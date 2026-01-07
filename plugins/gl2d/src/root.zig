//! GL2D Plugin - 2D Rendering Pipeline via sokol.gl
//!
//! Manages sokol.gl state for 2D rendering:
//! - Initializes sokol.gl subsystem
//! - Sets up 2D orthographic projection each frame
//! - Flushes sokol.gl draw commands after all 2D rendering
//!
//! Plugins that use sokol.gl for 2D rendering (Shapes2D, Sprite) should
//! depend on this plugin via `pub const Requires = .{GL2DPlugin}`.

const sokol = @import("sokol");
const sparze = @import("sparze");
const RendererPlugin = @import("renderer_plugin");

// Stable tag constants for ecosystem use
pub const Tags = struct {
    pub const GL_DEFAULTS = "sokol-gl-defaults";
    pub const GL_DRAW = "sokol-gl-draw";
};

pub const Components = .{};
pub const Resources = .{};
pub const Events = .{};
pub const Groups = .{};

// Depends on RendererPlugin for render pass lifecycle
pub const Requires = .{RendererPlugin};

/// Initialize sokol.gl subsystem.
/// Runs at startup after sokol.gfx is initialized by RendererPlugin.
fn initGL() void {
    sokol.gl.setup(.{
        .logger = .{ .func = sokol.log.func },
    });
}

/// Shutdown sokol.gl subsystem.
/// Runs at terminate before sokol.gfx is shut down.
fn shutdownGL() void {
    sokol.gl.shutdown();
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

/// Flush all sokol.gl 2D draw commands to the GPU.
/// Runs at high priority (200) after all 2D rendering systems but before endPass.
/// This allows SpritePlugin, Shapes2DPlugin, and other plugins to queue sokol.gl
/// commands independently without needing to call draw() themselves.
fn flushGL() void {
    sokol.gl.draw();
}

pub const systems = .{
    .startup = &.{
        .{
            .system = initGL,
            .stage = .first,
            .config = .{
                // After RendererPlugin's initGraphics (-32768)
                .priority = -32700,
            },
        },
    },
    .main = &.{
        // Set up sokol.gl state and 2D projection right after beginPass
        .{
            .system = setupGL,
            .stage = .render,
            .config = .{
                // After RendererPlugin's beginPass (-32768)
                .priority = -32767,
                .tags = &.{Tags.GL_DEFAULTS},
            },
        },
        // Flush sokol.gl 2D commands after all rendering systems (priority 200)
        // Shapes2DPlugin draw systems: 0-default, SpritePlugin: 115
        // This ensures all 2D commands are flushed before endPass
        .{
            .system = flushGL,
            .stage = .render,
            .config = .{
                .priority = 200,
                .tags = &.{Tags.GL_DRAW},
            },
        },
    },
    .terminate = &.{
        .{
            .system = shutdownGL,
            .stage = .last,
            .config = .{
                // Before RendererPlugin's shutdownGraphics
                .priority = -100,
            },
        },
    },
};
