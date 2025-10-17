const std = @import("std");
const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = zenithor.GraphicsPlugin;
const TimePlugin = zenithor.TimePlugin;
const ImGuiPlugin = zenithor.ImGuiPlugin;
const DebugPlugin = zenithor.DebugPlugin;
const ig = ImGuiPlugin.ig;

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, TimePlugin, ImGuiPlugin, DebugPlugin, Game });
}

const Velocity = struct {
    x: f32,
    y: f32,

    pub fn format(self: Velocity, writer: anytype) !void {
        try writer.print("Velocity({d:.1} px/s, {d:.1} px/s)", .{ self.x, self.y });
    }
};

const CoordinateGroup = struct {
    BuiltinPlugin.Transform,
    Velocity,
};

const Game = struct {
    pub const Components = .{Velocity};
    pub const Groups = .{CoordinateGroup};

    pub fn build(registry: SystemRegistry) !void {
        registry.registerStartupSystem(setup, .first);
        registry.registerSystem(movement, .update);
        registry.registerSystem(debugInfo, .render);
    }
};

fn setup(commands: anytype) !void {
    // Create a rotating rectangle
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Rectangle{ .x = 50, .y = 50 },
        BuiltinPlugin.Transform{ .x = 300, .y = 200, .z = 0 },
        Velocity{ .x = 100, .y = 50 },
        DebugPlugin.Tracked{},
    });

    // Create a bouncing triangle
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Triangle{ .x1 = 0, .y1 = -30, .x2 = 30, .y2 = 30, .x3 = -30, .y3 = 30 },
        BuiltinPlugin.Transform{ .x = 150, .y = 150, .z = 0 },
        Velocity{ .x = -80, .y = 120 },
        DebugPlugin.Tracked{},
    });

    // Set white background
    GraphicsPlugin.pass_action.colors[0].clear_value = .{ .r = 1, .g = 1, .b = 1, .a = 1 };
}

fn movement(movement_query: zenithor.Group(CoordinateGroup)) !void {
    // Use scaled delta time for frame-rate independent movement
    const dt = TimePlugin.delta_time * TimePlugin.time_scale;
    const transforms = movement_query.getMutArrayOf(BuiltinPlugin.Transform);
    const velocities = movement_query.getMutArrayOf(Velocity);

    for (transforms, velocities) |*transform, *velocity| {
        // Update position
        transform.x += velocity.x * dt;
        transform.y += velocity.y * dt;

        // Bounce off window edges
        const width: f32 = 640.0;
        const height: f32 = 480.0;

        if (transform.x < 0 or width < transform.x) {
            velocity.x = -velocity.x;
            transform.x = if (transform.x < 0) 0 else width;
        }

        if (transform.y < 0 or height < transform.y) {
            velocity.y = -velocity.y;
            transform.y = if (transform.y < 0) 0 else height;
        }
    }
}

fn debugInfo(commands: anytype, tracked: zenithor.SingleTag(DebugPlugin.Tracked)) !void {
    // Pass all tracked entities to the debug window
    try DebugPlugin.openDebugWindow(.{
        BuiltinPlugin.Transform,
        Velocity,
        GraphicsPlugin.Rectangle,
        GraphicsPlugin.Triangle,
    }, commands, tracked.entities);
}
