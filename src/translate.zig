const std = @import("std");
const alphabet = @import("alphabet.zig");
const phones = @import("phones.zig");
const settings = @import("settings.zig");

const Letter = alphabet.Letter;

pub const Case = enum { lower, capital, upper };

pub fn caseOf(word: []const u8) Case {
    var saw_letter = false;
    var first_upper = false;
    var has_upper = false;
    var has_lower = false;
    for (word) |c| {
        if (std.ascii.isUpper(c)) {
            if (!saw_letter) first_upper = true;
            saw_letter = true;
            has_upper = true;
        } else if (std.ascii.isLower(c)) {
            saw_letter = true;
            has_lower = true;
        }
    }
    if (has_upper and !has_lower) return .upper;
    if (first_upper) return .capital;
    return .lower;
}

pub fn applyCase(buf: []u8, style: Case) void {
    if (style == .lower) return;
    var i: usize = 0;
    var first = true;
    while (i < buf.len) {
        const len = std.unicode.utf8ByteSequenceLength(buf[i]) catch return;
        if (i + len > buf.len) return;
        const cp = std.unicode.utf8Decode(buf[i..][0..len]) catch return;
        var out = cp;
        const letter = cp >= 0x10428 and cp <= 0x1044F;
        if (letter and (style == .upper or (style == .capital and first))) out = cp - 0x28;
        if (letter) first = false;
        if (out != cp) {
            _ = std.unicode.utf8Encode(out, buf[i..][0..len]) catch return;
        }
        i += len;
    }
}

/// Write Deseret for one pronunciation. AH, stressed or not, is short o.
/// ER is short o plus er. There is no schwa letter.
pub fn renderPhones(phone_ids: []const u8, opts: settings.Settings, out: []u8) []const u8 {
    var len: usize = 0;
    var i: usize = 0;
    while (i < phone_ids.len) {
        const phone: phones.Phone = @enumFromInt(phone_ids[i]);
        if (!opts.book_alphabet and phone == .y and i + 1 < phone_ids.len and phone_ids[i + 1] == @intFromEnum(phones.Phone.uw)) {
            len = writeLetter(out, len, .ew);
            i += 2;
            continue;
        }
        switch (phone) {
            .iy => len = writeLetter(out, len, .long_i),
            .ey => len = writeLetter(out, len, .long_e),
            .aa => len = writeLetter(out, len, .long_a),
            .ao => len = writeLetter(out, len, if (opts.cot_caught_merge) .long_a else .long_ah),
            .ow => len = writeLetter(out, len, .long_o),
            .uw => len = writeLetter(out, len, .long_oo),
            .ih => len = writeLetter(out, len, .short_i),
            .eh => len = writeLetter(out, len, .short_e),
            .ae => len = writeLetter(out, len, .short_a),
            .ah => len = writeLetter(out, len, .short_o),
            .uh => len = writeLetter(out, len, .short_oo),
            .ay => len = writeLetter(out, len, .ay),
            .aw => len = writeLetter(out, len, .ow),
            .w => len = writeLetter(out, len, .wu),
            .y => len = writeLetter(out, len, .yee),
            .hh => len = writeLetter(out, len, .h),
            .p => len = writeLetter(out, len, .pee),
            .b => len = writeLetter(out, len, .bee),
            .t => len = writeLetter(out, len, .tee),
            .d => len = writeLetter(out, len, .dee),
            .ch => len = writeLetter(out, len, .chee),
            .jh => len = writeLetter(out, len, .jee),
            .k => len = writeLetter(out, len, .kay),
            .g => len = writeLetter(out, len, .gay),
            .f => len = writeLetter(out, len, .ef),
            .v => len = writeLetter(out, len, .vee),
            .th => len = writeLetter(out, len, .eth),
            .dh => len = writeLetter(out, len, .thee),
            .s => len = writeLetter(out, len, .es),
            .z => len = writeLetter(out, len, .zee),
            .sh => len = writeLetter(out, len, .esh),
            .zh => len = writeLetter(out, len, .zhee),
            .r => len = writeLetter(out, len, .er),
            .l => len = writeLetter(out, len, .el),
            .m => len = writeLetter(out, len, .em),
            .n => len = writeLetter(out, len, .en),
            .ng => len = writeLetter(out, len, .eng),
            .oy => {
                if (opts.book_alphabet) {
                    len = writeLetter(out, len, .long_ah);
                    len = writeLetter(out, len, .short_i);
                } else len = writeLetter(out, len, .oi);
            },
            .er => {
                len = writeLetter(out, len, .short_o);
                len = writeLetter(out, len, .er);
            },
        }
        i += 1;
    }
    return out[0..len];
}

fn writeLetter(out: []u8, len: usize, letter: Letter) usize {
    if (len + 4 > out.len) return len;
    const n = alphabet.encodeCp(letter.small(), out[len..]) catch return len;
    return len + n;
}

pub fn lowercase(word: []const u8, buf: []u8) []const u8 {
    const n = @min(word.len, buf.len);
    for (word[0..n], 0..) |c, i| buf[i] = std.ascii.toLower(c);
    return buf[0..n];
}

test "the few and coy" {
    const dh_ah = [_]u8{ @intFromEnum(phones.Phone.dh), @intFromEnum(phones.Phone.ah) };
    const f_y_uw = [_]u8{ @intFromEnum(phones.Phone.f), @intFromEnum(phones.Phone.y), @intFromEnum(phones.Phone.uw) };
    const oy = [_]u8{@intFromEnum(phones.Phone.oy)};
    const ao = [_]u8{ @intFromEnum(phones.Phone.k), @intFromEnum(phones.Phone.ao), @intFromEnum(phones.Phone.t) };

    var buf: [32]u8 = undefined;
    const the = renderPhones(&dh_ah, .{}, &buf);
    try expectLetters(the, &.{ .thee, .short_o });

    const few = renderPhones(&f_y_uw, .{}, &buf);
    try expectLetters(few, &.{ .ef, .ew });

    const few_book = renderPhones(&f_y_uw, .{ .book_alphabet = true }, &buf);
    try expectLetters(few_book, &.{ .ef, .yee, .long_oo });

    const coy = renderPhones(&oy, .{}, &buf);
    try expectLetters(coy, &.{.oi});
    const coy_book = renderPhones(&oy, .{ .book_alphabet = true }, &buf);
    try expectLetters(coy_book, &.{ .long_ah, .short_i });

    const caught = renderPhones(&ao, .{}, &buf);
    try expectLetters(caught, &.{ .kay, .long_ah, .tee });
    const merged = renderPhones(&ao, .{ .cot_caught_merge = true }, &buf);
    try expectLetters(merged, &.{ .kay, .long_a, .tee });
}

test "capitalization" {
    try std.testing.expectEqual(Case.capital, caseOf("Hello"));
    try std.testing.expectEqual(Case.upper, caseOf("HELLO"));
    try std.testing.expectEqual(Case.lower, caseOf("hello"));
    try std.testing.expectEqual(Case.capital, caseOf("Don't"));

    var buf: [8]u8 = undefined;
    const n: usize = alphabet.encodeCp(Letter.bee.small(), &buf) catch unreachable;
    const n2: usize = alphabet.encodeCp(Letter.short_i.small(), buf[n..]) catch unreachable;
    applyCase(buf[0 .. n + n2], .capital);
    const cp = std.unicode.utf8Decode(buf[0..4]) catch unreachable;
    try std.testing.expectEqual(Letter.bee.capitalCp(), cp);
}

fn expectLetters(bytes: []const u8, letters: []const Letter) !void {
    var i: usize = 0;
    for (letters) |letter| {
        const cp = try std.unicode.utf8Decode(bytes[i..][0..4]);
        try std.testing.expectEqual(letter.small(), cp);
        i += 4;
    }
    try std.testing.expectEqual(bytes.len, i);
}
