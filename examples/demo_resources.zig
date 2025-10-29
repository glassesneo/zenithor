const std = @import("std");
const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = zenithor.GraphicsPlugin;
const ImGuiPlugin = zenithor.ImGuiPlugin;
const ig = ImGuiPlugin.ig;

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, Game });
}

// ===== Resource Definitions =====

/// DeltaTime resource for frame-rate independent movement
const DeltaTime = struct {
    dt: f32,
    scale: f32,
};

/// Game score tracking
const Score = struct {
    points: i32,
    combo: i32,
    high_score: i32,
};

/// Game configuration
const GameConfig = struct {
    spawn_rate: f32, // shapes per second
    point_value: i32,
};

// ===== Component Definitions =====

const Velocity = struct {
    x: f32,
    y: f32,
};

const Lifetime = struct {
    remaining: f32, // seconds
};

const Clickable = struct {};

const MovementGroup = struct {
    BuiltinPlugin.Transform,
    Velocity,
};

// ===== Game Plugin =====

const Game = struct {
    pub const Components = .{ Velocity, Lifetime, Clickable };
    pub const Resources = .{ DeltaTime, Score, GameConfig };
    pub const Groups = .{MovementGroup};

    pub fn build(world: anytype, registry: SystemRegistry) !void {
        // Initialize resources with default values
        try world.setResource(DeltaTime, .{ .dt = 0.016, .scale = 1.0 });
        try world.setResource(Score, .{ .points = 0, .combo = 0, .high_score = 0 });
        try world.setResource(GameConfig, .{ .spawn_rate = 2.0, .point_value = 10 });

        // Register systems
        registry.registerStartupSystem(setup, .first);
        registry.registerSystem(updateDeltaTime, .first);
        registry.registerSystem(spawnShapes, .update);
        registry.registerSystem(movement, .update);
        registry.registerSystem(updateLifetime, .update);
        registry.registerSystem(handleClicks, .update);
        registry.registerSystem(displayUI, .render);
    }
};

// ===== Systems =====

fn setup(pass_action_resource: zenithor.Resource(GraphicsPlugin.PassAction)) !void {
    var pass_action = pass_action_resource.value;
    // Set white background
    pass_action.colors[0].clear_value = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
}

/// Update delta time resource
fn updateDeltaTime(delta: zenithor.Resource(DeltaTime)) !void {
    // In a real implementation, this would get actual frame delta
    // For this demo, we'll simulate it
    const raw_dt: f32 = 1.0 / 60.0; // Assume 60 FPS
    delta.value.dt = raw_dt;
}

var spawn_timer: f32 = 0;

/// Spawn shapes at regular intervals using GameConfig resource
fn spawnShapes(
    delta: zenithor.Resource(DeltaTime),
    config: zenithor.Resource(GameConfig),
    commands: anytype,
) !void {
    const dt = delta.value.dt * delta.value.scale;
    spawn_timer += dt;

    const spawn_interval = 1.0 / config.value.spawn_rate;

    while (spawn_timer >= spawn_interval) {
        spawn_timer -= spawn_interval;

        // Random position
        const x = @as(f32, @floatFromInt(std.crypto.random.intRangeAtMost(u32, 50, 590)));
        const y = @as(f32, @floatFromInt(std.crypto.random.intRangeAtMost(u32, 50, 430)));

        // Random velocity
        const vx = @as(f32, @floatFromInt(std.crypto.random.intRangeAtMost(i32, -100, 100)));
        const vy = @as(f32, @floatFromInt(std.crypto.random.intRangeAtMost(i32, -100, 100)));

        // Random shape type
        const shape_type = std.crypto.random.intRangeAtMost(u8, 0, 2);

        // Create entity and add components
        const entity = commands.createEntity();

        switch (shape_type) {
            0 => {
                // Rectangle (red)
                try commands.addComponent(entity, GraphicsPlugin.Rectangle, .{ .x = 30, .y = 30 });
                try commands.addComponent(entity, BuiltinPlugin.Color, .{ .r = 0.784, .g = 0.196, .b = 0.196 });
            },
            1 => {
                // Triangle (green)
                try commands.addComponent(entity, GraphicsPlugin.Triangle, .{ .x1 = 0, .y1 = -20, .x2 = 20, .y2 = 20, .x3 = -20, .y3 = 20 });
                try commands.addComponent(entity, BuiltinPlugin.Color, .{ .r = 0.196, .g = 0.784, .b = 0.196 });
            },
            else => {
                // Circle (blue)
                try commands.addComponent(entity, GraphicsPlugin.Circle, .{ .radius = 20 });
                try commands.addComponent(entity, BuiltinPlugin.Color, .{ .r = 0.196, .g = 0.196, .b = 0.784 });
            },
        }

        // Add common components
        try commands.addComponent(entity, BuiltinPlugin.Transform, .{ .x = x, .y = y, .z = 0 });
        try commands.addComponent(entity, Velocity, .{ .x = vx, .y = vy });
        try commands.addComponent(entity, Lifetime, .{ .remaining = 5.0 });
        try commands.addTag(entity, Clickable);
    }
}

/// Frame-rate independent movement using DeltaTime resource
fn movement(
    delta: zenithor.Resource(DeltaTime),
    movement_query: zenithor.Group(MovementGroup),
) !void {
    const dt = delta.value.dt * delta.value.scale;
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

/// Update entity lifetimes and remove expired entities
fn updateLifetime(
    delta: zenithor.Resource(DeltaTime),
    lifetime_query: zenithor.SingleQuery(Lifetime),
    commands: anytype,
) !void {
    const dt = delta.value.dt * delta.value.scale;

    for (lifetime_query.entities, lifetime_query.components) |entity, *lifetime| {
        lifetime.remaining -= dt;

        if (lifetime.remaining <= 0) {
            try commands.destroyEntity(entity);
        }
    }
}

/// Handle click events and update score
fn handleClicks(
    score: zenithor.Resource(Score),
    config: zenithor.Resource(GameConfig),
    clickable_query: zenithor.Query(struct { Clickable, BuiltinPlugin.Transform }),
    commands: anytype,
) !void {
    // Simple click detection (in real game, would use proper input handling)
    const io = ig.igGetIO();
    if (io.*.MouseClicked[0]) {
        const mouse_x = io.*.MousePos.x;
        const mouse_y = io.*.MousePos.y;

        for (clickable_query.entities) |entity| {
            if (clickable_query.filter(entity)) {
                const transform = clickable_query.getComponent(entity, BuiltinPlugin.Transform);

                // Simple distance-based collision (assume 30px radius)
                const dx = mouse_x - transform.x;
                const dy = mouse_y - transform.y;
                const dist_sq = dx * dx + dy * dy;

                if (dist_sq < 30 * 30) {
                    // Hit! Update score
                    score.value.points += config.value.point_value;
                    score.value.combo += 1;

                    // Update high score
                    if (score.value.points > score.value.high_score) {
                        score.value.high_score = score.value.points;
                    }

                    // Destroy the entity
                    try commands.destroyEntity(entity);
                    break; // Only handle one click per frame
                }
            }
        }
    } else if (!io.*.MouseDown[0]) {
        // Reset combo when not clicking
        score.value.combo = 0;
    }
}

/// Display game UI with resource information
fn displayUI(
    delta: zenithor.Resource(DeltaTime),
    score: zenithor.Resource(Score),
    config: zenithor.Resource(GameConfig),
) !void {
    // Score display
    ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 300, .y = 150 }, ig.ImGuiCond_Once);

    if (ig.igBegin("Score", null, ig.ImGuiWindowFlags_None)) {
        ig.igText("Points: %d", score.value.points);
        ig.igText("Combo: %dx", score.value.combo);
        ig.igText("High Score: %d", score.value.high_score);

        if (ig.igButton("Reset Score")) {
            score.value.points = 0;
            score.value.combo = 0;
        }
    }
    ig.igEnd();

    // Game controls
    ig.igSetNextWindowPos(.{ .x = 10, .y = 170 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 300, .y = 200 }, ig.ImGuiCond_Once);

    if (ig.igBegin("Game Controls", null, ig.ImGuiWindowFlags_None)) {
        ig.igText("Time Scale: %.2fx", delta.value.scale);
        _ = ig.igSliderFloat("##timescale", &delta.value.scale, 0.0, 2.0);

        if (ig.igButton("Pause")) {
            delta.value.scale = 0.0;
        }
        ig.igSameLine();
        if (ig.igButton("Normal")) {
            delta.value.scale = 1.0;
        }
        ig.igSameLine();
        if (ig.igButton("Fast")) {
            delta.value.scale = 2.0;
        }

        ig.igSeparator();

        ig.igText("Spawn Rate: %.1f shapes/s", config.value.spawn_rate);
        _ = ig.igSliderFloat("##spawnrate", &config.value.spawn_rate, 0.1, 10.0);

        ig.igText("Point Value: %d", config.value.point_value);
        _ = ig.igSliderInt("##pointvalue", &config.value.point_value, 1, 100);
    }
    ig.igEnd();

    // Instructions
    ig.igSetNextWindowPos(.{ .x = 10, .y = 380 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 300, .y = 100 }, ig.ImGuiCond_Once);

    if (ig.igBegin("Instructions", null, ig.ImGuiWindowFlags_None)) {
        ig.igTextWrapped("Click on the moving shapes to score points!\nCombo multiplier increases while clicking.\nShapes disappear after 5 seconds.");
    }
    ig.igEnd();
}
