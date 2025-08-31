const std = @import("std");
const sparze = @import("sparze");
const testing = std.testing;
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;

const state = struct {
    var pass_action: sg.PassAction = .{};
};

export fn appInit() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    };
    std.debug.print("Backend: {}\n", .{sg.queryBackend()});
}

export fn appFrame() void {
    // const g = state.pass_action.colors[0].clear_value.g + 0.01;
    // state.pass_action.colors[0].clear_value.g = if (g > 1.0) 0.0 else g;
    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.endPass();
    sg.commit();
}

export fn appCleanup() void {
    sg.shutdown();
}

pub const Application = struct {
    pub fn init() Application {
        return .{};
    }

    pub fn run(_: *Application) void {
        sapp.run(.{
            .init_cb = appInit,
            .frame_cb = appFrame,
            .cleanup_cb = appCleanup,
            .width = 640,
            .height = 480,
            .icon = .{ .sokol_default = true },
            .window_title = "window",
            .logger = .{ .func = slog.func },
            .win32_console_attach = true,
        });
    }
};
