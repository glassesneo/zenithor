const zenithor = @import("zenithor");
const Stage = zenithor.Stage;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = @import("graphics_plugin");
const TimePlugin = @import("time_plugin");
const ImGuiPlugin = @import("imgui_plugin");

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, TimePlugin, ImGuiPlugin, Game }, .{});
}

const Game = struct {
    pub const Components = .{};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = animate, .stage = .update },
            .{ .system = infoWindow, .stage = .render },
        },
    };
};

var animation_time: f32 = 0.0;

fn setup(commands: anytype, pass_action: zenithor.ResourceMut(GraphicsPlugin.RenderingOptions)) !void {
    pass_action.value.pass_action.colors[0].clear_value = .{ .r = 0.9, .g = 0.9, .b = 0.95, .a = 1.0 };

    // Create overlapping rectangles at different z-depths
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Rectangle{ .x = 200, .y = 200 },
        BuiltinPlugin.Transform{ .x = 400, .y = 250, .z = 0.5 },
        BuiltinPlugin.Color{ .r = 1.0, .g = 0.392, .b = 0.392, .a = 1.0 },
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Rectangle{ .x = 200, .y = 200 },
        BuiltinPlugin.Transform{ .x = 500, .y = 300, .z = 0.0 },
        BuiltinPlugin.Color{ .r = 1.0, .g = 1.0, .b = 0.392, .a = 1.0 },
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Rectangle{ .x = 200, .y = 200 },
        BuiltinPlugin.Transform{ .x = 600, .y = 350, .z = -0.5 },
        BuiltinPlugin.Color{ .r = 0.392, .g = 1.0, .b = 0.392, .a = 1.0 },
    });

    // Create triangles at different z-depths
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Triangle{ .x1 = 0, .y1 = -80, .x2 = 80, .y2 = 80, .x3 = -80, .y3 = 80 },
        BuiltinPlugin.Transform{ .x = 200, .y = 200, .z = 0.8 },
        BuiltinPlugin.Color{ .r = 0.392, .g = 1.0, .b = 0.392, .a = 1.0 },
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Triangle{ .x1 = 0, .y1 = -80, .x2 = 80, .y2 = 80, .x3 = -80, .y3 = 80 },
        BuiltinPlugin.Transform{ .x = 1000, .y = 200, .z = -0.8 },
        BuiltinPlugin.Color{ .r = 0.392, .g = 1.0, .b = 0.392, .a = 1.0 },
    });

    // Create lines at different z-depths
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Line{ .x = 300, .y = 0 },
        BuiltinPlugin.Transform{ .x = 300, .y = 600, .z = 0.3 },
        BuiltinPlugin.Color{ .r = 0.392, .g = 0.392, .b = 1.0, .a = 1.0 },
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Line{ .x = 300, .y = 0 },
        BuiltinPlugin.Transform{ .x = 700, .y = 600, .z = -0.3 },
        BuiltinPlugin.Color{ .r = 0.392, .g = 0.392, .b = 1.0, .a = 1.0 },
    });

    // Create points at different z-depths
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Point{},
        BuiltinPlugin.Transform{ .x = 640, .y = 100, .z = 0.9 },
        BuiltinPlugin.Color{ .r = 1.0, .g = 0.392, .b = 1.0, .a = 1.0 },
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Point{},
        BuiltinPlugin.Transform{ .x = 640, .y = 150, .z = -0.9 },
        BuiltinPlugin.Color{ .r = 1.0, .g = 0.392, .b = 1.0, .a = 1.0 },
    });
}

fn animate(time: zenithor.Resource(TimePlugin.Time)) !void {
    const dt = time.value.delta_time;
    animation_time += dt;
}

fn infoWindow() !void {
    const pos = ImGuiPlugin.ImVec2{ .x = 10, .y = 720 };
    ImGuiPlugin.setNextWindowPos(pos, ImGuiPlugin.ImGuiCond.Once);

    const size = ImGuiPlugin.ImVec2{ .x = 420, .y = 70 };
    ImGuiPlugin.setNextWindowSize(size, ImGuiPlugin.ImGuiCond.Once);

    var window_open = true;
    if (ImGuiPlugin.begin("Z-Index Demo", &window_open, .None)) {
        ImGuiPlugin.textColored(ImGuiPlugin.ImVec4{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Z-Index Depth Ordering Demo");
        ImGuiPlugin.separator();
        ImGuiPlugin.spacing();

        ImGuiPlugin.text("This demo shows 2D shapes at different z-depths:");
        ImGuiPlugin.bulletText("Lower z values render in front (closer)");
        ImGuiPlugin.bulletText("Higher z values render behind (farther)");
        ImGuiPlugin.bulletText("Middle entities animate between depths");
        ImGuiPlugin.spacing();

        ImGuiPlugin.text("Animation time:");
        ImGuiPlugin.sameLine();
        ImGuiPlugin.textFmt("{d:.2}s", .{animation_time});

        ImGuiPlugin.spacing();
    }
    ImGuiPlugin.end();
}

const std = @import("std");
