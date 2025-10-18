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

/// Velocity component with custom formatting for debug display
const Velocity = struct {
    x: f32,
    y: f32,

    pub fn format(self: Velocity, writer: anytype) !void {
        try writer.print("Velocity({d:.1} px/s, {d:.1} px/s)", .{ self.x, self.y });
    }
};

/// Health component to demonstrate multiple component types
const Health = struct {
    current: f32,
    max: f32,

    pub fn format(self: Health, writer: anytype) !void {
        const percentage = (self.current / self.max) * 100.0;
        try writer.print("Health({d:.0}/{d:.0} = {d:.1}%)", .{ self.current, self.max, percentage });
    }
};

/// Lifetime component - entities with this will be destroyed after duration
const Lifetime = struct {
    remaining: f32, // seconds

    pub fn format(self: Lifetime, writer: anytype) !void {
        try writer.print("Lifetime({d:.2}s remaining)", .{self.remaining});
    }
};

const CoordinateGroup = struct {
    BuiltinPlugin.Transform,
    Velocity,
};

const Game = struct {
    pub const Components = .{ Velocity, Health, Lifetime };
    pub const Groups = .{CoordinateGroup};

    pub fn build(registry: SystemRegistry) !void {
        registry.registerStartupSystem(setup, .first);
        registry.registerSystem(movement, .update);
        registry.registerSystem(healthSystem, .update);
        registry.registerSystem(lifetimeSystem, .update);
        registry.registerSystem(spawner, .update);
        registry.registerSystem(debugInfo, .render);
        registry.registerSystem(controlPanel, .render);
    }
};

// Shared state for spawner
var spawn_timer: f32 = 0.0;
var spawn_interval: f32 = 3.0; // Spawn every 3 seconds
var spawn_enabled: bool = true;
var next_spawn_type: usize = 0;

fn setup(commands: anytype) !void {
    // Create initial tracked entities with different configurations

    // Rectangle with health - bounces and can "die"
    const rect_entity = try commands.createEntityWith(.{
        GraphicsPlugin.Rectangle{ .x = 50, .y = 50 },
        BuiltinPlugin.Transform{ .x = 900, .y = 300, .z = 0 },
        Velocity{ .x = 100, .y = 50 },
        Health{ .current = 100, .max = 100 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(rect_entity);

    // Triangle - fast moving, tracked
    const tri_entity = try commands.createEntityWith(.{
        GraphicsPlugin.Triangle{ .x1 = 0, .y1 = -30, .x2 = 30, .y2 = 30, .x3 = -30, .y3 = 30 },
        BuiltinPlugin.Transform{ .x = 850, .y = 200, .z = 0 },
        Velocity{ .x = -150, .y = 180 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(tri_entity);

    // Point - not tracked, just for comparison
    const point_entity = try commands.createEntityWith(.{
        GraphicsPlugin.Point{},
        BuiltinPlugin.Transform{ .x = 1000, .y = 500, .z = 0 },
    });
    try DebugPlugin.logEntityCreated(point_entity);

    // Set background
    GraphicsPlugin.pass_action.colors[0].clear_value = .{ .r = 0.95, .g = 0.95, .b = 0.95, .a = 1 };
}

fn movement(movement_query: zenithor.Group(CoordinateGroup)) !void {
    const dt = TimePlugin.delta_time * TimePlugin.time_scale;
    const transforms = movement_query.getMutArrayOf(BuiltinPlugin.Transform);
    const velocities = movement_query.getMutArrayOf(Velocity);

    for (transforms, velocities) |*transform, *velocity| {
        // Update position
        transform.x += velocity.x * dt;
        transform.y += velocity.y * dt;

        // Bounce off window edges
        const width: f32 = 1280.0;
        const height: f32 = 800.0;

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

/// Health system - slowly drain health, destroy at 0
fn healthSystem(commands: anytype, health_query: zenithor.SingleQuery(Health)) !void {
    const dt = TimePlugin.delta_time * TimePlugin.time_scale;

    for (health_query.entities, health_query.components) |entity, *health| {
        // health is already a mutable pointer in the for loop

        // Drain health over time (10 hp/second)
        health.current -= 10.0 * dt;

        // Destroy when health reaches 0
        if (health.current <= 0) {
            try DebugPlugin.logEntityDestroyed(entity);
            try commands.destroyEntity(entity);
        }
    }
}

/// Lifetime system - destroy entities when their lifetime expires
fn lifetimeSystem(commands: anytype, lifetime_query: zenithor.SingleQuery(Lifetime)) !void {
    const dt = TimePlugin.delta_time * TimePlugin.time_scale;

    for (lifetime_query.entities, lifetime_query.components) |entity, *lifetime| {
        // lifetime is already a mutable pointer in the for loop

        lifetime.remaining -= dt;

        if (lifetime.remaining <= 0) {
            try DebugPlugin.logEntityDestroyed(entity);
            try commands.destroyEntity(entity);
        }
    }
}

/// Spawner system - periodically create new entities
fn spawner(commands: anytype) !void {
    if (!spawn_enabled) return;

    const dt = TimePlugin.delta_time * TimePlugin.time_scale;
    spawn_timer += dt;

    if (spawn_timer >= spawn_interval) {
        spawn_timer = 0.0;

        // Spawn different entity types in rotation
        const spawn_x = 900.0;
        const spawn_y = 400.0;

        const entity = switch (next_spawn_type % 3) {
            0 => blk: {
                // Spawn line with lifetime
                const e = try commands.createEntityWith(.{
                    GraphicsPlugin.Line{ .x = 100, .y = 0 },
                    BuiltinPlugin.Transform{ .x = spawn_x, .y = spawn_y, .z = 0 },
                    Velocity{ .x = 50, .y = 80 },
                    Lifetime{ .remaining = 5.0 },
                    DebugPlugin.Tracked{},
                });
                break :blk e;
            },
            1 => blk: {
                // Spawn rectangle with health
                const e = try commands.createEntityWith(.{
                    GraphicsPlugin.Rectangle{ .x = 40, .y = 40 },
                    BuiltinPlugin.Transform{ .x = spawn_x + 50, .y = spawn_y, .z = 0 },
                    Velocity{ .x = -70, .y = 60 },
                    Health{ .current = 50, .max = 50 },
                    DebugPlugin.Tracked{},
                });
                break :blk e;
            },
            else => blk: {
                // Spawn triangle with both
                const e = try commands.createEntityWith(.{
                    GraphicsPlugin.Triangle{ .x1 = 0, .y1 = -20, .x2 = 20, .y2 = 20, .x3 = -20, .y3 = 20 },
                    BuiltinPlugin.Transform{ .x = spawn_x - 50, .y = spawn_y, .z = 0 },
                    Velocity{ .x = 90, .y = 110 },
                    Lifetime{ .remaining = 4.0 },
                    Health{ .current = 30, .max = 30 },
                    DebugPlugin.Tracked{},
                });
                break :blk e;
            },
        };

        try DebugPlugin.logEntityCreated(entity);
        next_spawn_type += 1;
    }
}

/// Debug info window - shows all tracked entities
fn debugInfo(commands: anytype, tracked: zenithor.SingleTag(DebugPlugin.Tracked)) !void {
    try DebugPlugin.openDebugWindow(.{
        BuiltinPlugin.Transform,
        Velocity,
        Health,
        Lifetime,
        GraphicsPlugin.Rectangle,
        GraphicsPlugin.Triangle,
        GraphicsPlugin.Line,
        GraphicsPlugin.Point,
    }, commands, tracked.entities);
}

/// Control panel for demo features
fn controlPanel() !void {
    const pos = ig.ImVec2{ .x = 10, .y = 720 };
    ig.igSetNextWindowPos(pos, ig.ImGuiCond_Once);

    const size = ig.ImVec2{ .x = 420, .y = 70 };
    ig.igSetNextWindowSize(size, ig.ImGuiCond_Once);

    var window_open = true;
    if (ig.igBegin("Demo Controls", &window_open, ig.ImGuiWindowFlags_None)) {
        ig.igTextColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "%s", "Debug Demo Features");
        ig.igSeparator();
        ig.igSpacing();

        // Spawner controls
        _ = ig.igCheckbox("Auto-spawn entities", &spawn_enabled);

        ig.igText("Spawn interval:");
        ig.igSameLine();
        ig.igPushItemWidth(100);
        _ = ig.igSliderFloat("##interval", &spawn_interval, 0.5, 10.0);
        ig.igPopItemWidth();

        if (ig.igButton("Spawn Now!")) {
            spawn_timer = spawn_interval; // Trigger immediate spawn
        }

        ig.igSpacing();
        ig.igSeparator();
        ig.igSpacing();

        // Time controls
        ig.igText("Time scale:");
        ig.igSameLine();
        ig.igPushItemWidth(100);
        _ = ig.igSliderFloat("##timescale", &TimePlugin.time_scale, 0.0, 3.0);
        ig.igPopItemWidth();

        ig.igSpacing();

        // Feature hints
        ig.igTextColored(.{ .x = 0.6, .y = 0.6, .z = 0.6, .w = 1.0 }, "%s", "Watch for:");
        ig.igBulletText("%s", "Highlight changes on bounce");
        ig.igBulletText("%s", "Health/lifetime drain");
        ig.igBulletText("%s", "Entity lifecycle log");
        ig.igBulletText("%s", "Performance metrics");
    }
    ig.igEnd();
}
