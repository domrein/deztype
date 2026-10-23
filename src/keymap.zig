const std = @import("std");
const alphabet = @import("alphabet.zig");
const settings = @import("settings.zig");

const Letter = alphabet.Letter;

pub const Binding = struct {
    key: u8,
    letter: Letter,
};

/// Letter keys are the nearest English consonant or short vowel.
/// Long vowels and the letters English spells with two characters sit on the digit row.
const mnemonic = [_]Binding{
    .{ .key = 'a', .letter = .short_a },
    .{ .key = 'b', .letter = .bee },
    .{ .key = 'c', .letter = .chee },
    .{ .key = 'd', .letter = .dee },
    .{ .key = 'e', .letter = .short_e },
    .{ .key = 'f', .letter = .ef },
    .{ .key = 'g', .letter = .gay },
    .{ .key = 'h', .letter = .h },
    .{ .key = 'i', .letter = .short_i },
    .{ .key = 'j', .letter = .jee },
    .{ .key = 'k', .letter = .kay },
    .{ .key = 'l', .letter = .el },
    .{ .key = 'm', .letter = .em },
    .{ .key = 'n', .letter = .en },
    .{ .key = 'o', .letter = .short_o },
    .{ .key = 'p', .letter = .pee },
    .{ .key = 'q', .letter = .eng },
    .{ .key = 'r', .letter = .er },
    .{ .key = 's', .letter = .es },
    .{ .key = 't', .letter = .tee },
    .{ .key = 'u', .letter = .short_oo },
    .{ .key = 'v', .letter = .vee },
    .{ .key = 'w', .letter = .wu },
    .{ .key = 'x', .letter = .zhee },
    .{ .key = 'y', .letter = .yee },
    .{ .key = 'z', .letter = .zee },
    .{ .key = '1', .letter = .long_i },
    .{ .key = '2', .letter = .long_e },
    .{ .key = '3', .letter = .long_a },
    .{ .key = '4', .letter = .long_ah },
    .{ .key = '5', .letter = .long_o },
    .{ .key = '6', .letter = .long_oo },
    .{ .key = '7', .letter = .short_ah },
    .{ .key = '8', .letter = .ay },
    .{ .key = '9', .letter = .ow },
    .{ .key = '0', .letter = .eth },
    .{ .key = '-', .letter = .thee },
    .{ .key = '=', .letter = .esh },
    .{ .key = '[', .letter = .oi },
    .{ .key = ']', .letter = .ew },
};

/// Frequency layout published by the Illinois Deseret Consortium for the 1869 Book of Mormon.
/// Oi and ew were not in that book; they sit on the bracket keys.
const bom69 = [_]Binding{
    .{ .key = '1', .letter = .esh },
    .{ .key = '2', .letter = .gay },
    .{ .key = '3', .letter = .jee },
    .{ .key = '4', .letter = .chee },
    .{ .key = '5', .letter = .yee },
    .{ .key = '6', .letter = .short_oo },
    .{ .key = '7', .letter = .long_ah },
    .{ .key = '8', .letter = .eth },
    .{ .key = '9', .letter = .long_o },
    .{ .key = '0', .letter = .long_a },
    .{ .key = '-', .letter = .ow },
    .{ .key = '=', .letter = .zhee },
    .{ .key = 'q', .letter = .bee },
    .{ .key = 'w', .letter = .wu },
    .{ .key = 'e', .letter = .h },
    .{ .key = 'r', .letter = .ef },
    .{ .key = 't', .letter = .thee },
    .{ .key = 'y', .letter = .long_e },
    .{ .key = 'u', .letter = .long_oo },
    .{ .key = 'i', .letter = .el },
    .{ .key = 'o', .letter = .short_o },
    .{ .key = 'p', .letter = .long_i },
    .{ .key = 'a', .letter = .es },
    .{ .key = 's', .letter = .tee },
    .{ .key = 'd', .letter = .er },
    .{ .key = 'f', .letter = .dee },
    .{ .key = 'g', .letter = .kay },
    .{ .key = 'h', .letter = .short_e },
    .{ .key = 'j', .letter = .short_a },
    .{ .key = 'k', .letter = .en },
    .{ .key = 'l', .letter = .short_i },
    .{ .key = 'z', .letter = .zee },
    .{ .key = 'x', .letter = .em },
    .{ .key = 'c', .letter = .eng },
    .{ .key = 'v', .letter = .vee },
    .{ .key = 'b', .letter = .pee },
    .{ .key = 'n', .letter = .ay },
    .{ .key = 'm', .letter = .short_ah },
    .{ .key = '[', .letter = .oi },
    .{ .key = ']', .letter = .ew },
};

pub fn bindings(layout: settings.Layout) []const Binding {
    return switch (layout) {
        .mnemonic => &mnemonic,
        .bom69 => &bom69,
    };
}

pub fn lookup(layout: settings.Layout, key: u8) ?Letter {
    const lower = if (key >= 'A' and key <= 'Z') key + 32 else key;
    for (bindings(layout)) |binding| {
        if (binding.key == lower) return binding.letter;
    }
    return null;
}

pub fn shiftedLiteral(key: u8) u8 {
    return switch (key) {
        'a'...'z' => key - 32,
        '1' => '!',
        '2' => '@',
        '3' => '#',
        '4' => '$',
        '5' => '%',
        '6' => '^',
        '7' => '&',
        '8' => '*',
        '9' => '(',
        '0' => ')',
        '-' => '_',
        '=' => '+',
        '[' => '{',
        ']' => '}',
        '\\' => '|',
        ';' => ':',
        '\'' => '"',
        ',' => '<',
        '.' => '>',
        '/' => '?',
        '`' => '~',
        else => key,
    };
}

pub const rows = [_][]const u8{
    "1234567890-=",
    "qwertyuiop[]",
    "asdfghjkl;'",
    "zxcvbnm,./",
};

test "mnemonic and book layouts disagree on a" {
    try std.testing.expectEqual(Letter.short_a, lookup(.mnemonic, 'a').?);
    try std.testing.expectEqual(Letter.es, lookup(.bom69, 'a').?);
    try std.testing.expectEqual(Letter.bee, lookup(.mnemonic, 'B').?);
    try std.testing.expect(lookup(.mnemonic, ';') == null);
}

test "layouts cover every letter once" {
    for (std.enums.values(settings.Layout)) |layout| {
        var seen = [_]bool{false} ** alphabet.all_letters.len;
        for (bindings(layout)) |binding| {
            const index = @intFromEnum(binding.letter) - 0x10428;
            try std.testing.expect(!seen[index]);
            seen[index] = true;
        }
        for (seen) |ok| try std.testing.expect(ok);
    }
}
