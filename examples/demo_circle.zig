const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const Transform = BuiltinPlugin.Transform;
const Color = BuiltinPlugin.Color;
const GraphicsPlugin = zenithor.GraphicsPlugin;
const TimePlugin = zenithor.TimePlugin;
const ImGuiPlugin = zenithor.ImGuiPlugin;
const ig = ImGuiPlugin.ig;

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, TimePlugin, ImGuiPlugin, Game });
}

const Game = struct {
    pub const Components = .{};

    pub fn build(registry: SystemRegistry) !void {
        registry.registerStartupSystem(setup, .first);
        registry.registerSystem(animate, .update);
        registry.registerSystem(infoWindow, .render);
    }
};

var animation_time: f32 = 0.0;

fn setup(commands: anytype, pass_action: zenithor.Resource(GraphicsPlugin.PassAction)) !void {
    var action = pass_action.value;
    action.colors[0].clear_value = .{ .r = 0.95, .g = 0.95, .b = 1.0, .a = 1.0 };

    // SECTION 1: Quality comparison - circles with different segment counts (top left)
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 50, .segments = 8 },
        Transform{ .x = 100, .y = 100, .z = 0.0 },
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 50, .segments = 16 },
        Transform{ .x = 250, .y = 100, .z = 0.0 },
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 50 }, // Default 32 segments
        Transform{ .x = 400, .y = 100, .z = 0.0 },
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 50, .segments = 64 },
        Transform{ .x = 550, .y = 100, .z = 0.0 },
    });

    // SECTION 2: Mixed shapes overlapping at different z-depths (center)
    // This demonstrates z-index ordering with multiple shape types
    // Each shape has a distinct color to make layering obvious

    // Layer 1 (back): Red circle at z=0.8
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 100, .segments = 32 },
        Transform{ .x = 640, .y = 350, .z = 0.8 },
        Color.red,
    });

    // Layer 2: Orange rectangle at z=0.4
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Rectangle{ .x = 150, .y = 150 },
        Transform{ .x = 565, .y = 275, .z = 0.4 },
        Color.orange,
    });

    // Layer 3: Yellow triangle at z=0.0
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Triangle{ .x1 = 0, .y1 = -80, .x2 = 80, .y2 = 80, .x3 = -80, .y3 = 80 },
        Transform{ .x = 640, .y = 350, .z = 0.0 },
        Color.yellow,
    });

    // Layer 4: Green circle at z=-0.4
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 60, .segments = 32 },
        Transform{ .x = 640, .y = 350, .z = -0.4 },
        Color.green,
    });

    // Layer 5 (front): Blue rectangle at z=-0.8
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Rectangle{ .x = 80, .y = 80 },
        Transform{ .x = 600, .y = 310, .z = -0.8 },
        Color.blue,
    });

    // SECTION 3: Animated rotating circles (right side)
    // Create 5 circles that will rotate around a center point at different z-depths
    // Each has a different color to show depth when they overlap
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 35, .segments = 32 },
        Transform{ .x = 1100, .y = 350, .z = -0.8 },
        Color.blue,
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 35, .segments = 32 },
        Transform{ .x = 1030.9, .y = 445.1, .z = -0.4 },
        Color.green,
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 35, .segments = 32 },
        Transform{ .x = 938.2, .y = 409.5, .z = 0.0 },
        Color.yellow,
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 35, .segments = 32 },
        Transform{ .x = 938.2, .y = 290.5, .z = 0.4 },
        Color.orange,
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 35, .segments = 32 },
        Transform{ .x = 1030.9, .y = 254.9, .z = 0.8 },
        Color.red,
    });

    // SECTION 4: Overlapping circles with animation (bottom left)
    // Three circles that will move and demonstrate depth ordering
    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 70, .segments = 32 },
        Transform{ .x = 200, .y = 600, .z = 0.6 },
        Color.red,
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 70, .segments = 32 },
        Transform{ .x = 280, .y = 600, .z = 0.0 },
        Color.green,
    });

    _ = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 70, .segments = 32 },
        Transform{ .x = 360, .y = 600, .z = -0.6 },
        Color.blue,
    });
}

fn animate(time: zenithor.Resource(TimePlugin.Time), transforms: zenithor.SingleQuery(Transform)) !void {
    const dt = time.value.delta_time;
    animation_time += dt;

    // Animate rotating circles (entities around x=1000)
    for (transforms.components) |*transform| {
        // Rotating circles animation (right side)
        if (transform.x > 900 and transform.x < 1100 and transform.y > 250 and transform.y < 450) {
            // Calculate which circle this is based on original position
            const center_x: f32 = 1000;
            const center_y: f32 = 350;
            const dx = transform.x - center_x;
            const dy = transform.y - center_y;
            const current_angle = std.math.atan2(dy, dx);
            const rotation_speed: f32 = 1.0;
            const new_angle = current_angle + rotation_speed * dt;
            const radius_orbit: f32 = 100.0;

            transform.x = center_x + radius_orbit * @cos(new_angle);
            transform.y = center_y + radius_orbit * @sin(new_angle);
        }

        // Oscillating circles animation (bottom left)
        if (transform.y > 550 and transform.y < 650) {
            const offset = @sin(animation_time * 2.0) * 40.0;
            if (transform.x > 150 and transform.x < 250) {
                transform.x = 200 + offset;
            } else if (transform.x > 250 and transform.x < 350) {
                transform.x = 280 - offset * 0.5;
            } else if (transform.x > 350 and transform.x < 450) {
                transform.x = 360 + offset * 0.7;
            }
        }
    }
}

fn infoWindow() !void {
    const pos = ig.ImVec2{ .x = 10, .y = 10 };
    ig.igSetNextWindowPos(pos, ig.ImGuiCond_Once);

    const size = ig.ImVec2{ .x = 400, .y = 200 };
    ig.igSetNextWindowSize(size, ig.ImGuiCond_Once);

    var window_open = true;
    if (ig.igBegin("Circle & Z-Index Demo", &window_open, ig.ImGuiWindowFlags_None)) {
        ig.igTextColored(.{ .x = 0.2, .y = 0.8, .z = 1.0, .w = 1.0 }, "%s", "2D Circle Rendering & Z-Index Demo");
        ig.igSeparator();
        ig.igSpacing();

        ig.igText("%s", "Demonstrations:");
        ig.igBulletText("%s", "Top row: Circle quality (8, 16, 32, 64 segments)");
        ig.igBulletText("%s", "Center: Mixed shapes at different z-depths");
        ig.igTextWrapped("%s", "  (Circle, Rectangle, Triangle, Circle, Rectangle)");
        ig.igTextWrapped("%s", "  Note how shapes layer based on z-value!");
        ig.igBulletText("%s", "Right: Rotating circles at various depths");
        ig.igBulletText("%s", "Bottom-left: Oscillating overlapping circles");
        ig.igSpacing();

        ig.igText("Animation time:");
        ig.igSameLine();
        var time_buf: [32]u8 = undefined;
        const time_text = std.fmt.bufPrintZ(&time_buf, "{d:.2}s", .{animation_time}) catch "N/A";
        ig.igText("%s", time_text.ptr);

        ig.igSpacing();
        ig.igTextColored(.{ .x = 0.8, .y = 0.8, .z = 0.2, .w = 1.0 }, "%s", "Z-Index Legend:");
        ig.igTextWrapped("%s", "Lower z (more negative) = In front (closer)");
        ig.igTextWrapped("%s", "Higher z (more positive) = Behind (farther)");
    }
    ig.igEnd();
}

const std = @import("std");
