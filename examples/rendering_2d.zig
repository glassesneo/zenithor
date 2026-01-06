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
const ImGuiPlugin = @import("imgui_plugin");
const Renderer = @import("renderer_plugin");

pub fn main() !void {
    zenithor.run(.{ Shapes2DPlugin, ImGuiPlugin, Game }, .{});
}

const Game = struct {
    pub const Components = .{};
    pub const Resources = .{};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = drawUI, .stage = .render },
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

fn drawUI() void {
    ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = 10 }, .Once);
    ImGuiPlugin.setNextWindowSize(.{ .x = 280, .y = 350 }, .Once);

    if (ImGuiPlugin.begin("2D Rendering Demo", null, .None)) {
        ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Z-Index Ordering");
        ImGuiPlugin.separator();
        ImGuiPlugin.textWrapped("Left side shows overlapping shapes at different Z depths:");
        ImGuiPlugin.bulletText("z = -0.5 (front): Cyan circle");
        ImGuiPlugin.bulletText("z = 0.0 (middle): Red/Green rects");
        ImGuiPlugin.bulletText("z = 0.5 (back): Dark blue rect");

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "2D Shape Types");
        ImGuiPlugin.separator();
        ImGuiPlugin.bulletText("Point - single pixel");
        ImGuiPlugin.bulletText("Line - start to offset");
        ImGuiPlugin.bulletText("Triangle - 3 vertices");
        ImGuiPlugin.bulletText("Rectangle - width x height");
        ImGuiPlugin.bulletText("Circle - radius + segments");

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.5, .z = 0.5, .w = 1.0 }, "Color Override");
        ImGuiPlugin.separator();
        ImGuiPlugin.textWrapped("Bottom circles: left has no Color (defaults to red), right has Color.purple override.");

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "Coordinate System");
        ImGuiPlugin.separator();
        ImGuiPlugin.text("Origin: top-left (0, 0)");
        ImGuiPlugin.text("Y-axis: increases downward");
    }
    ImGuiPlugin.end();
}
