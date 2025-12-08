const zenithor = @import("zenithor");
const Stage = zenithor.Stage;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = @import("graphics_plugin");

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, Game }, .{});
}

fn setup(commands: anytype) !void {
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Triangle{ .x1 = 0, .y1 = -50, .x2 = 50, .y2 = 50, .x3 = -50, .y3 = 50 },
        BuiltinPlugin.Transform{ .x = 150, .y = 150, .z = 0 },
    });
}

fn changeColor(rendering_options: zenithor.ResourceMut(GraphicsPlugin.RenderingOptions)) !void {
    const g = rendering_options.value.pass_action.colors[0].clear_value.g + 0.01;
    rendering_options.value.pass_action.colors[0].clear_value.g = if (g > 1.0) 0.0 else g;
}

const Game = struct {
    pub const Components = .{};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = changeColor, .stage = .render },
        },
    };
};
