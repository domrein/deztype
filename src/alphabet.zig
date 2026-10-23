const std = @import("std");

/// Small Deseret letters in Unicode order. Capital is 0x28 code points earlier.
pub const Letter = enum(u21) {
    long_i = 0x10428,
    long_e = 0x10429,
    long_a = 0x1042A,
    long_ah = 0x1042B,
    long_o = 0x1042C,
    long_oo = 0x1042D,
    short_i = 0x1042E,
    short_e = 0x1042F,
    short_a = 0x10430,
    short_ah = 0x10431,
    short_o = 0x10432,
    short_oo = 0x10433,
    ay = 0x10434,
    ow = 0x10435,
    wu = 0x10436,
    yee = 0x10437,
    h = 0x10438,
    pee = 0x10439,
    bee = 0x1043A,
    tee = 0x1043B,
    dee = 0x1043C,
    chee = 0x1043D,
    jee = 0x1043E,
    kay = 0x1043F,
    gay = 0x10440,
    ef = 0x10441,
    vee = 0x10442,
    eth = 0x10443,
    thee = 0x10444,
    es = 0x10445,
    zee = 0x10446,
    esh = 0x10447,
    zhee = 0x10448,
    er = 0x10449,
    el = 0x1044A,
    em = 0x1044B,
    en = 0x1044C,
    eng = 0x1044D,
    oi = 0x1044E,
    ew = 0x1044F,

    pub fn small(self: Letter) u21 {
        return @intFromEnum(self);
    }

    pub fn capitalCp(self: Letter) u21 {
        return @intFromEnum(self) - 0x28;
    }

    pub fn name(self: Letter) []const u8 {
        return switch (self) {
            .long_i => "long i",
            .long_e => "long e",
            .long_a => "long a",
            .long_ah => "long ah",
            .long_o => "long o",
            .long_oo => "long oo",
            .short_i => "short i",
            .short_e => "short e",
            .short_a => "short a",
            .short_ah => "short ah",
            .short_o => "short o",
            .short_oo => "short oo",
            .ay => "ay",
            .ow => "ow",
            .wu => "wu",
            .yee => "yee",
            .h => "h",
            .pee => "pee",
            .bee => "bee",
            .tee => "tee",
            .dee => "dee",
            .chee => "chee",
            .jee => "jee",
            .kay => "kay",
            .gay => "gay",
            .ef => "ef",
            .vee => "vee",
            .eth => "eth",
            .thee => "thee",
            .es => "es",
            .zee => "zee",
            .esh => "esh",
            .zhee => "zhee",
            .er => "er",
            .el => "el",
            .em => "em",
            .en => "en",
            .eng => "eng",
            .oi => "oi",
            .ew => "ew",
        };
    }

    pub fn example(self: Letter) []const u8 {
        return switch (self) {
            .long_i => "beet",
            .long_e => "bait",
            .long_a => "cot",
            .long_ah => "caught",
            .long_o => "coat",
            .long_oo => "boot",
            .short_i => "kit",
            .short_e => "bet",
            .short_a => "bat",
            .short_ah => "pot",
            .short_o => "but",
            .short_oo => "book",
            .ay => "ice",
            .ow => "cow",
            .wu => "wet",
            .yee => "yes",
            .h => "hat",
            .pee => "pea",
            .bee => "bee",
            .tee => "tea",
            .dee => "day",
            .chee => "chew",
            .jee => "jay",
            .kay => "key",
            .gay => "go",
            .ef => "fee",
            .vee => "vat",
            .eth => "thin",
            .thee => "then",
            .es => "see",
            .zee => "zoo",
            .esh => "she",
            .zhee => "vision",
            .er => "run",
            .el => "let",
            .em => "me",
            .en => "no",
            .eng => "sing",
            .oi => "boy",
            .ew => "few",
        };
    }

    pub fn ipa(self: Letter) []const u8 {
        return switch (self) {
            .long_i => "/i/",
            .long_e => "/eɪ/",
            .long_a => "/ɑ/",
            .long_ah => "/ɔ/",
            .long_o => "/oʊ/",
            .long_oo => "/u/",
            .short_i => "/ɪ/",
            .short_e => "/ɛ/",
            .short_a => "/æ/",
            .short_ah => "/ɒ/",
            .short_o => "/ʌ/",
            .short_oo => "/ʊ/",
            .ay => "/aɪ/",
            .ow => "/aʊ/",
            .wu => "/w/",
            .yee => "/j/",
            .h => "/h/",
            .pee => "/p/",
            .bee => "/b/",
            .tee => "/t/",
            .dee => "/d/",
            .chee => "/tʃ/",
            .jee => "/dʒ/",
            .kay => "/k/",
            .gay => "/ɡ/",
            .ef => "/f/",
            .vee => "/v/",
            .eth => "/θ/",
            .thee => "/ð/",
            .es => "/s/",
            .zee => "/z/",
            .esh => "/ʃ/",
            .zhee => "/ʒ/",
            .er => "/r/",
            .el => "/l/",
            .em => "/m/",
            .en => "/n/",
            .eng => "/ŋ/",
            .oi => "/ɔɪ/",
            .ew => "/ju/",
        };
    }
};

pub const all_letters = std.enums.values(Letter);

pub fn isDeseret(cp: u21) bool {
    return cp >= 0x10400 and cp <= 0x1044F;
}

pub fn appendCp(list: *std.ArrayList(u8), gpa: std.mem.Allocator, cp: u21) !void {
    var buf: [4]u8 = undefined;
    const n = try std.unicode.utf8Encode(cp, &buf);
    try list.appendSlice(gpa, buf[0..n]);
}

pub fn encodeCp(cp: u21, buf: []u8) !u3 {
    return std.unicode.utf8Encode(cp, buf);
}

pub fn prevScalar(text: []const u8, cursor: usize) usize {
    if (cursor == 0) return 0;
    var i = cursor - 1;
    while (i > 0 and text[i] & 0xc0 == 0x80) i -= 1;
    return i;
}

pub fn nextScalar(text: []const u8, cursor: usize) usize {
    if (cursor >= text.len) return text.len;
    const len = std.unicode.utf8ByteSequenceLength(text[cursor]) catch 1;
    return @min(text.len, cursor + len);
}

comptime {
    for (all_letters, 0..) |letter, i| {
        if (@intFromEnum(letter) != 0x10428 + i) {
            @compileError("Deseret letter enum must stay in Unicode order");
        }
    }
}

test "capital offset stays inside the block" {
    for (all_letters) |letter| {
        const cap = letter.capitalCp();
        try std.testing.expect(cap >= 0x10400 and cap < 0x10428);
        try std.testing.expect(letter.small() - cap == 0x28);
    }
}
