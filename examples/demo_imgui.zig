const std = @import("std");
const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = @import("graphics_plugin");
const ImGuiPlugin = @import("imgui_plugin");

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, Game });
}

// Simple component to hold UI state
const Player = struct {
    position: [2]f32 = .{ 0, 0 },
    health: f32 = 100.0,
};

const Game = struct {
    pub const Components = .{ Player };
    pub const Events = .{};

    fn setup(commands: anytype) !void {
        // Create a player entity with UI state
        const entity = commands.createEntity();
        try commands.addComponent(entity, Player, .{});
    }

    // System to render ImGui UI based on ECS data
    fn renderUi(query: zenithor.SingleQuery(Player)) !void {
        for (query.components) |player| {
            // Using the new helper functions from ImGuiPlugin
            if (ImGuiPlugin.begin("Player Info", null, 0)) {
                ImGuiPlugin.text("Player position:");
                ImGuiPlugin.textFmt("{d:.2}, {d:.2}", .{ player.position[0], player.position[1] });
                ImGuiPlugin.textFmt("Health: {d:.1}", .{player.health});
            }
            ImGuiPlugin.end();
        }
    }

    pub fn build(registry: SystemRegistry) !void {
        registry.registerStartupSystem(setup, .first);
        registry.registerSystem(renderUi, .render);
    }
};