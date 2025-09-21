const std = @import("std");
const sparze = @import("sparze");
const testing = std.testing;
const sokol = @import("sokol");

const plugin_module = @import("plugin.zig");
const AbstractPlugin = plugin_module.AbstractPlugin;

const Callbacks = struct {
    export fn appInit() callconv(.c) void {
        sokol.gfx.setup(.{
            .environment = sokol.glue.environment(),
            .logger = .{ .func = sokol.log.func },
        });
        std.debug.print("Backend: {}\n", .{sokol.gfx.queryBackend()});
        Application.app.world.runStartupSystems() catch unreachable;
    }

    fn appFrame() callconv(.c) void {
        Application.app.world.runSystems() catch unreachable;
    }

    export fn appCleanup() callconv(.c) void {
        Application.app.world.runTerminateSystems() catch unreachable;
        sokol.gfx.shutdown();
    }
};

pub const Application = struct {
    allocator: std.mem.Allocator,
    component_arena: std.heap.ArenaAllocator,
    plugins: std.ArrayList(AbstractPlugin),
    world: sparze.World,
    pub var app: Application = undefined;

    pub fn init(allocator: std.mem.Allocator) void {
        app = .{
            .allocator = allocator,
            .component_arena = .init(allocator),
            .world = .init(allocator),
            .plugins = .{},
        };
    }

    pub fn deinit() void {
        for (app.plugins.items) |plugin| {
            plugin.deinit();
        }
        app.plugins.deinit(app.allocator);
        app.world.deinit();
        app.component_arena.deinit();
    }

    pub fn registerPlugin(comptime P: type) !void {
        const arena_allocator = app.component_arena.allocator();
        try app.plugins.append(app.allocator, try AbstractPlugin.init(P, arena_allocator));
    }

    fn buildPlugins() !void {
        for (app.plugins.items) |plugin| {
            try plugin.build(&app.world);
        }
    }

    pub fn run(comptime Game: type) !void {
        try registerPlugin(Game);
        try buildPlugins();
        const desc: sokol.app.Desc = .{
            .init_cb = Callbacks.appInit,
            .frame_cb = Callbacks.appFrame,
            .cleanup_cb = Callbacks.appCleanup,
            .width = 640,
            .height = 480,
            .icon = .{ .sokol_default = true },
            .window_title = "window",
            .logger = .{ .func = sokol.log.func },
            .win32_console_attach = true,
        };

        sokol.app.run(desc);
    }
};

test "Register plugins" {
    const Position = struct {
        x: f32,
        y: f32,
    };

    const Velocity = struct {
        x: f32,
        y: f32,
    };

    const ExamplePlugin = struct {
        pub const Components = .{ Position, Velocity };

        pub fn build(world: *sparze.World) !void {
            _ = world;
        }
    };

    const allocator = std.testing.allocator;

    Application.init(allocator);
    defer Application.deinit();

    try Application.registerPlugin(ExamplePlugin);
    try Application.buildPlugins();

    const e1 = Application.app.world.createEntity();
    try Application.app.world.addComponent(e1, Position, .{ .x = 1.0, .y = 2.0 });
    std.debug.print("Position of e1: {any}\n", .{Application.app.world.getComponent(e1, Position)});
}
