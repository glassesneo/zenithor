const std = @import("std");
const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const BuiltinPlugin = zenithor.BuiltinPlugin;
const GraphicsPlugin = @import("graphics_plugin");
const ImGuiPlugin = @import("imgui_plugin");

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, Game });
}

fn setup(commands: anytype) !void {
    const entity1 = commands.createEntity();
    try commands.addComponent(
        entity1,
        ImGuiPlugin.Window,
        ImGuiPlugin.Window.init("Hello ImGui!"),
    );

    const entity2 = commands.createEntity();
    try commands.addComponent(
        entity2,
        ImGuiPlugin.Window,
        ImGuiPlugin.Window.init("Another window"),
    );
}

// fn printTransform(transforms: zenithor.SingleQuery(BuiltinPlugin.Transform)) !void {
// for (transforms.entities, transforms.components) |entity, transform| {
// std.debug.print("entity: {any}, transform: {any}\n", .{ entity, transform });
// }
// }

const Game = struct {
    pub const Components = .{};
    pub const Events = .{};

    pub fn build(registry: SystemRegistry) !void {
        registry.registerStartupSystem(setup, .first);
        // registry.registerSystem(printTransform, .first);
    }
};