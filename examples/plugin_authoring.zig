/// Example: Plugin Authoring + Requires
///
/// Demonstrates creating a custom plugin:
/// - Plugin structure with Components, Resources, Events declarations
/// - Declarative system registration via `pub const systems`
/// - Plugin dependencies via `pub const Requires`
/// - Dependency expansion (transitive includes)
///
/// The example creates a "HealthPlugin" that depends on TimePlugin,
/// then a "GamePlugin" that depends on HealthPlugin.
///
/// See: CLAUDE.md (Plugin Development, Plugin Dependencies sections)
const std = @import("std");
const log = std.log.scoped(.plugin_authoring);
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Color = zenithor.Color;
const Resource = zenithor.Resource;
const ResourceMut = zenithor.ResourceMut;
const SingleQuery = zenithor.SingleQuery;
const EventWriter = zenithor.EventWriter;
const EventReader = zenithor.EventReader;
const Shapes2DPlugin = @import("shapes2d_plugin");
const Renderer = @import("renderer_plugin");
const TimePlugin = @import("time_plugin");
const InputPlugin = @import("input_plugin");
const ImGuiPlugin = @import("imgui_plugin");

pub fn main() !void {
    // Only include GamePlugin - all dependencies auto-included via Requires
    zenithor.run(.{GamePlugin}, .{});
}

// =============================================================================
// HEALTH PLUGIN - Custom plugin demonstrating Components/Resources/Events
// =============================================================================
const HealthPlugin = struct {
    // Declare dependency on Time plugin (auto-included)
    pub const Requires = .{TimePlugin};

    // Component types
    pub const Health = struct {
        current: i32,
        max: i32,
    };

    // Resource types
    pub const HealthConfig = struct {
        regen_rate: f32 = 5.0, // HP per second
        regen_enabled: bool = true,
    };

    // Event types
    pub const DamageEvent = struct {
        amount: i32,
    };
    pub const HealEvent = struct {
        amount: i32,
    };

    // Export for other plugins
    pub const Components = .{Health};
    pub const Resources = .{HealthConfig};
    pub const Events = .{ DamageEvent, HealEvent };

    // Declarative system registration
    pub const systems = .{
        .startup = &.{
            .{ .system = initHealth, .stage = .first },
        },
        .main = &.{
            .{ .system = processHealthEvents, .stage = .update },
            .{ .system = regenerateHealth, .stage = .update },
        },
    };

    fn initHealth(commands: anytype) void {
        commands.setResource(HealthConfig, .{
            .regen_rate = 5.0,
            .regen_enabled = true,
        });
    }

    fn processHealthEvents(
        damage_events: EventReader(DamageEvent),
        heal_events: EventReader(HealEvent),
        health_query: SingleQuery(Health),
    ) void {
        // Process damage events
        for (damage_events.read()) |event| {
            for (health_query.entities, health_query.components) |_, *health| {
                health.current = @max(0, health.current - event.amount);
            }
        }

        // Process heal events
        for (heal_events.read()) |event| {
            for (health_query.entities, health_query.components) |_, *health| {
                health.current = @min(health.max, health.current + event.amount);
            }
        }
    }

    fn regenerateHealth(
        time: Resource(TimePlugin.Time),
        config: Resource(HealthConfig),
        health_query: SingleQuery(Health),
    ) void {
        if (!config.regen_enabled) return;

        const regen_amount = config.regen_rate * time.delta_time;
        for (health_query.entities, health_query.components) |_, *health| {
            if (health.current < health.max) {
                const new_health = @as(f32, @floatFromInt(health.current)) + regen_amount;
                health.current = @min(health.max, @as(i32, @intFromFloat(new_health)));
            }
        }
    }
};

// =============================================================================
// GAME PLUGIN - Uses HealthPlugin (demonstrates plugin dependencies)
// =============================================================================
const GamePlugin = struct {
    // Declare all direct dependencies (HealthPlugin already includes TimePlugin transitively)
    // Best practice: explicitly declare every plugin whose types you use
    pub const Requires = .{ HealthPlugin, Renderer, Shapes2DPlugin, InputPlugin, ImGuiPlugin };

    // Tag component
    pub const Player = struct {};

    pub const Components = .{Player};
    pub const Resources = .{};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = setupGame, .stage = .first },
        },
        .main = &.{
            .{ .system = handleGameInput, .stage = .update },
            .{ .system = drawGameUI, .stage = .render },
        },
    };

    fn setupGame(commands: anytype, pass_action: ResourceMut(Renderer.PassAction)) !void {
        pass_action.colors[0].clear_value = .{ .r = 0.1, .g = 0.15, .b = 0.2, .a = 1.0 };

        // Create player entity with Health component from HealthPlugin
        const player = commands.createEntity();
        try commands.addTag(player, Player);
        try commands.addComponent(player, Shapes2DPlugin.Circle, .{ .radius = 40, .segments = 32 });
        try commands.addComponent(player, Transform, .{ .x = 640, .y = 400, .z = 0 });
        try commands.addComponent(player, Color, Color.green);
        try commands.addComponent(player, HealthPlugin.Health, .{ .current = 100, .max = 100 });

        log.info("Plugin Authoring Demo", .{});
        log.info("GamePlugin -> HealthPlugin -> TimePlugin (transitive)", .{});
    }

    fn handleGameInput(
        keyboard: Resource(InputPlugin.Keyboard),
        damage_writer: EventWriter(HealthPlugin.DamageEvent),
        heal_writer: EventWriter(HealthPlugin.HealEvent),
        config: ResourceMut(HealthPlugin.HealthConfig),
    ) !void {
        // D key = take damage
        if (keyboard.isPressed(.D)) {
            try damage_writer.enqueue(.{ .amount = 20 });
        }

        // H key = heal
        if (keyboard.isPressed(.H)) {
            try heal_writer.enqueue(.{ .amount = 30 });
        }

        // R key = toggle regen
        if (keyboard.isPressed(.R)) {
            config.regen_enabled = !config.regen_enabled;
        }
    }

    fn drawGameUI(
        health_query: SingleQuery(HealthPlugin.Health),
        config: ResourceMut(HealthPlugin.HealthConfig),
        time: Resource(TimePlugin.Time),
    ) void {
        ImGuiPlugin.setNextWindowPos(.{ .x = 10, .y = 10 }, .Once);
        ImGuiPlugin.setNextWindowSize(.{ .x = 350, .y = 280 }, .Once);

        if (ImGuiPlugin.begin("Plugin Authoring Demo", null, .None)) {
            ImGuiPlugin.textColored(.{ .x = 0.2, .y = 1.0, .z = 0.8, .w = 1.0 }, "Plugin Dependency Chain");
            ImGuiPlugin.separator();
            ImGuiPlugin.bulletText("GamePlugin");
            ImGuiPlugin.indent();
            ImGuiPlugin.bulletText("-> HealthPlugin (Requires)");
            ImGuiPlugin.indent();
            ImGuiPlugin.bulletText("-> TimePlugin (transitive)");
            ImGuiPlugin.unindent();
            ImGuiPlugin.unindent();

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.8, .z = 0.2, .w = 1.0 }, "Health System (from HealthPlugin)");
            ImGuiPlugin.separator();

            for (health_query.components) |health| {
                const pct = @as(f32, @floatFromInt(health.current)) / @as(f32, @floatFromInt(health.max));
                const color = if (pct > 0.5)
                    ImGuiPlugin.ImVec4{ .x = 0.2, .y = 1.0, .z = 0.2, .w = 1.0 }
                else if (pct > 0.25)
                    ImGuiPlugin.ImVec4{ .x = 1.0, .y = 1.0, .z = 0.2, .w = 1.0 }
                else
                    ImGuiPlugin.ImVec4{ .x = 1.0, .y = 0.2, .z = 0.2, .w = 1.0 };

                ImGuiPlugin.textColoredFmt(color, "HP: {} / {}", .{ health.current, health.max });
            }

            ImGuiPlugin.textFmt("Regen: {} ({d:.1} HP/s)", .{
                config.regen_enabled,
                config.regen_rate,
            });

            _ = ImGuiPlugin.sliderFloat("Regen Rate", &config.regen_rate, 0.0, 20.0);

            ImGuiPlugin.spacing();
            ImGuiPlugin.textColored(.{ .x = 1.0, .y = 0.5, .z = 0.5, .w = 1.0 }, "Controls");
            ImGuiPlugin.separator();
            ImGuiPlugin.bulletText("D - Take damage (-20 HP)");
            ImGuiPlugin.bulletText("H - Heal (+30 HP)");
            ImGuiPlugin.bulletText("R - Toggle regeneration");

            ImGuiPlugin.spacing();
            ImGuiPlugin.textFmt("Time (from TimePlugin): {d:.1}s", .{time.total_time});
        }
        ImGuiPlugin.end();
    }
};
