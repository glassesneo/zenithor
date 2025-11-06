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
    _ = try commands.createEntityWith(.{
        BuiltinPlugin.Transform{ .x = 150, .y = 150, .z = 0 },
        ImGuiPlugin.Window{ .title = "Hello ImGui!", .open = true },
    });
    _ = try commands.createEntityWith(.{
        BuiltinPlugin.Transform{ .x = 250, .y = 150, .z = 0 },
        ImGuiPlugin.Window{ .title = "Another window", .open = true },
    });
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
