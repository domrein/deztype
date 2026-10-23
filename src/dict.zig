const std = @import("std");
const phones = @import("phones.zig");

pub const embedded = @embedFile("data/cmudict.dzd");

pub const WordInput = struct {
    word: []const u8,
    prons: []const []const u8,
};

pub const View = struct {
    word: []const u8,
    body: []const u8,

    pub fn count(self: View) usize {
        if (self.body.len == 0) return 0;
        return self.body[0];
    }

    pub fn pron(self: View, index: usize) ?[]const u8 {
        var i: usize = 1;
        var n: usize = 0;
        while (n < self.count()) : (n += 1) {
            if (i >= self.body.len) return null;
            const len = self.body[i];
            i += 1;
            if (i + len > self.body.len) return null;
            if (n == index) return self.body[i..][0..len];
            i += len;
        }
        return null;
    }
};

pub fn encode(gpa: std.mem.Allocator, words: []const WordInput, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(gpa, "DZD1");
    try appendU32(gpa, out, @intCast(words.len));
    try out.appendNTimes(gpa, 0, words.len * 4);

    for (words, 0..) |word, index| {
        const off: u32 = @intCast(out.items.len);
        writeU32(out.items[8 + index * 4 ..][0..4], off);
        if (word.word.len > 255 or word.prons.len > 255) return error.TooBig;
        try out.append(gpa, @intCast(word.word.len));
        try out.appendSlice(gpa, word.word);
        try out.append(gpa, @intCast(word.prons.len));
        for (word.prons) |pron| {
            if (pron.len > 255) return error.TooBig;
            try out.append(gpa, @intCast(pron.len));
            try out.appendSlice(gpa, pron);
        }
    }
}

pub fn find(data: []const u8, word: []const u8) ?View {
    if (data.len < 8 or !std.mem.eql(u8, data[0..4], "DZD1")) return null;
    const count = std.mem.readInt(u32, data[4..8], .little);
    if (data.len < 8 + @as(usize, count) * 4) return null;

    var lo: u32 = 0;
    var hi: u32 = count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const off = std.mem.readInt(u32, data[8 + @as(usize, mid) * 4 ..][0..4], .little);
        const view = viewAt(data, off) orelse return null;
        switch (std.mem.order(u8, word, view.word)) {
            .eq => return view,
            .lt => hi = mid,
            .gt => lo = mid + 1,
        }
    }
    return null;
}

fn viewAt(data: []const u8, off: u32) ?View {
    if (off >= data.len) return null;
    const start = @as(usize, off);
    const len = data[start];
    if (start + 1 + len >= data.len) return null;
    const word = data[start + 1 .. start + 1 + len];
    return .{
        .word = word,
        .body = data[start + 1 + len ..],
    };
}

fn appendU32(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: u32) !void {
    var buf: [4]u8 = undefined;
    writeU32(&buf, value);
    try out.appendSlice(gpa, &buf);
}

fn writeU32(buf: *[4]u8, value: u32) void {
    std.mem.writeInt(u32, buf, value, .little);
}

pub fn parsePhoneToken(token: []const u8) ?u8 {
    const phone = phones.parseToken(token) orelse return null;
    return @intFromEnum(phone);
}

test "round trip a few words" {
    const gpa = std.testing.allocator;
    const the_a = [_]u8{ @intFromEnum(phones.Phone.dh), @intFromEnum(phones.Phone.ah) };
    const the_b = [_]u8{ @intFromEnum(phones.Phone.dh), @intFromEnum(phones.Phone.iy) };
    const read_a = [_]u8{ @intFromEnum(phones.Phone.r), @intFromEnum(phones.Phone.iy), @intFromEnum(phones.Phone.d) };
    var packed_bytes: std.ArrayList(u8) = .empty;
    defer packed_bytes.deinit(gpa);

    const the_prons = [_][]const u8{ &the_a, &the_b };
    const read_prons = [_][]const u8{&read_a};
    const words = [_]WordInput{
        .{ .word = "read", .prons = &read_prons },
        .{ .word = "the", .prons = &the_prons },
    };
    try encode(gpa, &words, &packed_bytes);

    const the = find(packed_bytes.items, "the").?;
    try std.testing.expectEqual(@as(usize, 2), the.count());
    try std.testing.expectEqualSlices(u8, &the_a, the.pron(0).?);
    try std.testing.expectEqualSlices(u8, &the_b, the.pron(1).?);
    try std.testing.expectEqualSlices(u8, &read_a, find(packed_bytes.items, "read").?.pron(0).?);
    try std.testing.expect(find(packed_bytes.items, "missing") == null);
}

test "embedded dictionary has the and read" {
    const the = find(embedded, "the") orelse return error.MissingThe;
    try std.testing.expect(the.count() >= 2);
    const read = find(embedded, "read") orelse return error.MissingRead;
    try std.testing.expect(read.count() >= 2);
    try std.testing.expect(find(embedded, "through") != null);
}
