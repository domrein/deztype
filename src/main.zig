const std = @import("std");
const dvui = @import("dvui");
const logo = @import("logo.zig");
const theme = @import("theme.zig");
const ui = @import("ui.zig");

pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 1080, .h = 720 },
            .min_size = .{ .w = 720, .h = 480 },
            .title = "Deztype",
            .org = "Dez Games",
            .icon = logo.icon_png,
            .window_init_options = .{
                .keybinds_zoom = true,
            },
        },
    },
    .frameFn = appFrame,
    .initFn = appInit,
    .deinitFn = appDeinit,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

var app_state: ?*ui.AppState = null;

pub fn appInit(win: *dvui.Window) !void {
    try dvui.addFont("Deseret", @embedFile("fonts/NotoSansDeseret-Regular.ttf"), null);
    win.themeSet(theme.theme());
    app_state = try ui.create(win.gpa);
}

pub fn appDeinit(win: *dvui.Window) void {
    if (app_state) |state| {
        ui.destroy(state, win.gpa);
        app_state = null;
    }
}

pub fn appFrame() !dvui.App.Result {
    const state = app_state orelse return .ok;
    return ui.frame(state);
}
