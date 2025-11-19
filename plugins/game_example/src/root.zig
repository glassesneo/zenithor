const std = @import("std");
const sparze = @import("sparze");
const zenithor = @import("zenithor");

const Query = sparze.Query;
const Resource = sparze.Resource;
const EventWriter = sparze.EventWriter;
const EventReader = sparze.EventReader;

const Transform = zenithor.Transform;
const Color = zenithor.Color;
const SystemRegistry = zenithor.SystemRegistry;

// Import dependencies
const TimePlugin = @import("time_plugin");
const InputPlugin = @import("input_plugin");
const GraphicsPlugin = @import("graphics_plugin");

// Use types from dependencies
const Time = TimePlugin.Time;
const Mouse = InputPlugin.Mouse;
const Keyboard = InputPlugin.Keyboard;
const Circle = GraphicsPlugin.Circle;
const Rectangle = GraphicsPlugin.Rectangle;

// Game-specific components
pub const Player = struct {
    speed: f32 = 200.0,
};

pub const Enemy = struct {
    speed: f32 = 50.0,
    direction: f32 = 1.0, // 1 or -1
};

pub const Score = struct {
    value: u32 = 0,
};

// Game-specific events
pub const EnemyDefeated = struct {
    points: u32,
};

pub const GameOver = struct {};

// Plugin declarations
pub const Components = .{ Player, Enemy, Score };
pub const Resources = .{};
pub const Events = .{ EnemyDefeated, GameOver };

// IMPORTANT: Declare dependencies on other plugins
// This demonstrates the auto-include feature - users only need to include
// GamePlugin in their zenithor.run() call, and Time, Input, and Graphics
// will be automatically included.
pub const Requires = .{ TimePlugin, InputPlugin, GraphicsPlugin };

pub fn build(allocator: std.mem.Allocator, world: anytype, registry: SystemRegistry) !void {
    _ = allocator;
    _ = world;

    // Register game systems
    registry.registerStartupSystem(setupGame, .first);
    registry.registerSystem(playerMovement, .update);
    registry.registerSystem(enemyMovement, .update);
    registry.registerSystem(checkCollisions, .post_update);
    registry.registerSystem(handleGameEvents, .post_update);
}

fn setupGame(commands: anytype) !void {
    // Create player
    const player = commands.createEntity();
    try commands.addComponent(player, Transform, .{ .x = 400, .y = 300, .z = 0 });
    try commands.addComponent(player, Color, Color.blue);
    try commands.addComponent(player, Circle, .{ .radius = 20 });
    try commands.addComponent(player, Player, .{});
    try commands.addComponent(player, Score, .{});

    // Create some enemies
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const enemy = commands.createEntity();
        const y = 100.0 + @as(f32, @floatFromInt(i)) * 150.0;
        try commands.addComponent(enemy, Transform, .{ .x = 100, .y = y, .z = 0 });
        try commands.addComponent(enemy, Color, Color.red);
        try commands.addComponent(enemy, Rectangle, .{ .x = 30, .y = 30 });
        try commands.addComponent(enemy, Enemy, .{});
    }
}

fn playerMovement(
    time: Resource(Time),
    keyboard: Resource(Keyboard),
    mouse: Resource(Mouse),
    players: Query(struct { Transform, Player }),
) !void {
    const dt = time.value.delta_time;
    const kb = keyboard.value;
    const m = mouse.value;

    for (players.entities) |entity| {
        const transform = players.getComponentMut(entity, Transform);
        const player = players.getComponent(entity, Player);

        // Keyboard movement (WASD)
        if (kb.isHeld(.W)) transform.y -= player.speed * dt;
        if (kb.isHeld(.S)) transform.y += player.speed * dt;
        if (kb.isHeld(.A)) transform.x -= player.speed * dt;
        if (kb.isHeld(.D)) transform.x += player.speed * dt;

        // Mouse movement (hold right click to move toward mouse)
        if (m.isHeld(.RIGHT)) {
            const dx = m.x - transform.x;
            const dy = m.y - transform.y;
            const dist = @sqrt(dx * dx + dy * dy);
            if (dist > 5.0) {
                transform.x += (dx / dist) * player.speed * dt;
                transform.y += (dy / dist) * player.speed * dt;
            }
        }

        // Keep player in bounds
        transform.x = std.math.clamp(transform.x, 20, 1260);
        transform.y = std.math.clamp(transform.y, 20, 780);
    }
}

fn enemyMovement(
    time: Resource(Time),
    enemies: Query(struct { Transform, Enemy }),
) !void {
    const dt = time.value.delta_time;

    for (enemies.entities) |entity| {
        const transform = enemies.getComponentMut(entity, Transform);
        const enemy = enemies.getComponentMut(entity, Enemy);

        // Move horizontally
        transform.x += enemy.speed * enemy.direction * dt;

        // Bounce at edges
        if (transform.x < 50 or transform.x > 1230) {
            enemy.direction *= -1;
        }
    }
}

fn checkCollisions(
    players: Query(struct { Transform, Circle, Score }),
    enemies: Query(struct { Transform, Rectangle }),
    commands: anytype,
    event_writer: EventWriter(EnemyDefeated),
) !void {
    for (players.entities) |player_entity| {
        const player_pos = players.getComponent(player_entity, Transform);
        const player_circle = players.getComponent(player_entity, Circle);
        const score = players.getComponentMut(player_entity, Score);

        for (enemies.entities) |enemy_entity| {
            const enemy_pos = enemies.getComponent(enemy_entity, Transform);
            const enemy_rect = enemies.getComponent(enemy_entity, Rectangle);

            // Simple circle-rectangle collision
            const dx = player_pos.x - std.math.clamp(player_pos.x, enemy_pos.x, enemy_pos.x + enemy_rect.x);
            const dy = player_pos.y - std.math.clamp(player_pos.y, enemy_pos.y, enemy_pos.y + enemy_rect.y);
            const dist_sq = dx * dx + dy * dy;

            if (dist_sq < player_circle.radius * player_circle.radius) {
                // Collision detected - destroy enemy and award points
                try commands.destroyEntity(enemy_entity);
                score.value += 10;
                try event_writer.enqueue(.{ .points = 10 });
            }
        }
    }
}

fn handleGameEvents(
    events: EventReader(EnemyDefeated),
) !void {
    for (events.queue) |event| {
        std.debug.print("Enemy defeated! +{} points\n", .{event.points});
    }
}
