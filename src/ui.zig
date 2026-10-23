const std = @import("std");
const dvui = @import("dvui");
const alphabet = @import("alphabet.zig");
const compose = @import("compose.zig");
const dict = @import("dict.zig");
const document = @import("document.zig");
const keymap = @import("keymap.zig");
const settings = @import("settings.zig");

const editor_size: f32 = 22;

pub const AppState = struct {
    mode: settings.Mode = .compose,
    settings: settings.Settings = .{},
    doc: document.Document,
    /// Focus the editor on the next frame. Set after clicks that would otherwise keep focus.
    refocus: bool = true,
    /// Border color from the previous frame, so the focused state is visible.
    editor_focused: bool = true,
    /// Chart and on-screen key clicks insert the capital letter.
    capital_clicks: bool = false,
};

pub fn create(gpa: std.mem.Allocator) !*AppState {
    const state = try gpa.create(AppState);
    state.* = .{ .doc = document.Document.init(gpa) };
    return state;
}

pub fn destroy(state: *AppState, gpa: std.mem.Allocator) void {
    state.doc.deinit();
    gpa.destroy(state);
}

pub fn frame(state: *AppState) !dvui.App.Result {
    {
        var scaler = dvui.scale(@src(), .{ .scale = &dvui.currentWindow().content_scale, .pinch_zoom = .global }, .{ .rect = .cast(dvui.windowRect()) });
        scaler.deinit();
    }

    var root = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .margin = dvui.Rect.all(8) });
    defer root.deinit();

    toolbar(state);
    optionRow(state);

    var body = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both });
    defer body.deinit();
    editor(state);
    panel(state);
    return .ok;
}

fn toolbar(state: *AppState) void {
    var bar = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
    defer bar.deinit();

    for (std.enums.values(settings.Mode)) |mode| {
        if (dvui.button(@src(), mode.label(), .{}, .{
            .id_extra = @intFromEnum(mode),
            .style = if (state.mode == mode) .highlight else .control,
        })) {
            setMode(state, mode);
        }
    }

    var spacer = dvui.box(@src(), .{}, .{ .expand = .horizontal });
    spacer.deinit();

    if (dvui.button(@src(), "Copy", .{}, .{})) {
        copyPage(state);
        armFocus(state);
    }
    if (dvui.button(@src(), "Clear", .{}, .{})) {
        attempt(state.doc.flush(state.mode, state.settings, dict.embedded));
        state.doc.clear();
        armFocus(state);
    }
}

fn optionRow(state: *AppState) void {
    var row = dvui.flexbox(@src(), .{ .justify_content = .start }, .{ .expand = .horizontal });
    defer row.deinit();

    switch (state.mode) {
        .compose => {
            const labels = [_][]const u8{ "Respelling", "Keyman" };
            var index: usize = @intFromEnum(state.settings.preset);
            if (dvui.dropdown(@src(), &labels, .{ .choice = &index }, .{}, .{ .min_size_content = .{ .w = 160, .h = 0 } })) {
                const preset: settings.Preset = @enumFromInt(index);
                if (preset != state.settings.preset) {
                    attempt(state.doc.flush(.compose, state.settings, dict.embedded));
                    state.settings.preset = preset;
                }
                armFocus(state);
            }
        },
        .map => {
            const labels = [_][]const u8{ "Mnemonic", "Book of Mormon 1869" };
            var index: usize = @intFromEnum(state.settings.layout);
            if (dvui.dropdown(@src(), &labels, .{ .choice = &index }, .{}, .{ .min_size_content = .{ .w = 220, .h = 0 } })) {
                state.settings.layout = @enumFromInt(index);
                armFocus(state);
            }
        },
        .translate => {},
    }

    if (state.mode == .compose or state.mode == .translate) {
        if (dvui.checkbox(@src(), &state.settings.book_alphabet, "38-letter book alphabet", .{})) {
            armFocus(state);
        }
    }
    if (state.mode == .translate) {
        if (dvui.checkbox(@src(), &state.settings.cot_caught_merge, "Merge cot and caught", .{})) {
            armFocus(state);
        }
    }
    if (dvui.checkbox(@src(), &state.capital_clicks, "Insert capitals", .{})) {
        armFocus(state);
    }
}

fn editor(state: *AppState) void {
    const border: dvui.ColorOrGradient = if (state.editor_focused)
        focusTint()
    else
        .{ .color = dvui.themeGet().border };
    var box = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .background = true,
        .border = dvui.Rect.all(2),
        .padding = dvui.Rect.all(8),
        .color_border = border,
        .tab_index = 1,
    });
    defer box.deinit();
    const wd = box.data();
    dvui.tabIndexSet(wd.id, 1, wd.rectScale().r);

    if (dvui.firstFrame(wd.id) or state.refocus) {
        dvui.focusWidget(wd.id, null, null);
        state.refocus = false;
        state.editor_focused = true;
    }
    var focused = dvui.focusedWidgetId() == wd.id;
    if (focused) dvui.wantTextInput(wd.borderRectScale().r.toNatural());

    var swallow_one = false;
    for (dvui.events()) |*event| {
        if (!dvui.eventMatch(event, .{ .id = wd.id, .r = wd.borderRectScale().r })) continue;
        switch (event.evt) {
            .mouse => |me| {
                if (me.action == .focus) {
                    // A click is a focus event followed by a press. An unhandled
                    // focus event clears focus, and the text scroller would
                    // take it. Claim it here. Leave the press unhandled so
                    // pronunciation buttons still see the click.
                    event.handle(@src(), wd);
                    dvui.focusWidget(wd.id, null, null);
                    focused = true;
                    state.editor_focused = true;
                    dvui.wantTextInput(wd.borderRectScale().r.toNatural());
                } else if (me.action == .press and (me.button == .left or me.button == .touch0)) {
                    dvui.focusWidget(wd.id, null, null);
                    focused = true;
                    state.editor_focused = true;
                }
            },
            .key => |ke| {
                if (ke.action == .up) continue;
                if (ke.action == .down and ke.matchBind("copy")) {
                    event.handle(@src(), wd);
                    copyPage(state);
                    continue;
                }
                if (ke.action == .down and ke.matchBind("cut")) {
                    event.handle(@src(), wd);
                    copyPage(state);
                    continue;
                }
                if (ke.action == .down and ke.matchBind("paste")) {
                    event.handle(@src(), wd);
                    paste(state);
                    continue;
                }
                if (ke.matchBind("text_start")) {
                    event.handle(@src(), wd);
                    attempt(state.doc.moveHome(state.mode, state.settings, dict.embedded));
                    continue;
                }
                if (ke.matchBind("text_end")) {
                    event.handle(@src(), wd);
                    attempt(state.doc.moveEnd(state.mode, state.settings, dict.embedded));
                    continue;
                }
                if (ke.matchBind("line_start")) {
                    event.handle(@src(), wd);
                    moveLine(state, true);
                    continue;
                }
                if (ke.matchBind("line_end")) {
                    event.handle(@src(), wd);
                    moveLine(state, false);
                    continue;
                }
                if (ke.mod.control() or ke.mod.command()) continue;

                switch (ke.code) {
                    .backspace => {
                        event.handle(@src(), wd);
                        attempt(state.doc.backspace());
                    },
                    .delete => {
                        event.handle(@src(), wd);
                        attempt(state.doc.deleteForward());
                    },
                    .left => if (!ke.mod.alt()) {
                        event.handle(@src(), wd);
                        attempt(state.doc.moveLeft(state.mode, state.settings, dict.embedded));
                    },
                    .right => if (!ke.mod.alt()) {
                        event.handle(@src(), wd);
                        attempt(state.doc.moveRight(state.mode, state.settings, dict.embedded));
                    },
                    .home => {
                        event.handle(@src(), wd);
                        moveLine(state, true);
                    },
                    .end => {
                        event.handle(@src(), wd);
                        moveLine(state, false);
                    },
                    .enter, .kp_enter => {
                        event.handle(@src(), wd);
                        attempt(state.doc.newline(state.mode, state.settings, dict.embedded));
                    },
                    else => if (state.mode == .map) {
                        if (keyChar(ke.code)) |ch| {
                            event.handle(@src(), wd);
                            attempt(state.doc.mapKey(state.settings, ch, ke.mod.shift(), ke.mod.alt()));
                            swallow_one = true;
                        }
                    },
                }
            },
            .text => |te| {
                const txt = switch (te.action) {
                    .value => |value| value.txt,
                    else => continue,
                };
                if (state.mode == .map and swallow_one and oneScalar(txt)) {
                    swallow_one = false;
                    event.handle(@src(), wd);
                    continue;
                }
                swallow_one = false;
                event.handle(@src(), wd);
                attempt(state.doc.typeBytes(state.mode, state.settings, dict.embedded, txt));
            },
            else => {},
        }
    }

    hint(state);
    if (state.mode == .compose) preview(state);
    if (state.mode == .translate) alternates(state);

    var scroll = dvui.scrollArea(@src(), .{ .horizontal = .auto }, .{ .expand = .both, .background = false, .border = .{} });
    defer scroll.deinit();
    const tl = openText(@src(), .{ .expand = .horizontal, .background = false, .padding = .{}, .margin = .{} });
    defer tl.deinit();
    addMixed(tl, state.doc.text.items[0..state.doc.cursor], null);
    if (state.doc.pending.items.len > 0) addMixed(tl, state.doc.pending.items, focusTint());
    if (focused) tl.addText("|", .{ .font = textFont(false, editor_size), .color_text = focusTint() });
    addMixed(tl, state.doc.text.items[state.doc.cursor..], null);

    state.editor_focused = dvui.focusedWidgetId() == wd.id;
}

fn hint(state: *AppState) void {
    const text: []const u8 = switch (state.mode) {
        .compose => "Sounds, not spellings. Shift capitalizes the next letter. \\ commits the short letter. The caret moves with the keyboard. Copy copies the whole page.",
        .map => "Each key is a letter. Shift capitalizes. Option types the number or punctuation. The caret moves with the keyboard. Copy copies the whole page.",
        .translate => "Looked up in the CMU dictionary. Click another pronunciation when a word has more than one. AH, including schwa, is written with short o. The caret moves with the keyboard. Copy copies the whole page.",
    };
    const tl = openText(@src(), .{ .expand = .horizontal, .background = false, .padding = .{}, .margin = .{}, .font = textFont(false, 14) });
    defer tl.deinit();
    tl.addText(text, .{});
}

fn preview(state: *AppState) void {
    var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .min_size_content = .{ .w = 0, .h = 28 } });
    defer row.deinit();
    const pending = state.doc.pending.items;
    if (pending.len == 0) return;

    dvui.label(@src(), "{s}", .{pending}, .{ .font = textFont(false, editor_size), .color_text = focusTint(), .gravity_y = 0.5 });
    switch (compose.decide(state.settings.preset, pending)) {
        .wait => |wait| {
            if (wait.ready) |seq| showGlyph(seq.letter, 1);
            if (wait.toward) |seq| {
                dvui.label(@src(), "…", .{}, .{ .gravity_y = 0.5, .id_extra = 2 });
                showGlyph(seq.letter, 3);
            }
        },
        .commit => |seq| showGlyph(seq.letter, 1),
        else => {},
    }
}

fn showGlyph(letter: alphabet.Letter, id_extra: usize) void {
    var buf: [4]u8 = undefined;
    const n = alphabet.encodeCp(letter.small(), &buf) catch return;
    dvui.label(@src(), "{s}", .{buf[0..n]}, .{
        .font = textFont(true, editor_size),
        .gravity_y = 0.5,
        .id_extra = id_extra,
    });
    dvui.label(@src(), "{s}", .{letter.name()}, .{ .gravity_y = 0.5, .id_extra = id_extra + 10 });
}

fn alternates(state: *AppState) void {
    if (state.doc.ambig.items.len == 0) return;
    var list = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .horizontal });
    defer list.deinit();
    for (state.doc.ambig.items, 0..) |item, index| {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .id_extra = index, .expand = .horizontal });
        defer row.deinit();
        dvui.label(@src(), "{s}", .{state.doc.englishOf(item)}, .{ .gravity_y = 0.5, .id_extra = index });
        for (0..item.count) |alt| {
            const bytes = state.doc.altBytes(item, @intCast(alt));
            if (dvui.button(@src(), bytes, .{}, .{
                .id_extra = index * 8 + alt,
                .font = textFont(true, 18),
                .style = if (alt == item.chosen) .highlight else .control,
                .margin = dvui.Rect.all(2),
                .padding = dvui.Rect.all(4),
            })) {
                attempt(state.doc.choose(index, @intCast(alt)));
                armFocus(state);
            }
        }
    }
}

fn panel(state: *AppState) void {
    var side = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .vertical,
        .min_size_content = .{ .w = 340, .h = 0 },
        .max_size_content = .width(380),
        .margin = .{ .x = 8 },
        .background = true,
        .border = dvui.Rect.all(1),
        .padding = dvui.Rect.all(4),
    });
    defer side.deinit();

    var scroll = dvui.scrollArea(@src(), .{ .horizontal = .auto }, .{ .expand = .both });
    defer scroll.deinit();

    if (state.mode == .map) keyboard(state);
    chart(state);
}

fn keyboard(state: *AppState) void {
    dvui.label(@src(), "On-screen keys", .{}, .{ .font = textFont(false, 14) });
    for (keymap.rows, 0..) |row, row_i| {
        var line = dvui.box(@src(), .{ .dir = .horizontal }, .{ .id_extra = row_i });
        defer line.deinit();
        for (row, 0..) |key, col| {
            var buf: [4]u8 = undefined;
            const glyph = keymap.lookup(state.settings.layout, key);
            const label: []const u8 = if (glyph) |letter| blk: {
                const cp = if (state.capital_clicks) letter.capitalCp() else letter.small();
                const n = alphabet.encodeCp(cp, &buf) catch 0;
                break :blk buf[0..n];
            } else buf[0..1];
            if (glyph == null) buf[0] = if (state.capital_clicks) keymap.shiftedLiteral(key) else key;
            const face = textFont(glyph != null, 16);
            if (dvui.button(@src(), label, .{}, .{
                .id_extra = row_i * 32 + col,
                .font = face,
                .min_size_content = .{ .w = 26, .h = 32 },
                .margin = dvui.Rect.all(1),
                .padding = dvui.Rect.all(2),
            })) {
                attempt(state.doc.mapKey(state.settings, key, state.capital_clicks, false));
                armFocus(state);
            }
        }
    }
}

fn chart(state: *AppState) void {
    dvui.label(@src(), "Letters", .{}, .{ .font = textFont(false, 14), .id_extra = 1 });
    if (state.settings.book_alphabet and (state.mode == .compose or state.mode == .translate)) {
        const note = openText(@src(), .{ .expand = .horizontal, .background = false, .padding = .{}, .font = textFont(false, 13) });
        defer note.deinit();
        note.addText("Typing oi and ew spells them with two letters. The chart still inserts the letter itself.", .{});
    }
    for (alphabet.all_letters, 0..) |letter, index| {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .id_extra = index, .expand = .horizontal });
        defer row.deinit();

        var buf: [4]u8 = undefined;
        const cp = if (state.capital_clicks) letter.capitalCp() else letter.small();
        const n = alphabet.encodeCp(cp, &buf) catch continue;
        if (dvui.button(@src(), buf[0..n], .{}, .{
            .id_extra = index,
            .font = textFont(true, 20),
            .min_size_content = .{ .w = 40, .h = 36 },
            .margin = dvui.Rect.all(2),
            .padding = dvui.Rect.all(2),
        })) {
            attempt(state.doc.insertLetter(state.mode, state.settings, dict.embedded, letter, state.capital_clicks));
            armFocus(state);
        }

        var keys_buf: [64]u8 = undefined;
        const keys = compose.keysFor(state.settings.preset, letter, &keys_buf);
        var text = dvui.box(@src(), .{ .dir = .vertical }, .{ .id_extra = index, .gravity_y = 0.5 });
        defer text.deinit();
        if (keys.len > 0) {
            dvui.label(@src(), "{s}", .{keys}, .{ .id_extra = index, .font = textFont(false, 14) });
        }
        dvui.label(@src(), "{s}  {s}  {s}", .{ letter.name(), letter.example(), letter.ipa() }, .{
            .id_extra = index + 100,
            .font = textFont(false, 13),
        });
    }
}

fn addMixed(tl: *dvui.TextLayoutWidget, bytes: []const u8, tint: ?dvui.ColorOrGradient) void {
    var i: usize = 0;
    while (i < bytes.len) {
        const start = i;
        const deseret = isDeseretAt(bytes, i);
        i = alphabet.nextScalar(bytes, i);
        while (i < bytes.len and isDeseretAt(bytes, i) == deseret) {
            i = alphabet.nextScalar(bytes, i);
        }
        var opts = dvui.Options{ .font = textFont(deseret, editor_size) };
        if (tint) |color| opts.color_text = color;
        tl.addText(bytes[start..i], opts);
    }
}

fn isDeseretAt(bytes: []const u8, i: usize) bool {
    if (i >= bytes.len) return false;
    const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch return false;
    if (i + len > bytes.len) return false;
    const cp = std.unicode.utf8Decode(bytes[i..][0..len]) catch return false;
    return alphabet.isDeseret(cp);
}

fn openText(src: std.builtin.SourceLocation, opts: dvui.Options) *dvui.TextLayoutWidget {
    // A wrapping text layout reports its min width as one long line. Cap that
    // so the editor does not push the letter chart off the window.
    var limited = opts;
    if (limited.max_size_content == null) limited.max_size_content = .width(280);
    const tl = dvui.widgetAlloc(dvui.TextLayoutWidget);
    tl.init(src, .{ .process_events_in_deinit = false }, limited);
    return tl;
}

fn textFont(deseret: bool, size: f32) dvui.Font {
    if (deseret) return .find(.{ .family = "Deseret", .size = size, .line_height_factor = 1.35 });
    var font = dvui.Font.theme(.body);
    font.size = size;
    font.line_height_factor = 1.35;
    return font;
}

fn focusTint() dvui.ColorOrGradient {
    return .{ .color = dvui.themeGet().focus };
}

fn copyPage(state: *AppState) void {
    attempt(state.doc.flush(state.mode, state.settings, dict.embedded));
    dvui.clipboardTextSet(state.doc.text.items);
    dvui.toast(@src(), .{ .message = "Copied the page" });
}

fn paste(state: *AppState) void {
    const clip = dvui.clipboardText();
    if (clip.len == 0) return;
    const copy = state.doc.gpa.dupe(u8, clip) catch {
        dvui.toast(@src(), .{ .message = "Out of memory" });
        return;
    };
    defer state.doc.gpa.free(copy);
    attempt(state.doc.typeBytes(state.mode, state.settings, dict.embedded, copy));
}

fn moveLine(state: *AppState, to_start: bool) void {
    attempt(state.doc.flush(state.mode, state.settings, dict.embedded));
    const text = state.doc.text.items;
    if (to_start) {
        var i = state.doc.cursor;
        while (i > 0) {
            const prev = alphabet.prevScalar(text, i);
            if (text[prev] == '\n') break;
            i = prev;
        }
        state.doc.cursor = i;
    } else {
        var i = state.doc.cursor;
        while (i < text.len and text[i] != '\n') {
            i = alphabet.nextScalar(text, i);
        }
        state.doc.cursor = i;
    }
}

fn setMode(state: *AppState, mode: settings.Mode) void {
    if (state.mode != mode) {
        attempt(state.doc.flush(state.mode, state.settings, dict.embedded));
        state.mode = mode;
    }
    armFocus(state);
}

fn armFocus(state: *AppState) void {
    state.refocus = true;
    state.editor_focused = true;
}

fn attempt(result: anytype) void {
    result catch dvui.toast(@src(), .{ .message = "Out of memory" });
}

fn oneScalar(txt: []const u8) bool {
    if (txt.len == 0) return false;
    const len = std.unicode.utf8ByteSequenceLength(txt[0]) catch return false;
    return len == txt.len;
}

fn keyChar(code: dvui.enums.Key) ?u8 {
    return switch (code) {
        .a => 'a',
        .b => 'b',
        .c => 'c',
        .d => 'd',
        .e => 'e',
        .f => 'f',
        .g => 'g',
        .h => 'h',
        .i => 'i',
        .j => 'j',
        .k => 'k',
        .l => 'l',
        .m => 'm',
        .n => 'n',
        .o => 'o',
        .p => 'p',
        .q => 'q',
        .r => 'r',
        .s => 's',
        .t => 't',
        .u => 'u',
        .v => 'v',
        .w => 'w',
        .x => 'x',
        .y => 'y',
        .z => 'z',
        .zero => '0',
        .one => '1',
        .two => '2',
        .three => '3',
        .four => '4',
        .five => '5',
        .six => '6',
        .seven => '7',
        .eight => '8',
        .nine => '9',
        .minus => '-',
        .equal => '=',
        .left_bracket => '[',
        .right_bracket => ']',
        .backslash => '\\',
        .semicolon => ';',
        .apostrophe => '\'',
        .comma => ',',
        .period => '.',
        .slash => '/',
        .grave => '`',
        .space => ' ',
        else => null,
    };
}
