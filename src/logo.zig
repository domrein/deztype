const std = @import("std");

/// Square mark drawn in the window. Generated from assets/logo/mark.svg.
pub const mark_png = @embedFile("logo/mark-256.png");

/// Window icon. Smaller than the in-app mark so SDL can set it on X11,
/// where a 256px icon can exceed the maximum request size.
pub const icon_png = @embedFile("logo/mark-128.png");

fn expectSquarePng(bytes: []const u8, size: u32) !void {
    try std.testing.expect(std.mem.startsWith(u8, bytes, "\x89PNG\r\n\x1a\n"));
    const width = std.mem.readInt(u32, bytes[16..20], .big);
    const height = std.mem.readInt(u32, bytes[20..24], .big);
    try std.testing.expectEqual(size, width);
    try std.testing.expectEqual(size, height);
}

test "mark pngs are square" {
    try expectSquarePng(mark_png, 256);
    try expectSquarePng(icon_png, 128);
}
