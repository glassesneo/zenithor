const std = @import("std");
const sparze = @import("sparze");
const testing = std.testing;
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;

const plugin_module = @import("plugin.zig");
const AbstractPlugin = plugin_module.AbstractPlugin;

const state = struct {
    var pass_action: sg.PassAction = .{};
};

export fn appInit() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    };
    std.debug.print("Backend: {}\n", .{sg.queryBackend()});
}

export fn appFrame() void {
    // const g = state.pass_action.colors[0].clear_value.g + 0.01;
    // state.pass_action.colors[0].clear_value.g = if (g > 1.0) 0.0 else g;
    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.endPass();
    sg.commit();
}

export fn appCleanup() void {
    sg.shutdown();
}

pub const Application = struct {
    allocator: std.mem.Allocator,
    component_arena: std.heap.ArenaAllocator,
    plugins: std.ArrayList(AbstractPlugin),
    world: sparze.World,

    pub fn init(allocator: std.mem.Allocator) Application {
        return .{
            .allocator = allocator,
            .component_arena = .init(allocator),
            .world = .init(allocator),
            .plugins = .{},
        };
    }

    pub fn deinit(self: *Application) void {
        for (self.plugins.items) |plugin| {
            plugin.deinit();
        }
        self.plugins.deinit(self.allocator);
        self.world.deinit();
        self.component_arena.deinit();
    }

    pub fn registerPlugin(self: *Application, comptime P: type) !void {
        const arena_allocator = self.component_arena.allocator();
        try self.plugins.append(self.allocator, try AbstractPlugin.init(P, arena_allocator));
    }

    pub fn buildPlugin(self: *Application) !void {
        for (self.plugins.items) |plugin| {
            try plugin.build(&self.world);
        }
    }

    pub fn run(_: *Application) !void {
        sapp.run(.{
            .init_cb = appInit,
            .frame_cb = appFrame,
            .cleanup_cb = appCleanup,
            .width = 640,
            .height = 480,
            .icon = .{ .sokol_default = true },
            .window_title = "window",
            .logger = .{ .func = slog.func },
            .win32_console_attach = true,
        });
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

    const ExamplePlugin = plugin_module.Plugin(.{ Position, Velocity });

    const allocator = std.testing.allocator;

    var app = Application.init(allocator);
    defer app.deinit();

    try app.registerPlugin(ExamplePlugin);
    try app.buildPlugin();

    const e1 = app.world.createEntity();
    try app.world.addComponent(e1, Position, .{ .x = 1.0, .y = 2.0 });
    std.debug.print("Position of e1: {any}\n", .{app.world.getComponent(e1, Position)});
}
