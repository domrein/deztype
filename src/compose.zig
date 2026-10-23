const std = @import("std");
const alphabet = @import("alphabet.zig");
const settings = @import("settings.zig");

const Letter = alphabet.Letter;

pub const Sequence = struct {
    keys: []const u8,
    letter: Letter,
};

const respelling = [_]Sequence{
    .{ .keys = "i", .letter = .short_i },
    .{ .keys = "ii", .letter = .long_i },
    .{ .keys = "ie", .letter = .ay },
    .{ .keys = "e", .letter = .short_e },
    .{ .keys = "ee", .letter = .long_i },
    .{ .keys = "ea", .letter = .long_i },
    .{ .keys = "ey", .letter = .long_e },
    .{ .keys = "ew", .letter = .ew },
    .{ .keys = "a", .letter = .short_a },
    .{ .keys = "ah", .letter = .long_a },
    .{ .keys = "aw", .letter = .long_ah },
    .{ .keys = "au", .letter = .short_ah },
    .{ .keys = "ai", .letter = .long_e },
    .{ .keys = "o", .letter = .short_o },
    .{ .keys = "oh", .letter = .long_o },
    .{ .keys = "oa", .letter = .long_o },
    .{ .keys = "oo", .letter = .long_oo },
    .{ .keys = "ou", .letter = .ow },
    .{ .keys = "ow", .letter = .ow },
    .{ .keys = "oi", .letter = .oi },
    .{ .keys = "oy", .letter = .oi },
    .{ .keys = "u", .letter = .short_oo },
    .{ .keys = "uu", .letter = .long_oo },
    .{ .keys = "uh", .letter = .short_o },
    .{ .keys = "yu", .letter = .ew },
    .{ .keys = "b", .letter = .bee },
    .{ .keys = "c", .letter = .chee },
    .{ .keys = "ch", .letter = .chee },
    .{ .keys = "d", .letter = .dee },
    .{ .keys = "dh", .letter = .thee },
    .{ .keys = "f", .letter = .ef },
    .{ .keys = "g", .letter = .gay },
    .{ .keys = "h", .letter = .h },
    .{ .keys = "j", .letter = .jee },
    .{ .keys = "k", .letter = .kay },
    .{ .keys = "l", .letter = .el },
    .{ .keys = "m", .letter = .em },
    .{ .keys = "n", .letter = .en },
    .{ .keys = "ng", .letter = .eng },
    .{ .keys = "p", .letter = .pee },
    .{ .keys = "ph", .letter = .ef },
    .{ .keys = "q", .letter = .eng },
    .{ .keys = "r", .letter = .er },
    .{ .keys = "s", .letter = .es },
    .{ .keys = "sh", .letter = .esh },
    .{ .keys = "t", .letter = .tee },
    .{ .keys = "th", .letter = .eth },
    .{ .keys = "v", .letter = .vee },
    .{ .keys = "w", .letter = .wu },
    .{ .keys = "x", .letter = .zhee },
    .{ .keys = "y", .letter = .yee },
    .{ .keys = "z", .letter = .zee },
    .{ .keys = "zh", .letter = .zhee },
};

/// Name-based sequences from the SIL Keyman Deseret keyboard.
/// `ee` is long e (bait), not the vowel in beet. `oo` is long o (coat).
const keyman = [_]Sequence{
    .{ .keys = "ii", .letter = .long_i },
    .{ .keys = "i", .letter = .short_i },
    .{ .keys = "ee", .letter = .long_e },
    .{ .keys = "e", .letter = .short_e },
    .{ .keys = "aa", .letter = .long_a },
    .{ .keys = "a", .letter = .short_a },
    .{ .keys = "aw", .letter = .long_ah },
    .{ .keys = "au", .letter = .short_ah },
    .{ .keys = "oo", .letter = .long_o },
    .{ .keys = "o", .letter = .short_o },
    .{ .keys = "uu", .letter = .long_oo },
    .{ .keys = "u", .letter = .short_oo },
    .{ .keys = "ie", .letter = .ay },
    .{ .keys = "ou", .letter = .ow },
    .{ .keys = "ow", .letter = .ow },
    .{ .keys = "oi", .letter = .oi },
    .{ .keys = "oy", .letter = .oi },
    .{ .keys = "eu", .letter = .ew },
    .{ .keys = "ew", .letter = .ew },
    .{ .keys = "b", .letter = .bee },
    .{ .keys = "t", .letter = .tee },
    .{ .keys = "d", .letter = .dee },
    .{ .keys = "c", .letter = .chee },
    .{ .keys = "j", .letter = .jee },
    .{ .keys = "k", .letter = .kay },
    .{ .keys = "g", .letter = .gay },
    .{ .keys = "f", .letter = .ef },
    .{ .keys = "ph", .letter = .ef },
    .{ .keys = "v", .letter = .vee },
    .{ .keys = "th", .letter = .eth },
    .{ .keys = "dh", .letter = .thee },
    .{ .keys = "s", .letter = .es },
    .{ .keys = "z", .letter = .zee },
    .{ .keys = "sh", .letter = .esh },
    .{ .keys = "zh", .letter = .zhee },
    .{ .keys = "r", .letter = .er },
    .{ .keys = "l", .letter = .el },
    .{ .keys = "m", .letter = .em },
    .{ .keys = "n", .letter = .en },
    .{ .keys = "ng", .letter = .eng },
    .{ .keys = "w", .letter = .wu },
    .{ .keys = "y", .letter = .yee },
    .{ .keys = "h", .letter = .h },
    .{ .keys = "p", .letter = .pee },
};

pub fn sequences(preset: settings.Preset) []const Sequence {
    return switch (preset) {
        .respelling => &respelling,
        .keyman => &keyman,
    };
}

pub const Wait = struct {
    /// Longest complete sequence that is a prefix of the pending keys.
    ready: ?Sequence = null,
    /// Shortest sequence that the pending keys could still grow into.
    toward: ?Sequence = null,
};

pub const Action = union(enum) {
    empty,
    /// Pending keys are a prefix of a longer sequence. Do not commit yet.
    wait: Wait,
    /// Commit this sequence and feed the leftover keys back in.
    commit: Sequence,
    /// The first character starts no sequence.
    reject,
};

pub fn decide(preset: settings.Preset, pending: []const u8) Action {
    if (pending.len == 0) return .empty;

    var longest: ?Sequence = null;
    var toward: ?Sequence = null;
    for (sequences(preset)) |seq| {
        if (std.mem.startsWith(u8, pending, seq.keys)) {
            if (longest == null or seq.keys.len > longest.?.keys.len) longest = seq;
        } else if (std.mem.startsWith(u8, seq.keys, pending) and seq.keys.len > pending.len) {
            if (toward == null or seq.keys.len < toward.?.keys.len) toward = seq;
        }
    }

    if (longest) |seq| {
        if (seq.keys.len < pending.len) return .{ .commit = seq };
        if (toward != null) return .{ .wait = .{ .ready = seq, .toward = toward } };
        return .{ .commit = seq };
    }
    if (toward != null) return .{ .wait = .{ .ready = null, .toward = toward } };
    return .reject;
}

pub fn keysFor(preset: settings.Preset, letter: Letter, buf: []u8) []const u8 {
    var len: usize = 0;
    for (sequences(preset)) |seq| {
        if (seq.letter != letter) continue;
        if (len > 0 and len + 2 <= buf.len) {
            buf[len] = ',';
            buf[len + 1] = ' ';
            len += 2;
        }
        if (len + seq.keys.len > buf.len) break;
        @memcpy(buf[len..][0..seq.keys.len], seq.keys);
        len += seq.keys.len;
    }
    return buf[0..len];
}

test "respelling th waits then commits" {
    try std.testing.expect(decide(.respelling, "t") == .wait);
    try std.testing.expectEqual(Letter.tee, decide(.respelling, "t").wait.ready.?.letter);
    try std.testing.expectEqual(Letter.eth, decide(.respelling, "th").commit.letter);
    try std.testing.expectEqual(Letter.eth, decide(.respelling, "the").commit.letter);
}

test "respelling ee is beet and keyman ee is bait" {
    try std.testing.expectEqual(Letter.long_i, decide(.respelling, "ee").commit.letter);
    try std.testing.expectEqual(Letter.long_e, decide(.keyman, "ee").commit.letter);
    try std.testing.expectEqual(Letter.long_o, decide(.keyman, "oo").commit.letter);
    try std.testing.expectEqual(Letter.long_oo, decide(.respelling, "oo").commit.letter);
}

test "every letter has a sequence and keys are unique" {
    for (std.enums.values(settings.Preset)) |preset| {
        var seen = [_]bool{false} ** alphabet.all_letters.len;
        for (sequences(preset)) |seq| {
            seen[@intFromEnum(seq.letter) - 0x10428] = true;
            for (sequences(preset)) |other| {
                if (seq.keys.ptr == other.keys.ptr) continue;
                try std.testing.expect(!std.mem.eql(u8, seq.keys, other.keys));
            }
        }
        for (seen) |ok| try std.testing.expect(ok);
    }
}
