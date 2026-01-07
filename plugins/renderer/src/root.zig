const sokol = @import("sokol");
const sparze = @import("sparze");
const zenithor = @import("zenithor");
const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.renderer);

// Stable tag constants for ecosystem use
pub const Tags = struct {
    pub const PASS_BEGIN = "render-pass-begin";
    pub const PASS_END = "render-pass-end";
    pub const PASS_COMMIT = "render-pass-commit";
};

// Resource definition - just PassAction directly
pub const PassAction = sokol.gfx.PassAction;

pub const Components = .{};
pub const Resources = .{PassAction};
pub const Events = .{};

// Graphics subsystem initialization (sokol.gfx only)
fn initGraphics() void {
    sokol.gfx.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });

    // Debug info
    if (builtin.mode == .Debug) {
        const backend = sokol.gfx.queryBackend();
        log.info("Graphics backend: {}", .{backend});
    }
}

fn shutdownGraphics() void {
    sokol.gfx.shutdown();
}

// Lifecycle systems with EXTREME priorities
fn initPassAction(commands: anytype) !void {
    var default_action = sokol.gfx.PassAction{};
    default_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.2, .g = 0.2, .b = 0.3, .a = 1.0 },
    };
    default_action.depth = .{
        .load_action = .CLEAR,
        .clear_value = 1.0,
    };
    commands.setResource(PassAction, default_action);
}

fn beginPass(pass_action: sparze.Resource(PassAction)) void {
    // Note: sparze.Resource(T) returns *const T directly (pointer)
    sokol.gfx.beginPass(.{
        .action = pass_action.*,
        .swapchain = sokol.glue.swapchain(),
    });
}

fn endPass() void {
    sokol.gfx.endPass();
}

fn commit() void {
    sokol.gfx.commit();
}

pub const systems = .{
    .startup = &.{
        .{
            .system = initGraphics,
            .stage = .first,
            .config = .{
                .priority = -32768, // Initialize graphics FIRST
            },
        },
        .{ .system = initPassAction, .stage = .first },
    },
    .main = &.{
        // CRITICAL: Use extreme priorities to guarantee execution order
        .{
            .system = beginPass,
            .stage = .render,
            .config = .{
                .priority = -32768, // Lowest possible - always first in .render
                .tags = &.{Tags.PASS_BEGIN},
            },
        },
        .{
            .system = endPass,
            .stage = .render,
            .config = .{
                .priority = 32760, // Very high - runs last in .render, before .post_render
                .tags = &.{Tags.PASS_END},
            },
        },
        .{
            .system = commit,
            .stage = .post_render,
            .config = .{
                .priority = -32768, // Lowest priority - runs first in .post_render
                .tags = &.{Tags.PASS_COMMIT},
            },
        },
    },
    .terminate = &.{
        .{ .system = shutdownGraphics, .stage = .last },
    },
};
