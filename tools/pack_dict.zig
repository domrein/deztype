const std = @import("std");
const dict = @import("dict");

const max_prons = 8;
const max_phones = 64;

const Item = struct {
    word: []const u8,
    prons: std.ArrayList([]const u8),
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 3) {
        std.debug.print("usage: pack_dict <cmudict.dict> <out.dzd>\n", .{});
        return error.Usage;
    }

    const input = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], gpa, .unlimited);
    defer gpa.free(input);

    var items: std.ArrayList(Item) = .empty;
    defer items.deinit(arena);

    var lines: usize = 0;
    var skipped: usize = 0;
    var truncated: usize = 0;

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    var line_no: usize = 0;
    while (line_iter.next()) |raw| {
        line_no += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#' or line[0] == ';') continue;
        lines += 1;

        const split = std.mem.indexOfAny(u8, line, " \t") orelse {
            skipped += 1;
            continue;
        };
        var word = line[0..split];
        if (std.mem.indexOfScalar(u8, word, '(')) |paren| word = word[0..paren];
        if (!validWord(word)) {
            skipped += 1;
            continue;
        }

        var rest = std.mem.trim(u8, line[split..], " \t");
        if (std.mem.indexOfScalar(u8, rest, '#')) |hash| {
            rest = std.mem.trim(u8, rest[0..hash], " \t");
        }
        const pron = parsePhones(arena, rest, word, line_no) catch |err| switch (err) {
            error.EmptyPronunciation => {
                skipped += 1;
                continue;
            },
            else => return err,
        };
        var prons: std.ArrayList([]const u8) = .empty;
        try prons.append(arena, pron);
        try items.append(arena, .{ .word = word, .prons = prons });
    }

    std.mem.sort(Item, items.items, {}, lessThan);

    var words: std.ArrayList(dict.WordInput) = .empty;
    defer words.deinit(arena);

    var i: usize = 0;
    while (i < items.items.len) {
        var item = &items.items[i];
        var j = i + 1;
        while (j < items.items.len and std.mem.eql(u8, items.items[j].word, item.word)) : (j += 1) {
            for (items.items[j].prons.items) |pron| {
                if (hasPron(item, pron)) continue;
                if (item.prons.items.len >= max_prons) {
                    truncated += 1;
                    continue;
                }
                try item.prons.append(arena, pron);
            }
        }
        try words.append(arena, .{ .word = item.word, .prons = item.prons.items });
        i = j;
    }

    var packed_bytes: std.ArrayList(u8) = .empty;
    defer packed_bytes.deinit(gpa);
    try dict.encode(gpa, words.items, &packed_bytes);
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = args[2],
        .data = packed_bytes.items,
    });

    var stdout_buf: [256]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buf);
    try stdout.interface.print(
        "packed {d} words from {d} entries ({d} skipped, {d} extra pronunciations dropped) into {d} bytes\n",
        .{ words.items.len, lines, skipped, truncated, packed_bytes.items.len },
    );
    try stdout.interface.flush();
}

fn lessThan(_: void, a: Item, b: Item) bool {
    return std.mem.order(u8, a.word, b.word) == .lt;
}

fn hasPron(item: *const Item, pron: []const u8) bool {
    for (item.prons.items) |have| {
        if (std.mem.eql(u8, have, pron)) return true;
    }
    return false;
}

fn validWord(word: []const u8) bool {
    if (word.len == 0 or word.len > 255) return false;
    if (word[0] < 'a' or word[0] > 'z') return false;
    for (word[1..]) |c| {
        if (!((c >= 'a' and c <= 'z') or c == '\'')) return false;
    }
    return true;
}

fn parsePhones(arena: std.mem.Allocator, rest: []const u8, word: []const u8, line_no: usize) ![]const u8 {
    var ids: [max_phones]u8 = undefined;
    var n: usize = 0;
    var tokens = std.mem.tokenizeAny(u8, rest, " \t");
    while (tokens.next()) |token| {
        if (n >= ids.len) {
            std.debug.print("line {d}: too many phones in '{s}'\n", .{ line_no, word });
            return error.TooManyPhones;
        }
        ids[n] = dict.parsePhoneToken(token) orelse {
            std.debug.print("line {d}: unknown phone '{s}' in '{s}'\n", .{ line_no, token, word });
            return error.UnknownPhone;
        };
        n += 1;
    }
    if (n == 0) return error.EmptyPronunciation;
    return arena.dupe(u8, ids[0..n]);
}
