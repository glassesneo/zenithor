/// Example: Input + Time Driven Movement
///
/// Demonstrates keyboard input and delta-time based movement:
/// - isPressed() for single-fire actions (first frame only)
/// - isHeld() for continuous input while key is held
/// - delta_time for frame-rate independent movement
/// - time_scale for global speed control (pause/slow-mo)
///
/// Controls:
///   WASD - Move the circle
///   Space - Toggle pause (time_scale = 0)
///   1/2 - Slow down / Speed up time_scale
///
/// See: plugins/input/CLAUDE.md, plugins/time/CLAUDE.md
const std = @import("std");
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Color = zenithor.Color;
const Resource = zenithor.Resource;
const ResourceMut = zenithor.ResourceMut;
const SingleQuery = zenithor.SingleQuery;
const Shapes2DPlugin = @import("shapes2d_plugin");
const Renderer = @import("renderer_plugin");
const TimePlugin = @import("time_plugin");
const InputPlugin = @import("input_plugin");

pub fn main() !void {
    zenithor.run(.{Game}, .{});
}

// Tag component to identify the player entity
const Player = struct {};

const Game = struct {
    pub const Requires = .{ Shapes2DPlugin, TimePlugin, InputPlugin };

    pub const Components = .{Player};
    pub const Resources = .{};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = handleInput, .stage = .update },
        },
    };
};

fn setup(commands: anytype, pass_action: ResourceMut(Renderer.PassAction)) !void {
    pass_action.colors[0].clear_value = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1.0 };

    // Create player circle
    const player = commands.createEntity();
    try commands.addTag(player, Player);
    try commands.addComponent(player, Shapes2DPlugin.Circle, .{ .radius = 30, .segments = 32 });
    try commands.addComponent(player, Transform, .{ .x = 640, .y = 400, .z = 0 });
    try commands.addComponent(player, Color, Color.cyan);
}

fn handleInput(
    keyboard: Resource(InputPlugin.Keyboard),
    time: ResourceMut(TimePlugin.Time),
    player_query: SingleQuery(Transform),
) void {
    // isPressed: fires only on the first frame the key is pressed
    // Use for toggle actions
    if (keyboard.isPressed(.SPACE)) {
        time.time_scale = if (time.time_scale == 0.0) 1.0 else 0.0;
    }

    // isPressed for discrete time_scale adjustments
    if (keyboard.isPressed(._1)) {
        time.time_scale = @max(0.1, time.time_scale - 0.25);
    }
    if (keyboard.isPressed(._2)) {
        time.time_scale = @min(3.0, time.time_scale + 0.25);
    }

    // Calculate scaled delta for movement
    // delta_time is clamped to 100ms max to prevent physics explosions
    const dt = time.delta_time * time.time_scale;
    const speed: f32 = 300.0;

    // isHeld: true every frame while key is held
    // Use for continuous movement
    for (player_query.components) |*transform| {
        if (keyboard.isHeld(.W) or keyboard.isHeld(.UP)) transform.y -= speed * dt;
        if (keyboard.isHeld(.S) or keyboard.isHeld(.DOWN)) transform.y += speed * dt;
        if (keyboard.isHeld(.A) or keyboard.isHeld(.LEFT)) transform.x -= speed * dt;
        if (keyboard.isHeld(.D) or keyboard.isHeld(.RIGHT)) transform.x += speed * dt;

        // Clamp to screen bounds
        transform.x = std.math.clamp(transform.x, 30, 1250);
        transform.y = std.math.clamp(transform.y, 30, 770);
    }
}
