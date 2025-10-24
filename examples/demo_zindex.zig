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
    GraphicsPlugin.pass_action.colors[0].clear_value = .{ .r = 0.9, .g = 0.9, .b = 0.95, .a = 1 };

    // Create overlapping rectangles at different z-depths
    // Rectangle at z=0.5 (back layer - red)
    const rect_back = try commands.createEntityWith(.{
        GraphicsPlugin.Rectangle{ .x = 200, .y = 200 },
        BuiltinPlugin.Transform{ .x = 400, .y = 250, .z = 0.5 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(rect_back);

    // Rectangle at z=0.0 (middle layer - will be yellow)
    const rect_middle = try commands.createEntityWith(.{
        GraphicsPlugin.Rectangle{ .x = 200, .y = 200 },
        BuiltinPlugin.Transform{ .x = 500, .y = 300, .z = 0.0 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(rect_middle);

    // Rectangle at z=-0.5 (front layer - will be yellow)
    const rect_front = try commands.createEntityWith(.{
        GraphicsPlugin.Rectangle{ .x = 200, .y = 200 },
        BuiltinPlugin.Transform{ .x = 600, .y = 350, .z = -0.5 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(rect_front);

    // Create triangles at different z-depths
    // Triangle at z=0.8 (far back - green)
    const tri_back = try commands.createEntityWith(.{
        GraphicsPlugin.Triangle{ .x1 = 0, .y1 = -80, .x2 = 80, .y2 = 80, .x3 = -80, .y3 = 80 },
        BuiltinPlugin.Transform{ .x = 200, .y = 200, .z = 0.8 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(tri_back);

    // Triangle at z=-0.8 (very front - green)
    const tri_front = try commands.createEntityWith(.{
        GraphicsPlugin.Triangle{ .x1 = 0, .y1 = -80, .x2 = 80, .y2 = 80, .x3 = -80, .y3 = 80 },
        BuiltinPlugin.Transform{ .x = 1000, .y = 200, .z = -0.8 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(tri_front);

    // Create lines at different z-depths
    const line_back = try commands.createEntityWith(.{
        GraphicsPlugin.Line{ .x = 300, .y = 0 },
        BuiltinPlugin.Transform{ .x = 300, .y = 600, .z = 0.3 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(line_back);

    const line_front = try commands.createEntityWith(.{
        GraphicsPlugin.Line{ .x = 300, .y = 0 },
        BuiltinPlugin.Transform{ .x = 700, .y = 600, .z = -0.3 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(line_front);

    // Create points at different z-depths
    const point_back = try commands.createEntityWith(.{
        GraphicsPlugin.Point{},
        BuiltinPlugin.Transform{ .x = 640, .y = 100, .z = 0.9 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(point_back);

    const point_front = try commands.createEntityWith(.{
        GraphicsPlugin.Point{},
        BuiltinPlugin.Transform{ .x = 640, .y = 150, .z = -0.9 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(point_front);
}

fn animate(tracked_query: zenithor.SingleTag(DebugPlugin.Tracked), commands: anytype) !void {
    const dt = TimePlugin.delta_time;
    animation_time += dt;

    // Animate z-depth of middle entities (sine wave)
    const z_offset = @sin(animation_time) * 0.8;

    const transform_sparse_set = commands.getSparseSetPtrMut(BuiltinPlugin.Transform);
    for (tracked_query.entities) |entity| {
        if (transform_sparse_set.getPtrMut(entity)) |transform| {
            // Only animate entities in the middle range
            if (transform.z >= -0.1 and transform.z <= 0.1) {
                transform.z = z_offset;
            }
        }
    }
}

fn debugInfo(commands: anytype, tracked: zenithor.SingleTag(DebugPlugin.Tracked)) !void {
    try DebugPlugin.openDebugWindow(.{
        BuiltinPlugin.Transform,
        GraphicsPlugin.Rectangle,
        GraphicsPlugin.Triangle,
        GraphicsPlugin.Line,
        GraphicsPlugin.Point,
    }, commands, tracked.entities);
}

fn infoWindow() !void {
    const pos = ig.ImVec2{ .x = 10, .y = 720 };
    ig.igSetNextWindowPos(pos, ig.ImGuiCond_Once);

    const size = ig.ImVec2{ .x = 420, .y = 70 };
    ig.igSetNextWindowSize(size, ig.ImGuiCond_Once);

    var window_open = true;
    if (ig.igBegin("Z-Index Demo", &window_open, ig.ImGuiWindowFlags_None)) {
        ig.igTextColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "%s", "Z-Index Depth Ordering Demo");
        ig.igSeparator();
        ig.igSpacing();

        ig.igText("%s", "This demo shows 2D shapes at different z-depths:");
        ig.igBulletText("%s", "Lower z values render in front (closer)");
        ig.igBulletText("%s", "Higher z values render behind (farther)");
        ig.igBulletText("%s", "Middle entities animate between depths");
        ig.igSpacing();

        ig.igText("Animation time:");
        ig.igSameLine();
        var time_buf: [32]u8 = undefined;
        const time_text = std.fmt.bufPrintZ(&time_buf, "{d:.2}s", .{animation_time}) catch "N/A";
        ig.igText("%s", time_text.ptr);

        ig.igSpacing();
        ig.igTextColored(.{ .x = 0.6, .y = 0.6, .z = 0.6, .w = 1.0 }, "%s", "Check Entity Tracker to see z values change!");
    }
    ig.igEnd();
}

const std = @import("std");
