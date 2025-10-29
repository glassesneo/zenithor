const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = zenithor.GraphicsPlugin;

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, Game });
}

fn setup(commands: anytype) !void {
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Triangle{ .x1 = 0, .y1 = -50, .x2 = 50, .y2 = 50, .x3 = -50, .y3 = 50 },
        BuiltinPlugin.Transform{ .x = 150, .y = 150, .z = 0 },
    });
}

fn changeColor(pass_action: zenithor.Resource(GraphicsPlugin.PassAction)) !void {
    var action = pass_action.value;
    const g = action.colors[0].clear_value.g + 0.01;
    action.colors[0].clear_value.g = if (g > 1.0) 0.0 else g;
}

const Game = struct {
    pub const Components = .{};

    pub fn build(registry: SystemRegistry) !void {
        registry.registerStartupSystem(setup, .first);
        registry.registerSystem(changeColor, .render);
    }
};
