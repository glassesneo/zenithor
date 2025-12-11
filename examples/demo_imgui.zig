const std = @import("std");
const zenithor = @import("zenithor");
const Stage = zenithor.Stage;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const graphics_plugin = @import("graphics_plugin");
const GraphicsPlugin = graphics_plugin.DefaultPlugin;
const ImGuiPlugin = @import("imgui_plugin");

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, Game }, .{});
}

fn setup(commands: anytype) !void {
    // Create a player entity to show ECS integration
    const player_entity = commands.createEntity();
    try commands.addComponent(player_entity, BuiltinPlugin.Transform, BuiltinPlugin.Transform{ .x = 400, .y = 300, .z = 0 });
}

const Game = struct {
    pub const Components = .{};
    pub const Events = .{};

    pub const systems = .{
        .startup = &.{
            .{ .system = setup, .stage = .first },
        },
        .main = &.{
            .{ .system = uiSystem, .stage = .render },
            .{ .system = playerInfoSystem, .stage = .render },
        },
    };
};

fn uiSystem() void {
    // Using ImGui plugin helper functions
    var window_open = true;
    ImGuiPlugin.setNextWindowPos(ImGuiPlugin.ImVec2{ .x = 10, .y = 10 }, ImGuiPlugin.ImGuiCond.Once);
    ImGuiPlugin.setNextWindowSize(ImGuiPlugin.ImVec2{ .x = 400, .y = 200 }, ImGuiPlugin.ImGuiCond.Once);

    if (ImGuiPlugin.begin("ImGui ECS Integration Demo", &window_open, .None)) {
        ImGuiPlugin.text("ImGui Plugin - ECS Focused");
        ImGuiPlugin.separator();
        ImGuiPlugin.text("This plugin provides core ImGui functionality without Window management.");
        ImGuiPlugin.text("Use helper functions as shown in this example.");
        ImGuiPlugin.separator();
        ImGuiPlugin.text("Example of dynamic text display:");

        // Show the example from the user request
        const player_pos = .{ .x = 400.0, .y = 300.0, .z = 0.0 };
        ImGuiPlugin.textFmt("Player position:\n{d:.1}, {d:.1}, {d:.1}", .{ player_pos.x, player_pos.y, player_pos.z });

        ImGuiPlugin.separator();
        ImGuiPlugin.text("Benefits of this approach:");
        ImGuiPlugin.bulletText("Direct ECS integration");
        ImGuiPlugin.bulletText("No artificial Window components");
        ImGuiPlugin.bulletText("Full control over UI layout");
        ImGuiPlugin.bulletText("Better separation of concerns");
    }
    ImGuiPlugin.end();
}

fn playerInfoSystem(transforms: zenithor.SingleQuery(BuiltinPlugin.Transform)) void {
    ImGuiPlugin.setNextWindowPos(ImGuiPlugin.ImVec2{ .x = 10, .y = 220 }, ImGuiPlugin.ImGuiCond.Once);
    ImGuiPlugin.setNextWindowSize(ImGuiPlugin.ImVec2{ .x = 400, .y = 150 }, ImGuiPlugin.ImGuiCond.Once);

    if (ImGuiPlugin.begin("Player Info", null, .None)) {
        ImGuiPlugin.text("Player Entities:");
        ImGuiPlugin.separator();

        for (transforms.entities, transforms.components) |entity, transform| {
            ImGuiPlugin.textFmt("Entity {any}: ({d:.0}, {d:.0}, {d:.0})", .{ entity, transform.x, transform.y, transform.z });
        }
    }
    ImGuiPlugin.end();
}
