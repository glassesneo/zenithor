/// Example: 2D Rendering + Layering
///
/// Demonstrates 2D shape rendering with Z-ordering:
/// - All 2D shape types: Point, Line, Triangle, Rectangle, Circle
/// - Z-index depth ordering (lower z = front, higher z = back)
/// - Color component overrides (defaults to red if absent)
/// - 2D coordinate system: origin (0,0) at top-left, Y increases downward
///
/// See: plugins/shapes2d/CLAUDE.md
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Color = zenithor.Color;
const Shapes2DPlugin = @import("shapes2d_plugin");
const Renderer = @import("renderer_plugin");

pub fn main() !void {
    zenithor.run(.{Game}, .{});
}

const Game = struct {
    pub const Requires = .{Shapes2DPlugin};

    pub const Components = .{};
    pub const Resources = .{};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
    };
};

fn setup(commands: anytype, pass_action: zenithor.ResourceMut(Renderer.PassAction)) !void {
    pass_action.colors[0].clear_value = .{ .r = 0.15, .g = 0.15, .b = 0.2, .a = 1.0 };

    // === Z-Index Demonstration ===
    // Lower Z values render in front (closer to camera)
    // Higher Z values render behind (farther from camera)

    // Back layer (z = 0.5): Large rectangle
    _ = try commands.createEntityWith(.{
        Shapes2DPlugin.Rectangle{ .x = 300, .y = 300 },
        Transform{ .x = 350, .y = 200, .z = 0.5 },
        Color{ .r = 0.3, .g = 0.3, .b = 0.5, .a = 1.0 }, // Dark blue
    });

    // Middle layer (z = 0.0): Overlapping rectangles
    _ = try commands.createEntityWith(.{
        Shapes2DPlugin.Rectangle{ .x = 200, .y = 200 },
        Transform{ .x = 400, .y = 250, .z = 0.0 },
        Color.red,
    });
    _ = try commands.createEntityWith(.{
        Shapes2DPlugin.Rectangle{ .x = 200, .y = 200 },
        Transform{ .x = 500, .y = 300, .z = 0.0 },
        Color.green,
    });

    // Front layer (z = -0.5): Circle on top
    _ = try commands.createEntityWith(.{
        Shapes2DPlugin.Circle{ .radius = 80, .segments = 48 },
        Transform{ .x = 500, .y = 350, .z = -0.5 },
        Color.cyan,
    });

    // === Shape Showcase (right side) ===

    // Point (small dot)
    _ = try commands.createEntityWith(.{
        Shapes2DPlugin.Point{},
        Transform{ .x = 900, .y = 150, .z = 0 },
        Color.white,
    });

    // Line
    _ = try commands.createEntityWith(.{
        Shapes2DPlugin.Line{ .x = 150, .y = 50 },
        Transform{ .x = 850, .y = 200, .z = 0 },
        Color.yellow,
    });

    // Triangle
    _ = try commands.createEntityWith(.{
        Shapes2DPlugin.Triangle{
            .x1 = 0,
            .y1 = -60, // top
            .x2 = 60,
            .y2 = 60, // bottom-right
            .x3 = -60,
            .y3 = 60, // bottom-left
        },
        Transform{ .x = 920, .y = 350, .z = 0 },
        Color.magenta,
    });

    // Rectangle
    _ = try commands.createEntityWith(.{
        Shapes2DPlugin.Rectangle{ .x = 120, .y = 80 },
        Transform{ .x = 860, .y = 450, .z = 0 },
        Color.orange,
    });

    // Circle
    _ = try commands.createEntityWith(.{
        Shapes2DPlugin.Circle{ .radius = 50, .segments = 32 },
        Transform{ .x = 920, .y = 600, .z = 0 },
        Color.blue,
    });

    // === Color Override Demo (bottom) ===
    // Entity without Color component defaults to red

    // No Color component - defaults to red
    _ = try commands.createEntityWith(.{
        Shapes2DPlugin.Circle{ .radius = 40, .segments = 24 },
        Transform{ .x = 200, .y = 650, .z = 0 },
    });

    // With Color component override
    _ = try commands.createEntityWith(.{
        Shapes2DPlugin.Circle{ .radius = 40, .segments = 24 },
        Transform{ .x = 320, .y = 650, .z = 0 },
        Color.purple,
    });
}
