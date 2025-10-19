const std = @import("std");
const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = zenithor.GraphicsPlugin;
const ImGuiPlugin = zenithor.ImGuiPlugin;
const TimePlugin = zenithor.TimePlugin;
const ig = ImGuiPlugin.ig;

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, TimePlugin, Game });
}

const Velocity = struct {
    x: f32,
    y: f32,
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
        registry.registerSystem(displayTimeInfo, .render);
        registry.registerSystem(timeControls, .render);
    }
};

fn setup(commands: anytype) !void {
    // Create a rotating rectangle
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Rectangle{ .x = 50, .y = 50 },
        BuiltinPlugin.Transform{ .x = 300, .y = 200, .z = 0 },
        Velocity{ .x = 100, .y = 50 },
    });

    // Create a bouncing triangle
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Triangle{ .x1 = 0, .y1 = -30, .x2 = 30, .y2 = 30, .x3 = -30, .y3 = 30 },
        BuiltinPlugin.Transform{ .x = 150, .y = 150, .z = 0 },
        Velocity{ .x = -80, .y = 120 },
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

fn displayTimeInfo() !void {
    ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 300, .y = 150 }, ig.ImGuiCond_Once);

    if (ig.igBegin("Time Information", null, ig.ImGuiWindowFlags_None)) {
        ig.igText("FPS: %.1f", TimePlugin.fps);
        ig.igText("Delta Time: %.4f s (%.2f ms)", TimePlugin.delta_time, TimePlugin.delta_time * 1000.0);
        ig.igText("Total Time: %.2f s", TimePlugin.total_time);
        ig.igText("Frame Count: %llu", TimePlugin.frame_count);
        ig.igSeparator();
        ig.igText("Time Scale: %.2fx", TimePlugin.time_scale);
    }
    ig.igEnd();
}

fn timeControls() !void {
    ig.igSetNextWindowPos(.{ .x = 10, .y = 170 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 300, .y = 150 }, ig.ImGuiCond_Once);

    if (ig.igBegin("Time Controls", null, ig.ImGuiWindowFlags_None)) {
        _ = ig.igSliderFloat("Time Scale", &TimePlugin.time_scale, 0.0, 2.0);

        if (ig.igButton("Pause")) {
            TimePlugin.time_scale = 0.0;
        }
        ig.igSameLine();
        if (ig.igButton("Normal")) {
            TimePlugin.time_scale = 1.0;
        }
        ig.igSameLine();
        if (ig.igButton("Fast")) {
            TimePlugin.time_scale = 2.0;
        }

        if (ig.igButton("Slow Motion (0.5x)")) {
            TimePlugin.time_scale = 0.5;
        }
        ig.igSameLine();
        if (ig.igButton("Very Slow (0.1x)")) {
            TimePlugin.time_scale = 0.1;
        }
    }
    ig.igEnd();
}
