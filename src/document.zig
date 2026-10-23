const std = @import("std");
const alphabet = @import("alphabet.zig");
const compose = @import("compose.zig");
const dict = @import("dict.zig");
const keymap = @import("keymap.zig");
const settings = @import("settings.zig");
const translate = @import("translate.zig");

const Letter = alphabet.Letter;

pub const Ambig = struct {
    start: usize,
    len: usize,
    chosen: u8,
    count: u8,
    alt_off: [4]u32,
    alt_len: [4]u32,
    src_off: u32,
    src_len: u32,
};

pub const Document = struct {
    gpa: std.mem.Allocator,
    text: std.ArrayList(u8) = .empty,
    cursor: usize = 0,
    pending: std.ArrayList(u8) = .empty,
    cap_next: bool = false,
    ambig: std.ArrayList(Ambig) = .empty,
    alts: std.ArrayList(u8) = .empty,
    english: std.ArrayList(u8) = .empty,

    pub fn init(gpa: std.mem.Allocator) Document {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Document) void {
        self.text.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.ambig.deinit(self.gpa);
        self.alts.deinit(self.gpa);
        self.english.deinit(self.gpa);
    }

    pub fn clear(self: *Document) void {
        self.text.clearRetainingCapacity();
        self.pending.clearRetainingCapacity();
        self.ambig.clearRetainingCapacity();
        self.alts.clearRetainingCapacity();
        self.english.clearRetainingCapacity();
        self.cursor = 0;
        self.cap_next = false;
    }

    pub fn typeBytes(self: *Document, mode: settings.Mode, opts: settings.Settings, lexicon: []const u8, bytes: []const u8) !void {
        var i: usize = 0;
        while (i < bytes.len) {
            const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch {
                i += 1;
                continue;
            };
            if (i + len > bytes.len) break;
            const cp = std.unicode.utf8Decode(bytes[i..][0..len]) catch {
                i += 1;
                continue;
            };
            if (cp < 128) {
                try self.typeAscii(mode, opts, lexicon, @intCast(cp));
            } else {
                try self.flush(mode, opts, lexicon);
                try self.insertCp(cp);
            }
            i += len;
        }
    }

    pub fn typeAscii(self: *Document, mode: settings.Mode, opts: settings.Settings, lexicon: []const u8, c: u8) !void {
        switch (mode) {
            .compose => try self.typeCompose(opts, c),
            .map => try self.typeMapPaste(opts, c),
            .translate => try self.typeTranslate(opts, lexicon, c),
        }
    }

    pub fn mapKey(self: *Document, opts: settings.Settings, key: u8, shift: bool, alt: bool) !void {
        self.cap_next = false;
        if (alt) {
            const literal: u8 = if (shift) keymap.shiftedLiteral(key) else key;
            try self.insertBytes(&[_]u8{literal});
            return;
        }
        if (keymap.lookup(opts.layout, key)) |letter| {
            const cp = if (shift) letter.capitalCp() else letter.small();
            try self.insertCp(cp);
            return;
        }
        const literal: u8 = if (shift) keymap.shiftedLiteral(key) else key;
        try self.insertBytes(&[_]u8{literal});
    }

    pub fn backspace(self: *Document) !void {
        if (self.pending.items.len > 0) {
            _ = self.pending.pop();
            if (self.pending.items.len == 0) self.cap_next = false;
            return;
        }
        if (self.cap_next) {
            self.cap_next = false;
            return;
        }
        if (self.cursor == 0) return;
        const start = alphabet.prevScalar(self.text.items, self.cursor);
        try self.splice(start, self.cursor - start, &.{});
        self.cursor = start;
    }

    pub fn deleteForward(self: *Document) !void {
        if (self.cursor >= self.text.items.len) return;
        const end = alphabet.nextScalar(self.text.items, self.cursor);
        try self.splice(self.cursor, end - self.cursor, &.{});
    }

    pub fn moveLeft(self: *Document, mode: settings.Mode, opts: settings.Settings, lexicon: []const u8) !void {
        if (self.pending.items.len > 0) {
            try self.flush(mode, opts, lexicon);
            return;
        }
        self.cursor = alphabet.prevScalar(self.text.items, self.cursor);
    }

    pub fn moveRight(self: *Document, mode: settings.Mode, opts: settings.Settings, lexicon: []const u8) !void {
        if (self.pending.items.len > 0) {
            try self.flush(mode, opts, lexicon);
            return;
        }
        self.cursor = alphabet.nextScalar(self.text.items, self.cursor);
    }

    pub fn moveHome(self: *Document, mode: settings.Mode, opts: settings.Settings, lexicon: []const u8) !void {
        try self.flush(mode, opts, lexicon);
        self.cursor = 0;
    }

    pub fn moveEnd(self: *Document, mode: settings.Mode, opts: settings.Settings, lexicon: []const u8) !void {
        try self.flush(mode, opts, lexicon);
        self.cursor = self.text.items.len;
    }

    pub fn newline(self: *Document, mode: settings.Mode, opts: settings.Settings, lexicon: []const u8) !void {
        try self.flush(mode, opts, lexicon);
        try self.insertBytes("\n");
    }

    pub fn flush(self: *Document, mode: settings.Mode, opts: settings.Settings, lexicon: []const u8) !void {
        switch (mode) {
            .compose => try self.flushCompose(opts),
            .translate => try self.flushTranslate(opts, lexicon),
            .map => {},
        }
    }

    pub fn forceShort(self: *Document, opts: settings.Settings) !void {
        const action = compose.decide(opts.preset, self.pending.items);
        switch (action) {
            .wait => |wait| if (wait.ready) |seq| try self.commitSequence(opts, seq),
            .commit => |seq| try self.commitSequence(opts, seq),
            else => {},
        }
        try self.pump(opts);
    }

    pub fn insertLetter(self: *Document, mode: settings.Mode, opts: settings.Settings, lexicon: []const u8, letter: Letter, capital: bool) !void {
        try self.flush(mode, opts, lexicon);
        const cp = if (capital) letter.capitalCp() else letter.small();
        try self.insertCp(cp);
    }

    pub fn choose(self: *Document, index: usize, alt: u8) !void {
        if (index >= self.ambig.items.len) return;
        const chosen = self.ambig.items[index];
        if (alt >= chosen.count) return;
        const bytes = self.altBytes(chosen, alt);
        var copy: [160]u8 = undefined;
        if (bytes.len > copy.len) return;
        @memcpy(copy[0..bytes.len], bytes);
        const old_len = chosen.len;
        const start = chosen.start;
        try self.text.replaceRange(self.gpa, start, old_len, copy[0..bytes.len]);
        self.ambig.items[index].len = bytes.len;
        self.ambig.items[index].chosen = alt;
        const delta: isize = @as(isize, @intCast(bytes.len)) - @as(isize, @intCast(old_len));
        if (self.cursor >= start and self.cursor <= start + old_len) {
            self.cursor = start + bytes.len;
        } else if (self.cursor > start + old_len) {
            self.cursor = @intCast(@as(isize, @intCast(self.cursor)) + delta);
        }
        for (self.ambig.items[index + 1 ..]) |*later| later.start = @intCast(@as(isize, @intCast(later.start)) + delta);
    }

    pub fn englishOf(self: *const Document, item: Ambig) []const u8 {
        const end = @min(self.english.items.len, item.src_off + item.src_len);
        if (item.src_off > self.english.items.len) return "";
        return self.english.items[item.src_off..end];
    }

    pub fn altBytes(self: *const Document, item: Ambig, alt: u8) []const u8 {
        const off = item.alt_off[alt];
        const len = item.alt_len[alt];
        return self.alts.items[off..][0..len];
    }

    fn typeCompose(self: *Document, opts: settings.Settings, c: u8) !void {
        if (c == '\\') {
            try self.forceShort(opts);
            return;
        }
        if (std.ascii.isAlphabetic(c)) {
            if (std.ascii.isUpper(c)) self.cap_next = true;
            try self.pending.append(self.gpa, std.ascii.toLower(c));
            try self.pump(opts);
            return;
        }
        try self.flushCompose(opts);
        try self.insertBytes(&[_]u8{c});
    }

    fn typeTranslate(self: *Document, opts: settings.Settings, lexicon: []const u8, c: u8) !void {
        if (std.ascii.isAlphabetic(c) or (c == '\'' and self.pending.items.len > 0)) {
            try self.pending.append(self.gpa, c);
            return;
        }
        try self.flushTranslate(opts, lexicon);
        try self.insertBytes(&[_]u8{c});
    }

    fn typeMapPaste(self: *Document, opts: settings.Settings, c: u8) !void {
        try self.mapKey(opts, if (c >= 'A' and c <= 'Z') c + 32 else c, c >= 'A' and c <= 'Z', false);
    }

    fn pump(self: *Document, opts: settings.Settings) !void {
        var guard: u8 = 0;
        while (self.pending.items.len > 0) {
            guard += 1;
            if (guard > 32) break;
            switch (compose.decide(opts.preset, self.pending.items)) {
                .empty, .wait => break,
                .commit => |seq| try self.commitSequence(opts, seq),
                .reject => {
                    const byte = self.pending.items[0];
                    self.pending.replaceRange(self.gpa, 0, 1, &.{}) catch |err| return err;
                    self.cap_next = false;
                    try self.insertBytes(&[_]u8{byte});
                },
            }
        }
    }

    fn flushCompose(self: *Document, opts: settings.Settings) !void {
        var guard: u8 = 0;
        while (self.pending.items.len > 0) {
            guard += 1;
            if (guard > 32) break;
            switch (compose.decide(opts.preset, self.pending.items)) {
                .empty => break,
                .commit => |seq| try self.commitSequence(opts, seq),
                .wait => |wait| {
                    if (wait.ready) |seq| {
                        try self.commitSequence(opts, seq);
                    } else {
                        try self.spillPending();
                    }
                },
                .reject => try self.spillPending(),
            }
        }
        self.cap_next = false;
    }

    fn spillPending(self: *Document) !void {
        const copy = try self.gpa.dupe(u8, self.pending.items);
        defer self.gpa.free(copy);
        self.pending.clearRetainingCapacity();
        self.cap_next = false;
        try self.insertBytes(copy);
    }

    fn commitSequence(self: *Document, opts: settings.Settings, seq: compose.Sequence) !void {
        if (!std.mem.startsWith(u8, self.pending.items, seq.keys)) return;
        try self.pending.replaceRange(self.gpa, 0, seq.keys.len, &.{});
        try self.writeLetter(opts, seq.letter);
    }

    fn writeLetter(self: *Document, opts: settings.Settings, letter: Letter) !void {
        if (opts.book_alphabet and letter == .oi) {
            try self.writeOne(.long_ah, true);
            try self.writeOne(.short_i, false);
            return;
        }
        if (opts.book_alphabet and letter == .ew) {
            try self.writeOne(.yee, true);
            try self.writeOne(.long_oo, false);
            return;
        }
        try self.writeOne(letter, true);
    }

    fn writeOne(self: *Document, letter: Letter, allow_cap: bool) !void {
        var cp = letter.small();
        if (allow_cap and self.cap_next) {
            cp = letter.capitalCp();
            self.cap_next = false;
        }
        try self.insertCp(cp);
    }

    fn flushTranslate(self: *Document, opts: settings.Settings, lexicon: []const u8) !void {
        if (self.pending.items.len == 0) return;
        const word = try self.gpa.dupe(u8, self.pending.items);
        defer self.gpa.free(word);
        self.pending.clearRetainingCapacity();

        var lower_buf: [64]u8 = undefined;
        const key = if (word.len <= lower_buf.len) translate.lowercase(word, &lower_buf) else word;
        const found = if (word.len <= lower_buf.len) dict.find(lexicon, key) else null;
        if (found == null or found.?.count() == 0) {
            try self.insertBytes(word);
            return;
        }
        const view = found.?;
        const n = @min(view.count(), 4);
        var rendered: [4][160]u8 = undefined;
        var lens: [4]usize = .{ 0, 0, 0, 0 };
        const style = translate.caseOf(word);
        var p: usize = 0;
        while (p < n) : (p += 1) {
            const phones = view.pron(p) orelse break;
            const raw = translate.renderPhones(phones, opts, &rendered[p]);
            lens[p] = raw.len;
            translate.applyCase(rendered[p][0..lens[p]], style);
        }
        if (lens[0] == 0) {
            try self.insertBytes(word);
            return;
        }
        const start = self.cursor;
        try self.insertBytes(rendered[0][0..lens[0]]);
        if (p > 1) {
            var item = Ambig{
                .start = start,
                .len = lens[0],
                .chosen = 0,
                .count = @intCast(p),
                .alt_off = .{ 0, 0, 0, 0 },
                .alt_len = .{ 0, 0, 0, 0 },
                .src_off = @intCast(self.english.items.len),
                .src_len = @intCast(word.len),
            };
            try self.english.appendSlice(self.gpa, word);
            for (0..p) |alt| {
                item.alt_off[alt] = @intCast(self.alts.items.len);
                item.alt_len[alt] = @intCast(lens[alt]);
                try self.alts.appendSlice(self.gpa, rendered[alt][0..lens[alt]]);
            }
            try self.ambig.append(self.gpa, item);
        }
    }

    fn insertCp(self: *Document, cp: u21) !void {
        var buf: [4]u8 = undefined;
        const n = try alphabet.encodeCp(cp, &buf);
        try self.insertBytes(buf[0..n]);
    }

    fn insertBytes(self: *Document, bytes: []const u8) !void {
        try self.splice(self.cursor, 0, bytes);
        self.cursor += bytes.len;
    }

    fn splice(self: *Document, start: usize, old_len: usize, bytes: []const u8) !void {
        try self.text.replaceRange(self.gpa, start, old_len, bytes);
        const end = start + old_len;
        const delta: isize = @as(isize, @intCast(bytes.len)) - @as(isize, @intCast(old_len));
        var i: usize = 0;
        while (i < self.ambig.items.len) {
            const a = &self.ambig.items[i];
            const a_end = a.start + a.len;
            if (a_end <= start) {
                i += 1;
            } else if (a.start >= end) {
                a.start = @intCast(@as(isize, @intCast(a.start)) + delta);
                i += 1;
            } else {
                _ = self.ambig.orderedRemove(i);
            }
        }
        if (self.cursor > end) {
            self.cursor = @intCast(@as(isize, @intCast(self.cursor)) + delta);
        } else if (self.cursor > start) {
            self.cursor = start + bytes.len;
        }
    }
};

test "respelling commits sounds and shift capitalizes" {
    const gpa = std.testing.allocator;
    var doc = Document.init(gpa);
    defer doc.deinit();
    try doc.typeBytes(.compose, .{}, &.{}, "th");
    try expectLetters(doc.text.items, &.{alphabet.Letter.eth});
    try doc.typeBytes(.compose, .{}, &.{}, "B");
    try std.testing.expectEqual(alphabet.Letter.bee.capitalCp(), try std.unicode.utf8Decode(doc.text.items[4..8]));
}

test "backslash commits the short letter" {
    const gpa = std.testing.allocator;
    var doc = Document.init(gpa);
    defer doc.deinit();
    try doc.typeBytes(.compose, .{}, &.{}, "e\\x");
    try expectLetters(doc.text.items[0..4], &.{alphabet.Letter.short_e});
    try expectLetters(doc.text.items[4..], &.{alphabet.Letter.zhee});
}

test "keyman ee is long e" {
    const gpa = std.testing.allocator;
    var doc = Document.init(gpa);
    defer doc.deinit();
    try doc.typeBytes(.compose, .{ .preset = .keyman }, &.{}, "ee");
    try expectLetters(doc.text.items, &.{alphabet.Letter.long_e});
}

test "map layouts" {
    const gpa = std.testing.allocator;
    var doc = Document.init(gpa);
    defer doc.deinit();
    try doc.mapKey(.{ .layout = .mnemonic }, 'b', true, false);
    try std.testing.expectEqual(alphabet.Letter.bee.capitalCp(), try std.unicode.utf8Decode(doc.text.items[0..4]));
    try doc.mapKey(.{ .layout = .mnemonic }, '1', false, true);
    try std.testing.expectEqualStrings("1", doc.text.items[4..]);

    doc.clear();
    try doc.mapKey(.{ .layout = .bom69 }, 'a', false, false);
    try expectLetters(doc.text.items, &.{alphabet.Letter.es});
}

test "translate the read and few" {
    const gpa = std.testing.allocator;
    var packed_bytes: std.ArrayList(u8) = .empty;
    defer packed_bytes.deinit(gpa);
    const Phone = @import("phones.zig").Phone;
    const dh_ah = [_]u8{ @intFromEnum(Phone.dh), @intFromEnum(Phone.ah) };
    const dh_iy = [_]u8{ @intFromEnum(Phone.dh), @intFromEnum(Phone.iy) };
    const r_iy_d = [_]u8{ @intFromEnum(Phone.r), @intFromEnum(Phone.iy), @intFromEnum(Phone.d) };
    const r_eh_d = [_]u8{ @intFromEnum(Phone.r), @intFromEnum(Phone.eh), @intFromEnum(Phone.d) };
    const f_y_uw = [_]u8{ @intFromEnum(Phone.f), @intFromEnum(Phone.y), @intFromEnum(Phone.uw) };
    const the_prons = [_][]const u8{ &dh_ah, &dh_iy };
    const read_prons = [_][]const u8{ &r_iy_d, &r_eh_d };
    const few_prons = [_][]const u8{&f_y_uw};
    const words = [_]dict.WordInput{
        .{ .word = "few", .prons = &few_prons },
        .{ .word = "read", .prons = &read_prons },
        .{ .word = "the", .prons = &the_prons },
    };
    try dict.encode(gpa, &words, &packed_bytes);

    var doc = Document.init(gpa);
    defer doc.deinit();
    try doc.typeBytes(.translate, .{}, packed_bytes.items, "The ");
    try std.testing.expectEqual(@as(u8, ' '), doc.text.items[doc.text.items.len - 1]);
    try std.testing.expectEqual(alphabet.Letter.thee.capitalCp(), try std.unicode.utf8Decode(doc.text.items[0..4]));
    try expectLetters(doc.text.items[4 .. doc.text.items.len - 1], &.{.short_o});

    const before = doc.text.items.len;
    try doc.typeBytes(.translate, .{}, packed_bytes.items, "read ");
    try std.testing.expectEqual(@as(usize, 2), doc.ambig.items.len);
    try doc.choose(1, 1);
    try expectLetters(doc.text.items[before .. doc.text.items.len - 1], &.{ .er, .short_e, .dee });

    doc.clear();
    try doc.typeBytes(.translate, .{}, packed_bytes.items, "few");
    try doc.flush(.translate, .{}, packed_bytes.items);
    try expectLetters(doc.text.items, &.{ .ef, .ew });
}

fn expectLetters(bytes: []const u8, letters: []const Letter) !void {
    try std.testing.expectEqual(letters.len * 4, bytes.len);
    for (letters, 0..) |letter, i| {
        const cp = try std.unicode.utf8Decode(bytes[i * 4 ..][0..4]);
        try std.testing.expectEqual(letter.small(), cp);
    }
}
