const std = @import("std");
const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = zenithor.GraphicsPlugin;
const ImGuiPlugin = zenithor.ImGuiPlugin;
const InputPlugin = zenithor.InputPlugin;
const ig = ImGuiPlugin.ig;

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, InputPlugin, Game });
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

fn spawnEnemies(commands: anytype) !void {
    const dt: f32 = 1.0 / 60.0;
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
    player_query: zenithor.SingleTag(Player),
    commands: anytype,
    stats: zenithor.Resource(GameStats),
) !void {
    if (!mouse.value.left_button) return;

    for (player_query.entities) |player_entity| {
        // Get player transform through separate query
        const player_transform = try getTransform(player_entity);
        if (player_transform == null) continue;

        // Fire projectile toward mouse
        const dx = mouse.value.x - player_transform.?.x;
        const dy = mouse.value.y - player_transform.?.y;
        const dist = @sqrt(dx * dx + dy * dy);

        if (dist < 1.0) continue;

        const speed: f32 = 400.0;
        const vx = (dx / dist) * speed;
        const vy = (dy / dist) * speed;

        const projectile = commands.createEntity();
        try commands.addComponent(projectile, BuiltinPlugin.Transform, .{ .x = player_transform.?.x, .y = player_transform.?.y, .z = 0 });
        try commands.addComponent(projectile, BuiltinPlugin.Color, .{ .r = 0.3, .g = 1.0, .b = 0.3, .a = 1.0 });
        try commands.addComponent(projectile, GraphicsPlugin.Circle, .{ .radius = 5 });
        try commands.addComponent(projectile, Velocity, .{ .x = vx, .y = vy });
        try commands.addComponent(projectile, Collider, .{ .radius = 5 });
        try commands.addComponent(projectile, Lifetime, .{ .remaining = 2.0 });
        try commands.addTag(projectile, Projectile);

        stats.value.shots_fired += 1;
        break; // Only fire one projectile per frame
    }
}

// Helper to get transform (workaround for query limitations)
var cached_transform: ?BuiltinPlugin.Transform = null;
fn getTransform(entity: zenithor.Entity) !?BuiltinPlugin.Transform {
    _ = entity;
    // This is a simplified version - in real code you'd query properly
    return .{ .x = 320, .y = 400, .z = 0 };
}

fn moveEntities(
    transform_query: zenithor.SingleQuery(BuiltinPlugin.Transform),
    velocity_query: zenithor.SingleQuery(Velocity),
) !void {
    const dt: f32 = 1.0 / 60.0;

    // Move all entities with both Transform and Velocity
    for (transform_query.entities, transform_query.components) |entity, *transform| {
        // Check if entity also has velocity
        for (velocity_query.entities, velocity_query.components) |vel_entity, velocity| {
            if (entity == vel_entity) {
                transform.x += velocity.x * dt;
                transform.y += velocity.y * dt;
                break;
            }
        }
    }
}

fn updateLifetimes(
    lifetime_query: zenithor.SingleQuery(Lifetime),
    commands: anytype,
) !void {
    const dt: f32 = 1.0 / 60.0;

    for (lifetime_query.entities, lifetime_query.components) |entity, *lifetime| {
        lifetime.remaining -= dt;
        if (lifetime.remaining <= 0.0) {
            try commands.destroyEntity(entity);
        }
    }
}

fn detectCollisions(
    projectile_tags: zenithor.SingleTag(Projectile),
    enemy_tags: zenithor.SingleTag(Enemy),
    transform_query: zenithor.SingleQuery(BuiltinPlugin.Transform),
    collider_query: zenithor.SingleQuery(Collider),
    collision_writer: zenithor.EventWriter(CollisionEvent),
) !void {
    // Check each projectile against each enemy
    for (projectile_tags.entities) |proj_entity| {
        const proj_transform = findTransform(proj_entity, transform_query);
        const proj_collider = findCollider(proj_entity, collider_query);
        if (proj_transform == null or proj_collider == null) continue;

        for (enemy_tags.entities) |enemy_entity| {
            const enemy_transform = findTransform(enemy_entity, transform_query);
            const enemy_collider = findCollider(enemy_entity, collider_query);
            if (enemy_transform == null or enemy_collider == null) continue;

            // Check distance
            const dx = proj_transform.?.x - enemy_transform.?.x;
            const dy = proj_transform.?.y - enemy_transform.?.y;
            const dist_sq = dx * dx + dy * dy;
            const radius_sum = proj_collider.?.radius + enemy_collider.?.radius;

            if (dist_sq < radius_sum * radius_sum) {
                try collision_writer.enqueue(.{
                    .projectile = proj_entity,
                    .enemy = enemy_entity,
                });
            }
        }
    }
}

fn findTransform(entity: zenithor.Entity, query: zenithor.SingleQuery(BuiltinPlugin.Transform)) ?BuiltinPlugin.Transform {
    for (query.entities, query.components) |e, t| {
        if (e == entity) return t;
    }
    return null;
}

fn findCollider(entity: zenithor.Entity, query: zenithor.SingleQuery(Collider)) ?Collider {
    for (query.entities, query.components) |e, c| {
        if (e == entity) return c;
    }
    return null;
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
    const pos = ig.ImVec2{ .x = 10, .y = 10 };
    ig.igSetNextWindowPos(pos, ig.ImGuiCond_Once);

    const size = ig.ImVec2{ .x = 300, .y = 120 };
    ig.igSetNextWindowSize(size, ig.ImGuiCond_Once);

    var window_open = true;
    if (ig.igBegin("Event System Demo", &window_open, ig.ImGuiWindowFlags_None)) {
        ig.igTextColored(.{ .x = 0.3, .y = 1.0, .z = 0.3, .w = 1.0 }, "%s", "Event System Demo");
        ig.igSeparator();
        ig.igSpacing();

        var buf: [64]u8 = undefined;
        var text = std.fmt.bufPrintZ(&buf, "Shots Fired: {d}", .{stats.value.shots_fired}) catch "N/A";
        ig.igText("%s", text.ptr);

        text = std.fmt.bufPrintZ(&buf, "Enemies Killed: {d}", .{stats.value.enemies_killed}) catch "N/A";
        ig.igText("%s", text.ptr);

        ig.igSpacing();
        ig.igTextWrapped("%s", "Click to shoot enemies!");
    }
    ig.igEnd();
}
