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

const Game = struct {
    pub const Components = .{};

    pub fn build(registry: SystemRegistry) !void {
        registry.registerStartupSystem(setup, .first);
        registry.registerSystem(animate, .update);
        registry.registerSystem(debugInfo, .render);
        registry.registerSystem(infoWindow, .render);
    }
};

var animation_time: f32 = 0.0;

fn setup(commands: anytype) !void {
    // Set light background
    GraphicsPlugin.pass_action.colors[0].clear_value = .{ .r = 0.95, .g = 0.95, .b = 1.0, .a = 1 };

    // Create circles with different segment counts to show quality levels
    // Low quality (8 segments - octagon)
    const circle_low = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 60, .segments = 8 },
        BuiltinPlugin.Transform{ .x = 150, .y = 200, .z = 0.0 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(circle_low);

    // Medium quality (16 segments)
    const circle_medium = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 60, .segments = 16 },
        BuiltinPlugin.Transform{ .x = 350, .y = 200, .z = 0.0 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(circle_medium);

    // Default quality (32 segments)
    const circle_default = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 60 }, // Uses default 32 segments
        BuiltinPlugin.Transform{ .x = 550, .y = 200, .z = 0.0 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(circle_default);

    // High quality (64 segments)
    const circle_high = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 60, .segments = 64 },
        BuiltinPlugin.Transform{ .x = 750, .y = 200, .z = 0.0 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(circle_high);

    // Create circles at different z-depths (overlapping)
    // Back circle (red tint via separate component if we add colors)
    const circle_back = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 80, .segments = 32 },
        BuiltinPlugin.Transform{ .x = 450, .y = 450, .z = 0.5 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(circle_back);

    // Middle circle
    const circle_middle = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 80, .segments = 32 },
        BuiltinPlugin.Transform{ .x = 520, .y = 450, .z = 0.0 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(circle_middle);

    // Front circle
    const circle_front = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 80, .segments = 32 },
        BuiltinPlugin.Transform{ .x = 590, .y = 450, .z = -0.5 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(circle_front);

    // Create animated circles that change size
    const circle_anim1 = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 40, .segments = 32 },
        BuiltinPlugin.Transform{ .x = 950, .y = 300, .z = 0.0 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(circle_anim1);

    const circle_anim2 = try commands.createEntityWith(.{
        GraphicsPlugin.Circle{ .radius = 40, .segments = 32 },
        BuiltinPlugin.Transform{ .x = 1080, .y = 300, .z = 0.0 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(circle_anim2);
}

fn animate(tracked_query: zenithor.SingleTag(DebugPlugin.Tracked), commands: anytype) !void {
    const dt = TimePlugin.delta_time;
    animation_time += dt;

    const circle_sparse_set = commands.getSparseSetPtrMut(GraphicsPlugin.Circle);
    const transform_sparse_set = commands.getSparseSetPtrMut(BuiltinPlugin.Transform);

    for (tracked_query.entities) |entity| {
        if (transform_sparse_set.getPtrMut(entity)) |transform| {
            // Animate circles in the right section (x > 900)
            if (transform.x > 900) {
                if (circle_sparse_set.getPtrMut(entity)) |circle| {
                    // Pulse radius with sine wave
                    const base_radius: f32 = 40.0;
                    const pulse_amount: f32 = 15.0;
                    circle.radius = base_radius + pulse_amount * @sin(animation_time * 2.0);
                }
            }

            // Animate middle overlapping circles (y around 450)
            if (transform.y > 400 and transform.y < 500) {
                // Move the circles in a circular motion
                const offset_x = @cos(animation_time) * 30.0;
                const offset_y = @sin(animation_time) * 30.0;

                if (transform.z > -0.1 and transform.z < 0.1) {
                    transform.x = 520 + offset_x;
                    transform.y = 450 + offset_y;
                }
            }
        }
    }
}

fn debugInfo(commands: anytype, tracked: zenithor.SingleTag(DebugPlugin.Tracked)) !void {
    try DebugPlugin.openDebugWindow(.{
        BuiltinPlugin.Transform,
        GraphicsPlugin.Circle,
    }, commands, tracked.entities);
}

fn infoWindow() !void {
    const pos = ig.ImVec2{ .x = 10, .y = 720 };
    ig.igSetNextWindowPos(pos, ig.ImGuiCond_Once);

    const size = ig.ImVec2{ .x = 420, .y = 70 };
    ig.igSetNextWindowSize(size, ig.ImGuiCond_Once);

    var window_open = true;
    if (ig.igBegin("Circle Demo", &window_open, ig.ImGuiWindowFlags_None)) {
        ig.igTextColored(.{ .x = 0.2, .y = 0.8, .z = 1.0, .w = 1.0 }, "%s", "2D Circle Rendering Demo");
        ig.igSeparator();
        ig.igSpacing();

        ig.igText("%s", "This demo shows circle rendering features:");
        ig.igBulletText("%s", "Top row: Different segment counts (8, 16, 32, 64)");
        ig.igBulletText("%s", "Middle: Overlapping circles at different z-depths");
        ig.igBulletText("%s", "Right: Animated circles with pulsing radius");
        ig.igSpacing();

        ig.igText("Animation time:");
        ig.igSameLine();
        var time_buf: [32]u8 = undefined;
        const time_text = std.fmt.bufPrintZ(&time_buf, "{d:.2}s", .{animation_time}) catch "N/A";
        ig.igText("%s", time_text.ptr);

        ig.igSpacing();
        ig.igTextColored(.{ .x = 0.6, .y = 0.6, .z = 0.6, .w = 1.0 }, "%s", "Check Entity Tracker to see circle properties!");
    }
    ig.igEnd();
}

const std = @import("std");
