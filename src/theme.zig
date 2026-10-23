const dvui = @import("dvui");

/// Warm paper and pine ink. The mark uses the same pine and paper.
pub const ink = dvui.Color{ .r = 0x1C, .g = 0x24, .b = 0x28 };
pub const pine = dvui.Color{ .r = 0x1E, .g = 0x3F, .b = 0x38 };
pub const pine_hover = dvui.Color{ .r = 0x27, .g = 0x4E, .b = 0x45 };
pub const pine_press = dvui.Color{ .r = 0x17, .g = 0x33, .b = 0x2D };
pub const paper = dvui.Color{ .r = 0xFB, .g = 0xF8, .b = 0xF2 };
pub const canvas = dvui.Color{ .r = 0xF3, .g = 0xEE, .b = 0xE6 };
pub const line = dvui.Color{ .r = 0xE0, .g = 0xD7, .b = 0xC8 };
pub const muted = dvui.Color{ .r = 0x5E, .g = 0x58, .b = 0x50 };
pub const control_fill = dvui.Color{ .r = 0xE7, .g = 0xE0, .b = 0xD4 };
pub const control_hover = dvui.Color{ .r = 0xDC, .g = 0xD3, .b = 0xC4 };
pub const control_press = dvui.Color{ .r = 0xD0, .g = 0xC5, .b = 0xB4 };
pub const on_pine = dvui.Color{ .r = 0xF7, .g = 0xF3, .b = 0xEA };

pub fn theme() dvui.Theme {
    var next = dvui.Theme.builtin.adwaita_light;
    next.name = "Deztype";
    next.dark = false;
    next.focus = pine;
    next.text_select = .{ .r = 0xC9, .g = 0xD9, .b = 0xD1 };
    next.fill = paper;
    next.fill_hover = control_hover;
    next.fill_press = control_press;
    next.text = ink;
    next.border = line;
    next.corner = .round(7);
    next.font_body = next.font_body.withSize(15);
    next.font_heading = next.font_heading.withSize(16);
    next.font_title = next.font_title.withSize(22);
    next.font_mono = next.font_mono.withSize(14);
    next.control = .{
        .fill = control_fill,
        .fill_hover = control_hover,
        .fill_press = control_press,
        .text = ink,
        .border = line,
    };
    next.window = .{
        .fill = canvas,
        .text = ink,
        .border = line,
    };
    next.highlight = .{
        .fill = pine,
        .fill_hover = pine_hover,
        .fill_press = pine_press,
        .text = on_pine,
        .border = pine_press,
    };
    next.err = .{
        .fill = .{ .r = 0x8E, .g = 0x3A, .b = 0x34 },
        .fill_hover = .{ .r = 0xA3, .g = 0x48, .b = 0x41 },
        .fill_press = .{ .r = 0x76, .g = 0x2F, .b = 0x2A },
        .text = on_pine,
        .border = .{ .r = 0x6E, .g = 0x2C, .b = 0x28 },
    };
    return next;
}
