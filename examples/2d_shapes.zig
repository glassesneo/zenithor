const zenithor = @import("zenithor");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    zenithor.init(allocator);
    defer zenithor.deinit();
    try zenithor.registerPlugin(zenithor.GraphicsPlugin);
    try zenithor.run(Game);
}

fn changeColor() !void {
    const g = zenithor.GraphicsPlugin.pass_action.colors[0].clear_value.g + 0.01;
    zenithor.GraphicsPlugin.pass_action.colors[0].clear_value.g = if (g > 1.0) 0.0 else g;
}

const Game = struct {
    const Components = .{};

    pub fn build(world: *zenithor.World) !void {
        world.registerSystem(changeColor, .render);
    }
};

const std = @import("std");
