const std = @import("std");
const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = @import("graphics_plugin");
const ImGuiPlugin = @import("imgui_plugin");
const InputPlugin = @import("input_plugin");
const TimePlugin = @import("time_plugin");

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, InputPlugin, TimePlugin, Game });
}

// ===== Event Definitions =====

const CollisionEvent = struct {
    projectile: zenithor.Entity,
    enemy: zenithor.Entity,
};

const DamageEvent = struct {
    entity: zenithor.Entity,
    amount: i32,
};

const DeathEvent = struct {
    entity: zenithor.Entity,
};

// ===== Component Definitions =====

const Health = struct {
    hp: i32,
    max_hp: i32,
};

const Velocity = struct {
    x: f32,
    y: f32,
};

const Collider = struct {
    radius: f32,
};

const Lifetime = struct {
    remaining: f32,
};

// Tag components
const Player = struct {};
const Enemy = struct {};
const Projectile = struct {};

// ===== Resource Definitions =====

const GameStats = struct {
    enemies_killed: i32 = 0,
    shots_fired: i32 = 0,
};

// ===== Game Plugin =====

const Game = struct {
    pub const Components = .{ Health, Velocity, Collider, Lifetime, Player, Enemy, Projectile };
    pub const Resources = .{GameStats};
    pub const Events = .{ CollisionEvent, DamageEvent, DeathEvent };

    pub fn build(world: anytype, registry: SystemRegistry) !void {
        try world.setResource(GameStats, .{});

        registry.registerStartupSystem(setup, .first);
        registry.registerSystem(spawnEnemies, .update);
        registry.registerSystem(handleInput, .update);
        registry.registerSystem(moveEntities, .update);
        registry.registerSystem(updateLifetimes, .update);
        registry.registerSystem(detectCollisions, .update);
        registry.registerSystem(handleDamage, .post_update);
        registry.registerSystem(handleDeath, .post_update);
        registry.registerSystem(displayUI, .render);
    }
};

// ===== Systems =====

fn setup(commands: anytype, pass_action: zenithor.Resource(GraphicsPlugin.PassAction)) !void {
    // Set background
    var action = pass_action.value;
    action.colors[0].clear_value = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1.0 };

    // Create player at bottom center
    const player = try commands.createEntityWith(.{
        BuiltinPlugin.Transform{ .x = 320, .y = 400, .z = 0 },
        BuiltinPlugin.Color{ .r = 0.3, .g = 0.5, .b = 1.0, .a = 1.0 },
        GraphicsPlugin.Circle{ .radius = 15 },
    });
    try commands.addTag(player, Player);
}

var spawn_timer: f32 = 0.0;
const spawn_interval: f32 = 1.0; // Spawn every 1 second

fn spawnEnemies(commands: anytype, time: zenithor.Resource(TimePlugin.Time)) !void {
    const dt = time.value.delta_time;
    spawn_timer += dt;

    if (spawn_timer >= spawn_interval) {
        spawn_timer -= spawn_interval;

        // Spawn enemy at random x position at top
        const x = @as(f32, @floatFromInt(std.crypto.random.intRangeAtMost(u32, 50, 590)));

        const enemy = commands.createEntity();
        try commands.addComponent(enemy, BuiltinPlugin.Transform, .{ .x = x, .y = 0, .z = 0 });
        try commands.addComponent(enemy, BuiltinPlugin.Color, .{ .r = 1.0, .g = 0.3, .b = 0.3, .a = 1.0 });
        try commands.addComponent(enemy, GraphicsPlugin.Circle, .{ .radius = 12 });
        try commands.addComponent(enemy, Velocity, .{ .x = 0, .y = 50 });
        try commands.addComponent(enemy, Collider, .{ .radius = 12 });
        try commands.addComponent(enemy, Health, .{ .hp = 100, .max_hp = 100 });
        try commands.addTag(enemy, Enemy);
    }
}

fn handleInput(
    mouse: zenithor.Resource(InputPlugin.Mouse),
    player_query: zenithor.Query(struct { Player, BuiltinPlugin.Transform }),
    commands: anytype,
    stats: zenithor.Resource(GameStats),
) !void {
    if (!mouse.value.left_button) return;

    if (player_query.entities.len == 0) return;
    const player_entity = player_query.entities[0];
    const player_transform = player_query.getComponent(player_entity, BuiltinPlugin.Transform);

    // Fire projectile toward mouse
    const dx = mouse.value.x - player_transform.x;
    const dy = mouse.value.y - player_transform.y;
    const dist = @sqrt(dx * dx + dy * dy);

    if (dist < 1.0) return;

    const speed: f32 = 400.0;
    const vx = (dx / dist) * speed;
    const vy = (dy / dist) * speed;

    const projectile = commands.createEntity();
    try commands.addComponent(projectile, BuiltinPlugin.Transform, .{ .x = player_transform.x, .y = player_transform.y, .z = 0 });
    try commands.addComponent(projectile, BuiltinPlugin.Color, .{ .r = 0.3, .g = 1.0, .b = 0.3, .a = 1.0 });
    try commands.addComponent(projectile, GraphicsPlugin.Circle, .{ .radius = 5 });
    try commands.addComponent(projectile, Velocity, .{ .x = vx, .y = vy });
    try commands.addComponent(projectile, Collider, .{ .radius = 5 });
    try commands.addComponent(projectile, Lifetime, .{ .remaining = 2.0 });
    try commands.addTag(projectile, Projectile);

    stats.value.shots_fired += 1;
}

fn moveEntities(query: zenithor.Query(struct { BuiltinPlugin.Transform, Velocity }), time: zenithor.Resource(TimePlugin.Time)) !void {
    const dt = time.value.delta_time;

    // Move all entities with both Transform and Velocity
    for (query.entities) |entity| {
        if (!query.filter(entity)) continue;
        const transform = query.getComponentMut(entity, BuiltinPlugin.Transform);
        const velocity = query.getComponent(entity, Velocity);
        transform.x += velocity.x * dt;
        transform.y += velocity.y * dt;
    }
}

fn updateLifetimes(
    lifetime_query: zenithor.SingleQuery(Lifetime),
    commands: anytype,
    time: zenithor.Resource(TimePlugin.Time),
) !void {
    const dt = time.value.delta_time;

    for (lifetime_query.entities, lifetime_query.components) |entity, *lifetime| {
        lifetime.remaining -= dt;
        if (lifetime.remaining <= 0.0) {
            try commands.destroyEntity(entity);
        }
    }
}

fn detectCollisions(
    projectiles: zenithor.Query(struct { Projectile, BuiltinPlugin.Transform, Collider }),
    enemies: zenithor.Query(struct { Enemy, BuiltinPlugin.Transform, Collider }),
    collision_writer: zenithor.EventWriter(CollisionEvent),
) !void {
    var iter = projectiles.crossProduct(&enemies);
    while (iter.next()) |entry| {
        const projectile, const enemy = entry;
        const proj_transform = projectiles.getComponent(projectile, BuiltinPlugin.Transform);
        const proj_collider = projectiles.getComponent(projectile, Collider);
        const enemy_transform = enemies.getComponent(enemy, BuiltinPlugin.Transform);
        const enemy_collider = enemies.getComponent(enemy, Collider);

        // Check distance between projectile and enemy
        const dx = proj_transform.x - enemy_transform.x;
        const dy = proj_transform.y - enemy_transform.y;
        const dist_sq = dx * dx + dy * dy;
        const radius_sum = proj_collider.radius + enemy_collider.radius;

        if (dist_sq < radius_sum * radius_sum) {
            try collision_writer.enqueue(.{
                .projectile = projectile,
                .enemy = enemy,
            });
        }
    }
}

fn handleDamage(
    collision_reader: zenithor.EventReader(CollisionEvent),
    damage_writer: zenithor.EventWriter(DamageEvent),
    commands: anytype,
) !void {
    for (collision_reader.queue) |collision| {
        // Destroy projectile
        try commands.destroyEntity(collision.projectile);

        // Deal damage to enemy
        try damage_writer.enqueue(.{
            .entity = collision.enemy,
            .amount = 50,
        });
    }
}

fn handleDeath(
    damage_reader: zenithor.EventReader(DamageEvent),
    health_query: zenithor.SingleQuery(Health),
    death_writer: zenithor.EventWriter(DeathEvent),
    commands: anytype,
    stats: zenithor.Resource(GameStats),
) !void {
    for (damage_reader.queue) |damage_event| {
        // Find entity's health
        for (health_query.entities, health_query.components) |entity, *health| {
            if (entity == damage_event.entity) {
                health.hp -= damage_event.amount;

                if (health.hp <= 0) {
                    try death_writer.enqueue(.{ .entity = entity });
                    try commands.destroyEntity(entity);
                    stats.value.enemies_killed += 1;
                }
                break;
            }
        }
    }
}

fn displayUI(stats: zenithor.Resource(GameStats)) !void {
    const pos = ImGuiPlugin.ImVec2{ .x = 10, .y = 10 };
    ImGuiPlugin.setNextWindowPos(pos, .Once);

    const size = ImGuiPlugin.ImVec2{ .x = 300, .y = 120 };
    ImGuiPlugin.setNextWindowSize(size, .Once);

    var window_open = true;
    if (ImGuiPlugin.begin("Event System Demo", &window_open, .None)) {
        ImGuiPlugin.textColored(ImGuiPlugin.ImVec4{ .x = 0.3, .y = 1.0, .z = 0.3, .w = 1.0 }, "Event System Demo");
        ImGuiPlugin.separator();
        ImGuiPlugin.spacing();

        ImGuiPlugin.textFmt("Shots Fired: {d}", .{stats.value.shots_fired});
        ImGuiPlugin.textFmt("Enemies Killed: {d}", .{stats.value.enemies_killed});

        ImGuiPlugin.spacing();
        ImGuiPlugin.textWrapped("Click to shoot enemies!");
    }
    ImGuiPlugin.end();
}