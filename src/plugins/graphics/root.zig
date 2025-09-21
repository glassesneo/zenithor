const sparze = @import("sparze");
const sokol = @import("sokol");

pub const Components = .{};

pub var pass_action: sokol.gfx.PassAction = .{};

fn mainPass() !void {
    sokol.gfx.beginPass(.{ .action = pass_action, .swapchain = sokol.glue.swapchain() });
    sokol.gfx.endPass();
    sokol.gfx.commit();
}

pub fn build(world: *sparze.World) !void {
    pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 1, .g = 1, .b = 1, .a = 0 },
    };
    world.registerSystem(mainPass, .post_render);
}

const std = @import("std");
