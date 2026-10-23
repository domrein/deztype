const std = @import("std");

/// ARPABET phones, stress digits stripped. Values are stable in the packed dictionary.
pub const Phone = enum(u8) {
    aa,
    ae,
    ah,
    ao,
    aw,
    ay,
    b,
    ch,
    d,
    dh,
    eh,
    er,
    ey,
    f,
    g,
    hh,
    ih,
    iy,
    jh,
    k,
    l,
    m,
    n,
    ng,
    ow,
    oy,
    p,
    r,
    s,
    sh,
    t,
    th,
    uh,
    uw,
    v,
    w,
    y,
    z,
    zh,

    pub fn parse(name: []const u8) ?Phone {
        const fields = @typeInfo(Phone).@"enum".fields;
        inline for (fields) |field| {
            if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }
};

pub fn parseToken(token: []const u8) ?Phone {
    var end = token.len;
    while (end > 0 and std.ascii.isDigit(token[end - 1])) end -= 1;
    if (end == 0 or end > 2) return null;
    var buf: [2]u8 = undefined;
    for (token[0..end], 0..) |c, i| buf[i] = std.ascii.toLower(c);
    return Phone.parse(buf[0..end]);
}

test "stress digits are ignored" {
    try std.testing.expectEqual(Phone.ah, Phone.parse("ah").?);
    try std.testing.expectEqual(Phone.ah, parseToken("AH0").?);
    try std.testing.expectEqual(Phone.uw, parseToken("UW1").?);
    try std.testing.expectEqual(Phone.th, parseToken("TH").?);
    try std.testing.expect(parseToken("XYZ") == null);
}
