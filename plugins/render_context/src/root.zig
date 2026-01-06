const sokol = @import("sokol");
const sparze = @import("sparze");
const zenithor = @import("zenithor");
const builtin = @import("builtin");
const std = @import("std");

// Stable tag constants for ecosystem use
pub const Tags = struct {
    pub const PASS_BEGIN = "render-pass-begin";
    pub const GL_DEFAULTS = "sokol-gl-defaults";
    pub const GL_DRAW = "sokol-gl-draw";
    pub const PASS_END = "render-pass-end";
    pub const PASS_COMMIT = "render-pass-commit";
};

// Resource definition - just PassAction directly
pub const PassAction = sokol.gfx.PassAction;

pub const Components = .{};
pub const Resources = .{PassAction};
pub const Events = .{};

// Graphics subsystem initialization
fn initGraphics() void {
    sokol.gfx.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });

    sokol.gl.setup(.{
        .logger = .{ .func = sokol.log.func },
    });

    // Debug info
    if (builtin.mode == .Debug) {
        const backend = sokol.gfx.queryBackend();
        std.debug.print("[RenderContext] Graphics backend: {}\n", .{backend});
    }
}

fn shutdownGraphics() void {
    sokol.gl.shutdown();
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

/// Reset sokol.gl state and set up 2D orthographic projection.
/// Must run early in render stage so all 2D draw commands use correct state.
fn setupGL() void {
    // Reset sokol.gl to default state (clears matrices, textures, colors, etc.)
    sokol.gl.defaults();

    // Set up 2D orthographic projection:
    // - Origin at top-left (0,0)
    // - X increases rightward, Y increases downward
    // - Z range [-1, 1] for depth ordering
    sokol.gl.matrixModeProjection();
    sokol.gl.ortho(0, sokol.app.widthf(), sokol.app.heightf(), 0, -1, 1);
}

fn endPass() void {
    sokol.gfx.endPass();
}

/// Flush all sokol.gl 2D draw commands to the GPU.
/// Runs at high priority (200) after all 2D rendering systems but before endPass.
/// This allows SpritePlugin, GraphicsPlugin, and other plugins to queue sokol.gl
/// commands independently without needing to call draw() themselves.
fn flushGL() void {
    sokol.gl.draw();
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
        // Set up sokol.gl state and 2D projection right after beginPass
        .{
            .system = setupGL,
            .stage = .render,
            .config = .{
                .priority = -32767, // Right after beginPass
                .tags = &.{Tags.GL_DEFAULTS},
            },
        },
        // Flush sokol.gl 2D commands after all rendering systems (priority 200)
        // GraphicsPlugin draw systems: 0-120, SpritePlugin: 115
        // This ensures all 2D commands are flushed before endPass
        .{
            .system = flushGL,
            .stage = .render,
            .config = .{
                .priority = 200,
                .tags = &.{Tags.GL_DRAW},
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
