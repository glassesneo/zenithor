const std = @import("std");
const sparze = @import("sparze");
// const World = sparze.World;

const testing = std.testing;
const sokol = @import("sokol");

const system_module = @import("system.zig");
const Stage = system_module.Stage;

fn containsType(comptime arr: anytype, comptime T: type, comptime n: usize) bool {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (arr[i] == T) return true;
    }
    return false;
}

pub fn buildWorld(comptime plugins: anytype) type {
    // compute max possible length
    var total_len: usize = 0;
    inline for (plugins) |P| {
        inline for (P.Components) |_| {
            total_len += 1;
        }
    }

    // dedup into temporary list
    var tmp: [total_len]type = undefined;
    var count: usize = 0;
    inline for (plugins) |Plugin| {
        inline for (Plugin.Components) |C| {
            if (!containsType(tmp, C, count)) {
                tmp[count] = C;
                count += 1;
            }
        }
    }

    // finalize exact-sized component list
    var components: [count]type = undefined;
    comptime {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            components[i] = tmp[i];
        }
    }
    const Components = std.meta.Tuple(&components);
    return sparze.FixedWorld(Components);
}

pub fn run(comptime plugins: anytype) void {
    const World = buildWorld(plugins);
    const SystemScheduler = system_module.SystemScheduler(World);

    const App = struct {
        var arena: std.heap.ArenaAllocator = undefined;
        var world: World = undefined;
        var system_scheduler: SystemScheduler = SystemScheduler.init();
        var startup_system_scheduler: SystemScheduler = SystemScheduler.init();
        var terminate_system_scheduler: SystemScheduler = SystemScheduler.init();

        pub fn registerSystem(comptime system_fn: anytype, stage: Stage) void {
            const wrapper = struct {
                fn run(w: *World) !void {
                    try w.runSystem(system_fn);
                }
            }.run;
            system_scheduler.register(wrapper, stage);
        }

        pub fn registerStartupSystem(comptime system_fn: anytype, stage: Stage) void {
            const wrapper = struct {
                fn run(w: *World) !void {
                    try w.runSystem(system_fn);
                }
            }.run;
            startup_system_scheduler.register(wrapper, stage);
        }

        pub fn registerTerminateSystem(comptime system_fn: anytype, stage: Stage) void {
            const wrapper = struct {
                fn run(w: *World) !void {
                    try w.runSystem(system_fn);
                }
            }.run;
            terminate_system_scheduler.register(wrapper, stage);
        }
    };

    const Callbacks = struct {
        export fn appInit() callconv(.c) void {
            App.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            const allocator = App.arena.allocator();
            App.world = .init(allocator);

            // Call plugin build functions
            const registry = system_module.SystemRegistry.init(App.registerSystem, App.registerStartupSystem, App.registerTerminateSystem);

            inline for (plugins) |Plugin| {
                if (@hasDecl(Plugin, "build")) {
                    Plugin.build(registry) catch unreachable;
                }
            }

            sokol.gfx.setup(.{
                .environment = sokol.glue.environment(),
                .logger = .{ .func = sokol.log.func },
            });
            std.debug.print("Backend: {}\n", .{sokol.gfx.queryBackend()});
            App.startup_system_scheduler.run(&App.world) catch unreachable;
        }

        fn appFrame() callconv(.c) void {
            App.system_scheduler.run(&App.world) catch unreachable;
        }

        export fn appCleanup() callconv(.c) void {
            App.terminate_system_scheduler.run(&App.world) catch unreachable;
            App.world.deinit();
            sokol.gfx.shutdown();
            App.arena.deinit();
        }
    };

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

test "buildWorld: deduplicates components across plugins" {
    const Plugin1 = struct {
        pub const Components = .{ u32, f32 };
    };
    const Plugin2 = struct {
        pub const Components = .{ u32, i32 }; // u32 duplicated
    };

    const World = buildWorld(.{ Plugin1, Plugin2 });
    var world = World.init(testing.allocator);
    defer world.deinit();

    // If we got here without compile errors, deduplication worked
    // (duplicate components would cause FixedWorld to fail)
}

test "buildWorld: handles empty plugin list" {
    const World = buildWorld(.{});
    var world = World.init(testing.allocator);
    defer world.deinit();
}

test "buildWorld: handles single plugin" {
    const Plugin = struct {
        pub const Components = .{u32};
    };

    const World = buildWorld(.{Plugin});
    var world = World.init(testing.allocator);
    defer world.deinit();
}
