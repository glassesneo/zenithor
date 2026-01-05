/// Example: Serialization Round-Trip
///
/// Demonstrates save/load functionality:
/// - Save game state with F5 or button
/// - Load game state with F9 or button
/// - Resources are serialized automatically (POD types)
/// - Mark transient resources with `pub const serialized = false`
///
/// WASM Note: Requires `-Dfilesystem` build flag for IDBFS support.
///
/// Controls:
///   F5 - Save game
///   F9 - Load game
///   WASD - Move circle
///
/// See: plugins/serialization/CLAUDE.md
const std = @import("std");
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Color = zenithor.Color;
const Resource = zenithor.Resource;
const ResourceMut = zenithor.ResourceMut;
const SingleQuery = zenithor.SingleQuery;
const GraphicsPlugin = @import("graphics_plugin").Default;
const RenderContext = @import("render_context_plugin");
const TimePlugin = @import("time_plugin");
const InputPlugin = @import("input_plugin");
const ImGuiPlugin = @import("imgui_plugin");
const SerializationPlugin = @import("serialization_plugin");

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, TimePlugin, InputPlugin, ImGuiPlugin, SerializationPlugin, Game }, .{});
}

// Tag component for player
const Player = struct {};

// Game state resource - will be serialized
const GameState = struct {
    score: u32 = 0,
    level: u32 = 1,
    coins_collected: u32 = 0,
};

const Game = struct {
    pub const Components = .{Player};
    pub const Resources = .{GameState};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = handleInput, .stage = .update },
            .{ .system = drawUI, .stage = .render },
        },
    };
};

fn setup(commands: anytype, pass_action: ResourceMut(RenderContext.PassAction)) !void {
    pass_action.colors[0].clear_value = .{ .r = 0.1, .g = 0.15, .b = 0.2, .a = 1.0 };

    commands.setResource(GameState, .{
        .score = 0,
        .level = 1,
        .coins_collected = 0,
    });

    // Create player
    const player = commands.createEntity();
    try commands.addTag(player, Player);
    try commands.addComponent(player, GraphicsPlugin.Circle, .{ .radius = 30, .segments = 32 });
    try commands.addComponent(player, Transform, .{ .x = 640, .y = 400, .z = 0 });
    try commands.addComponent(player, Color, Color.cyan);

    std.debug.print("Game initialized. F5 to save, F9 to load.\n", .{});
}

fn handleInput(
    keyboard: Resource(InputPlugin.Keyboard),
    time: Resource(TimePlugin.Time),
    game: ResourceMut(GameState),
    save_file: ResourceMut(SerializationPlugin.SaveFile),
    player: SingleQuery(Transform),
    commands: anytype,
) !void {
    const dt = time.delta_time;

    // Save/Load with isPressed (fires once per key press)
    if (keyboard.isPressed(.F5)) {
        try SerializationPlugin.saveGame(commands, save_file);
        std.debug.print("Game saved! Score: {}, Level: {}\n", .{ game.score, game.level });
    }

    if (keyboard.isPressed(.F9)) {
        try SerializationPlugin.loadGame(commands, save_file);
        std.debug.print("Game loaded!\n", .{});
    }

    // Simulate gameplay
    if (keyboard.isPressed(.C)) {
        game.coins_collected += 1;
        game.score += 10;
    }

    if (keyboard.isPressed(.L)) {
        game.level += 1;
        game.score += 100;
    }

    // Movement
    const speed: f32 = 250.0;
    for (player.components) |*transform| {
        if (keyboard.isHeld(.W) or keyboard.isHeld(.UP)) transform.y -= speed * dt;
        if (keyboard.isHeld(.S) or keyboard.isHeld(.DOWN)) transform.y += speed * dt;
        if (keyboard.isHeld(.A) or keyboard.isHeld(.LEFT)) transform.x -= speed * dt;
        if (keyboard.isHeld(.D) or keyboard.isHeld(.RIGHT)) transform.x += speed * dt;

        transform.x = std.math.clamp(transform.x, 30, 1250);
        transform.y = std.math.clamp(transform.y, 30, 770);
    }
}

fn drawUI(
    game: ResourceMut(GameState),
    save_file: ResourceMut(SerializationPlugin.SaveFile),
    commands: anytype,
) !void {
    ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = 10 }, .Once);
    ImGuiPlugin.setNextWindowSize(.{ .x = 320, .y = 280 }, .Once);

    if (ImGuiPlugin.begin("Serialization Demo", null, .None)) {
        ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Game State (Serialized)");
        ImGuiPlugin.separator();
        ImGuiPlugin.textFmt("Score: {}", .{game.score});
        ImGuiPlugin.textFmt("Level: {}", .{game.level});
        ImGuiPlugin.textFmt("Coins: {}", .{game.coins_collected});

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Controls");
        ImGuiPlugin.separator();
        ImGuiPlugin.bulletText("WASD - Move circle");
        ImGuiPlugin.bulletText("C - Collect coin (+10 score)");
        ImGuiPlugin.bulletText("L - Next level (+100 score)");

        ImGuiPlugin.spacing();
        if (ImGuiPlugin.button("Save (F5)")) {
            try SerializationPlugin.saveGame(commands, save_file);
        }
        ImGuiPlugin.sameLine();
        if (ImGuiPlugin.button("Load (F9)")) {
            try SerializationPlugin.loadGame(commands, save_file);
        }

        if (ImGuiPlugin.button("Reset State")) {
            game.score = 0;
            game.level = 1;
            game.coins_collected = 0;
        }
    }
    ImGuiPlugin.end();

    // Info panel
    ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = 300 }, .Once);
    ImGuiPlugin.setNextWindowSize(.{ .x = 320, .y = 220 }, .Once);

    if (ImGuiPlugin.begin("Serialization Notes", null, .None)) {
        ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.5, .z = 0.5, .w = 1.0 }, "What Gets Serialized:");
        ImGuiPlugin.bulletText("Entities & Components");
        ImGuiPlugin.bulletText("Resources (POD types)");
        ImGuiPlugin.bulletText("Event read buffer");

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "NOT Serialized:");
        ImGuiPlugin.bulletText("Types with serialized=false");
        ImGuiPlugin.bulletText("Time, Input resources");

        ImGuiPlugin.spacing();
        ImGuiPlugin.textColored(.{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 }, "WASM:");
        ImGuiPlugin.textWrapped("Build with -Dfilesystem for IDBFS support (~50KB increase).");
    }
    ImGuiPlugin.end();
}
