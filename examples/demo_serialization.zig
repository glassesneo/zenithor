const std = @import("std");
const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = @import("graphics_plugin");
const ImGuiPlugin = @import("imgui_plugin");
const InputPlugin = @import("input_plugin");
const TimePlugin = @import("time_plugin");
const SerializationPlugin = @import("serialization_plugin");
const ig = ImGuiPlugin.ig;

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, InputPlugin, TimePlugin, SerializationPlugin, Game });
}

// ===== Component Definitions =====

const Velocity = struct {
    x: f32,
    y: f32,
};

const Health = struct {
    hp: i32,
    max_hp: i32,
};

const Lifetime = struct {
    remaining: f32,
};

const Collectible = struct {
    value: u32, // Score value
};

const Player = struct {}; // Tag component

// ===== Game State Management =====

const GameStatus = struct {
    state: enum { Playing, Paused, GameOver },
    level: u32 = 1,
    score: u32 = 0,
    lives: u32 = 3,
    timer: f32 = 60.0, // Level timer
};

const GameSettings = struct {
    spawn_rate: f32 = 1.0, // collectibles per second
    point_multiplier: f32 = 1.0,
    difficulty_scale: f32 = 1.0,
};

// ===== Game Plugin =====

const Game = struct {
    pub const Components = .{ Velocity, Health, Lifetime, Collectible, Player };
    pub const Resources = .{ GameStatus, GameSettings };
    pub const Events = .{};
    pub const Groups = .{};

    pub fn build(world: anytype, registry: SystemRegistry) !void {
        // Initialize game state
        try world.setResource(GameStatus, .{
            .state = .Playing,
            .level = 1,
            .score = 0,
            .lives = 3,
            .timer = 60.0,
        });

        try world.setResource(GameSettings, .{
            .spawn_rate = 1.0,
            .point_multiplier = 1.0,
            .difficulty_scale = 1.0,
        });

        // Register game systems
        registry.registerStartupSystem(setup, .first);
        registry.registerSystem(updateTimer, .first);
        registry.registerSystem(handleInput, .update);
        registry.registerSystem(spawnCollectibles, .update);
        registry.registerSystem(moveEntities, .update);
        registry.registerSystem(checkCollisions, .update);
        registry.registerSystem(updateLifetimes, .update);
        registry.registerSystem(nextLevel, .update);
        registry.registerSystem(drawUI, .render);
    }
};

// ===== Systems =====

fn setup(
    commands: anytype,
    pass_action_resource: zenithor.Resource(GraphicsPlugin.PassAction),
) !void {
    var pass_action = pass_action_resource.value;
    pass_action.colors[0].clear_value = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1.0 };

    // Create player entity
    const player = commands.createEntity();
    try commands.addTag(player, Player);
    try commands.addComponent(player, BuiltinPlugin.Transform, .{ .x = 640, .y = 400, .z = 0 });
    try commands.addComponent(player, GraphicsPlugin.Circle, .{ .radius = 20 });
    try commands.addComponent(player, BuiltinPlugin.Color, .{ .r = 1.0, .g = 1.0, .b = 1.0 });
    try commands.addComponent(player, Velocity, .{ .x = 0, .y = 0 });

    std.debug.print("Game started! Collect the colored circles to score points.\n", .{});
    std.debug.print("Controls: WASD to move, F5 to save, F9 to load\n", .{});
}

fn updateTimer(
    delta: zenithor.Resource(TimePlugin.Time),
    game_status: zenithor.Resource(GameStatus),
) !void {
    if (game_status.value.state == .Playing) {
        game_status.value.timer -= delta.value.delta_time;
        if (game_status.value.timer <= 0) {
            // Time up, next level or game over
            game_status.value.timer = 0;
            game_status.value.state = .GameOver;
        }
    }
}

fn handleInput(
    keyboard: zenithor.Resource(InputPlugin.Keyboard),
    commands: anytype,
    game_status: zenithor.Resource(GameStatus),
    save_file: zenithor.Resource(SerializationPlugin.SaveFile),
    player_query: zenithor.Query(struct { Player, BuiltinPlugin.Transform, Velocity }),
) !void {
    // Save/Load input (F5 and F9 keys) - edge detection prevents spam
    if (keyboard.value.isPressed(.F5)) {
        try SerializationPlugin.saveGame(commands, save_file);
    }
    if (keyboard.value.isPressed(.F9)) {
        try SerializationPlugin.loadGame(commands, save_file);
    }

    if (game_status.value.state != .Playing) return;

    // Find player entity (may have been recreated after load)
    for (player_query.entities) |entity| {
        if (!player_query.filter(entity)) continue;

        const velocity = player_query.getComponentMut(entity, Velocity);

        const speed: f32 = 300.0;
        velocity.x = 0;
        velocity.y = 0;

        // WASD movement - continuous input while held
        if (keyboard.value.isHeld(.W)) velocity.y = -speed;
        if (keyboard.value.isHeld(.A)) velocity.x = -speed;
        if (keyboard.value.isHeld(.S)) velocity.y = speed;
        if (keyboard.value.isHeld(.D)) velocity.x = speed;

        break; // Only process first player
    }
}

fn spawnCollectibles(
    delta: zenithor.Resource(TimePlugin.Time),
    game_status: zenithor.Resource(GameStatus),
    game_settings: zenithor.Resource(GameSettings),
    commands: anytype,
) !void {
    if (game_status.value.state != .Playing) return;

    const spawn_interval = 1.0 / game_settings.value.spawn_rate;
    const spawn_chance = game_settings.value.difficulty_scale * delta.value.delta_time / spawn_interval;

    if (std.crypto.random.float(f32) < spawn_chance) {
        // Spawn a new collectible
        const x = std.crypto.random.float(f32) * 1200 + 40; // Leave margin
        const y = std.crypto.random.float(f32) * 720 + 40;

        // Random color
        const colors = [_]BuiltinPlugin.Color{
            .{ .r = 1.0, .g = 0.0, .b = 0.0 }, // Red
            .{ .r = 0.0, .g = 1.0, .b = 0.0 }, // Green
            .{ .r = 0.0, .g = 0.0, .b = 1.0 }, // Blue
            .{ .r = 1.0, .g = 1.0, .b = 0.0 }, // Yellow
            .{ .r = 1.0, .g = 0.0, .b = 1.0 }, // Magenta
        };
        const color = colors[std.crypto.random.intRangeAtMost(usize, 0, colors.len - 1)];

        // Random value
        const value = std.crypto.random.intRangeAtMost(u32, 10, 100);

        const entity = commands.createEntity();
        try commands.addComponent(entity, GraphicsPlugin.Circle, .{ .radius = 15 });
        try commands.addComponent(entity, BuiltinPlugin.Transform, .{ .x = x, .y = y, .z = 0 });
        try commands.addComponent(entity, BuiltinPlugin.Color, color);
        try commands.addComponent(entity, Collectible, .{ .value = value });
        try commands.addComponent(entity, Lifetime, .{ .remaining = 10.0 });
    }
}

fn moveEntities(
    delta: zenithor.Resource(TimePlugin.Time),
    movable_query: zenithor.Query(struct { BuiltinPlugin.Transform, Velocity }),
) !void {
    for (movable_query.entities) |entity| {
        if (!movable_query.filter(entity)) continue;

        const transform = movable_query.getComponentMut(entity, BuiltinPlugin.Transform);
        const velocity = movable_query.getComponent(entity, Velocity);

        transform.x += velocity.x * delta.value.delta_time;
        transform.y += velocity.y * delta.value.delta_time;
    }
}

fn checkCollisions(
    game_status: zenithor.Resource(GameStatus),
    game_settings: zenithor.Resource(GameSettings),
    player_query: zenithor.Query(struct { Player, BuiltinPlugin.Transform }),
    collectible_query: zenithor.Query(struct { Collectible, BuiltinPlugin.Transform }),
    commands: anytype,
) !void {
    if (game_status.value.state != .Playing) return;
    if (player_query.entities.len == 0) return;

    const player_entity = player_query.entities[0];
    const player_pos = player_query.getComponent(player_entity, BuiltinPlugin.Transform);

    for (collectible_query.entities) |collectible_entity| {
        if (!collectible_query.filter(collectible_entity)) continue;

        const collectible_pos = collectible_query.getComponent(collectible_entity, BuiltinPlugin.Transform);
        const collectible_data = collectible_query.getComponent(collectible_entity, Collectible);

        // Simple distance check (20px radius + 15px collectible radius = 35px total)
        const dx = player_pos.x - collectible_pos.x;
        const dy = player_pos.y - collectible_pos.y;
        const dist_sq = dx * dx + dy * dy;

        if (dist_sq < 35 * 35) {
            // Collision detected!
            const points = @as(u32, @intFromFloat(@as(f32, @floatFromInt(collectible_data.value)) * game_settings.value.point_multiplier));
            game_status.value.score += points;

            std.debug.print("Collected collectible! +{} points (Total: {})\n", .{ points, game_status.value.score });

            try commands.destroyEntity(collectible_entity);
        }
    }
}

fn updateLifetimes(
    delta: zenithor.Resource(TimePlugin.Time),
    lifetime_query: zenithor.SingleQuery(Lifetime),
    commands: anytype,
) !void {
    for (lifetime_query.entities, lifetime_query.components) |entity, *lifetime| {
        lifetime.remaining -= delta.value.delta_time;
        if (lifetime.remaining <= 0) {
            try commands.destroyEntity(entity);
        }
    }
}

fn nextLevel(
    game_status: zenithor.Resource(GameStatus),
    game_settings: zenithor.Resource(GameSettings),
) !void {
    if (game_status.value.state == .GameOver) {
        // Check for restart
        if (game_status.value.lives > 0) {
            game_status.value.state = .Playing;
            game_status.value.level += 1;
            game_status.value.timer = 60.0;
            game_status.value.lives -= 1;

            // Increase difficulty
            game_settings.value.spawn_rate *= 1.2;
            game_settings.value.point_multiplier *= 1.1;
            game_settings.value.difficulty_scale *= 1.1;

            std.debug.print("Level {}! Lives remaining: {}\n", .{ game_status.value.level, game_status.value.lives });
        } else {
            std.debug.print("Game Over! Final Score: {}\n", .{game_status.value.score});
        }
    }
}

fn drawUI(
    commands: anytype,
    player_query: zenithor.Query(struct { Player, BuiltinPlugin.Transform, Velocity }),
    game_status: zenithor.Resource(GameStatus),
    game_settings: zenithor.Resource(GameSettings),
    save_file: zenithor.Resource(SerializationPlugin.SaveFile),
) !void {
    // Game status window
    ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 300, .y = 200 }, ig.ImGuiCond_Once);

    if (ig.igBegin("Game Status", null, ig.ImGuiWindowFlags_None)) {
        var buf: [128]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "State: {s}", .{@tagName(game_status.value.state)}) catch "Error";
        ig.igText("%s", text.ptr);
        ig.igText("Level: %u", game_status.value.level);
        ig.igText("Score: %u", game_status.value.score);
        ig.igText("Lives: %u", game_status.value.lives);
        ig.igText("Time: %.1fs", game_status.value.timer);
        ig.igText("Spawn Rate: %.1f/s", game_settings.value.spawn_rate);
    }
    ig.igEnd();

    // Save/Load controls
    ig.igSetNextWindowPos(.{ .x = 10, .y = 220 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 300, .y = 150 }, ig.ImGuiCond_Once);

    if (ig.igBegin("Save/Load", null, ig.ImGuiWindowFlags_None)) {
        var buf: [256]u8 = undefined;
        const path_text = std.fmt.bufPrintZ(&buf, "Save File: {s}", .{save_file.value.getPath()}) catch "Error";
        ig.igText("%s", path_text.ptr);

        if (ig.igButton("Save Game (F5)")) {
            try SerializationPlugin.saveGame(commands, save_file);
        }
        ig.igSameLine();
        if (ig.igButton("Load Game (F9)")) {
            try SerializationPlugin.loadGame(commands, save_file);
        }

        if (ig.igButton("New Game")) {
            // Reset game state
            game_status.value.state = .Playing;
            game_status.value.level = 1;
            game_status.value.score = 0;
            game_status.value.lives = 3;
            game_status.value.timer = 60.0;

            game_settings.value.spawn_rate = 1.0;
            game_settings.value.point_multiplier = 1.0;
            game_settings.value.difficulty_scale = 1.0;

            std.debug.print("New game started!\n", .{});
        }
    }
    ig.igEnd();

    // Instructions
    ig.igSetNextWindowPos(.{ .x = 10, .y = 380 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 300, .y = 150 }, ig.ImGuiCond_Once);

    if (ig.igBegin("Instructions", null, ig.ImGuiWindowFlags_None)) {
        ig.igTextWrapped("Move with WASD\nF5 - Save Game\nF9 - Load Game\n\nCollect colored circles to score points!\nDon't let the timer run out.");
        for (player_query.entities) |entity| {
            if (!player_query.filter(entity)) continue;

            const transform = player_query.getComponentMut(entity, BuiltinPlugin.Transform);
            var buf: [256]u8 = undefined;
            const path_text = std.fmt.bufPrintZ(&buf, "Player position:\n{f}", .{transform}) catch "Error";
            ig.igText("%s", path_text.ptr);
            break; // Only process first player
        }
    }
    ig.igEnd();
}
