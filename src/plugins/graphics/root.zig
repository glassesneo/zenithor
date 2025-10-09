const sparze = @import("sparze");
const sokol = @import("sokol");

const system_module = @import("../../core/system.zig");
const Stage = system_module.Stage;
const RegisterFunc = system_module.RegisterFunc;

pub const Components = .{};

pub var pass_action: sokol.gfx.PassAction = .{};

fn init() !void {
    pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 1, .g = 1, .b = 1, .a = 0 },
    };
}

fn mainPass() !void {
    sokol.gfx.beginPass(.{ .action = pass_action, .swapchain = sokol.glue.swapchain() });
    sokol.gfx.endPass();
    sokol.gfx.commit();
}

pub fn build(
    registerSystem: RegisterFunc,
    registerStartupSystem: RegisterFunc,
    registerTerminateSystem: RegisterFunc,
) !void {
    _ = registerTerminateSystem;
    registerStartupSystem(init, .first);
    registerSystem(mainPass, .post_render);
}

const std = @import("std");
