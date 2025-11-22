const std = @import("std");
const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = @import("graphics_plugin");
const ImGuiPlugin = @import("imgui_plugin");
const TimePlugin = @import("time_plugin");

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, TimePlugin, Game });
}

fn setupPassAction(pass_action: zenithor.Resource(GraphicsPlugin.PassAction)) !void {
    var action = pass_action.value;
    action.colors[0].clear_value = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
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
    pub const Events = .{};
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
}

fn movement(time: zenithor.Resource(TimePlugin.Time), movement_query: zenithor.Group(CoordinateGroup)) !void {
    // Use scaled delta time for frame-rate independent movement
    const dt = time.value.delta_time * time.value.time_scale;
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

fn displayTimeInfo(time: zenithor.Resource(TimePlugin.Time)) !void {
    ImGuiPlugin.setNextWindowPos(ImGuiPlugin.ImVec2{ .x = 10, .y = 10 }, ImGuiPlugin.ImGuiCond.Once);
    ImGuiPlugin.setNextWindowSize(ImGuiPlugin.ImVec2{ .x = 300, .y = 150 }, ImGuiPlugin.ImGuiCond.Once);

    if (ImGuiPlugin.begin("Time Information", null, .None)) {
        ImGuiPlugin.textFmt("FPS: {d:.1}", .{1.0 / time.value.delta_time});
        ImGuiPlugin.textFmt("Delta Time: {d:.4} s ({d:.2} ms)", .{ time.value.delta_time, time.value.delta_time * 1000.0 });
        ImGuiPlugin.textFmt("Total Time: {d:.2} s", .{time.value.total_time});
        ImGuiPlugin.textFmt("Frame Count: {d}", .{time.value.frame_count});
        ImGuiPlugin.separator();
        ImGuiPlugin.textFmt("Time Scale: {d:.2}x", .{time.value.time_scale});
    }
    ImGuiPlugin.end();
}

fn timeControls(time: zenithor.ResourceMut(TimePlugin.Time)) !void {
    ImGuiPlugin.setNextWindowPos(ImGuiPlugin.ImVec2{ .x = 10, .y = 170 }, ImGuiPlugin.ImGuiCond.Once);
    ImGuiPlugin.setNextWindowSize(ImGuiPlugin.ImVec2{ .x = 300, .y = 150 }, ImGuiPlugin.ImGuiCond.Once);

    if (ImGuiPlugin.begin("Time Controls", null, .None)) {
        _ = ImGuiPlugin.sliderFloat("Time Scale", &time.value.time_scale, 0.0, 2.0);

        if (ImGuiPlugin.button("Pause")) {
            time.value.time_scale = 0.0;
        }
        ImGuiPlugin.sameLine();
        if (ImGuiPlugin.button("Normal")) {
            time.value.time_scale = 1.0;
        }
        ImGuiPlugin.sameLine();
        if (ImGuiPlugin.button("Fast")) {
            time.value.time_scale = 2.0;
        }

        if (ImGuiPlugin.button("Slow Motion (0.5x)")) {
            time.value.time_scale = 0.5;
        }
        ImGuiPlugin.sameLine();
        if (ImGuiPlugin.button("Very Slow (0.1x)")) {
            time.value.time_scale = 0.1;
        }
    }
    ImGuiPlugin.end();
}

