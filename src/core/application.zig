const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

const system_module = @import("system.zig");
const Stage = system_module.Stage;
const BuiltinPlugin = @import("builtin.zig");

const sparze = @import("sparze");
const sokol = @import("sokol");

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
        if (!@hasDecl(P, "Components")) continue;
        inline for (P.Components) |_| {
            total_len += 1;
        }
    }

    // dedup into temporary list
    var tmp: [total_len]type = undefined;
    var count: usize = 0;
    inline for (plugins) |P| {
        if (!@hasDecl(P, "Components")) continue;
        inline for (P.Components) |C| {
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
    return sparze.World(Components);
}

pub fn run(comptime plugins: anytype) void {
    const allPlugins = .{BuiltinPlugin} ++ plugins;
    const World = buildWorld(allPlugins);
    const SystemScheduler = system_module.SystemScheduler(World);

    const App = struct {
        var arena: std.heap.ArenaAllocator = undefined;
        var world: World = undefined;
        var system_scheduler: SystemScheduler = SystemScheduler.init();
        var startup_system_scheduler: SystemScheduler = SystemScheduler.init();
        var terminate_system_scheduler: SystemScheduler = SystemScheduler.init();

        const max_event_handlers = 32;
        var event_handlers: [max_event_handlers]*const fn ([*c]const sokol.app.Event) void = undefined;
        var event_handler_count: usize = 0;

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

        pub fn registerEventHandler(comptime handler_fn: anytype) void {
            const wrapper = struct {
                fn handle(ev: [*c]const sokol.app.Event) void {
                    handler_fn(ev.*) catch {};
                }
            }.handle;
            event_handlers[event_handler_count] = wrapper;
            event_handler_count += 1;
        }
    };

    const Callbacks = struct {
        export fn appInit() callconv(.c) void {
            const base_alloc: std.mem.Allocator = if (builtin.os.tag == .emscripten or builtin.cpu.arch.isWasm())
                std.heap.c_allocator
            else
                std.heap.page_allocator;
            App.arena = std.heap.ArenaAllocator.init(base_alloc);
            const allocator = App.arena.allocator();
            App.world = .init(allocator);
            inline for (allPlugins) |P| {
                if (!@hasDecl(P, "Groups")) continue;
                inline for (P.Groups) |Group| {
                    App.world.createGroup(Group) catch unreachable;
                }
            }

            // Call plugin build functions
            const registry = system_module.SystemRegistry.init(App.registerSystem, App.registerStartupSystem, App.registerTerminateSystem, App.registerEventHandler);

            inline for (plugins) |Plugin| {
                if (@hasDecl(Plugin, "build")) {
                    const build_fn_info = @typeInfo(@TypeOf(Plugin.build)).@"fn";

                    // Create a wrapper function to construct args at runtime
                    const wrapper = struct {
                        fn call(alloc: std.mem.Allocator, reg: system_module.SystemRegistry) !void {
                            // Build tuple type at compile time
                            const ArgsType = comptime blk: {
                                var fields: [build_fn_info.params.len]std.builtin.Type.StructField = undefined;
                                for (build_fn_info.params, 0..) |param, i| {
                                    const ArgType = param.type.?;
                                    // SystemRegistry contains comptime function pointers
                                    const is_comptime_type = ArgType == system_module.SystemRegistry;
                                    fields[i] = std.builtin.Type.StructField{
                                        .name = std.fmt.comptimePrint("{d}", .{i}),
                                        .type = ArgType,
                                        .is_comptime = is_comptime_type,
                                        .alignment = if (is_comptime_type) 0 else @alignOf(ArgType),
                                        .default_value_ptr = if (is_comptime_type) &reg else null,
                                    };
                                }
                                break :blk @Type(.{ .@"struct" = .{
                                    .layout = .auto,
                                    .is_tuple = true,
                                    .decls = &.{},
                                    .fields = &fields,
                                } });
                            };

                            // Populate the tuple at runtime
                            var args: ArgsType = undefined;
                            inline for (build_fn_info.params, 0..) |param, i| {
                                const ParamType = param.type.?;
                                if (ParamType == std.mem.Allocator) {
                                    args[i] = alloc;
                                } else if (ParamType == system_module.SystemRegistry) {
                                    args[i] = reg;
                                }
                            }

                            try @call(.auto, Plugin.build, args);
                        }
                    }.call;

                    try wrapper(allocator, registry);
                }
            }

            sokol.gfx.setup(.{
                .environment = sokol.glue.environment(),
                .logger = .{ .func = sokol.log.func },
            });
            sokol.gl.setup(.{});
            std.debug.print("Backend: {}\n", .{sokol.gfx.queryBackend()});
            App.world.beginFrame();
            App.startup_system_scheduler.run(&App.world) catch unreachable;
            App.world.endFrame() catch unreachable;
        }

        fn appFrame() callconv(.c) void {
            App.world.beginFrame();
            App.system_scheduler.run(&App.world) catch unreachable;
            App.world.endFrame() catch unreachable;
        }

        export fn appCleanup() callconv(.c) void {
            App.world.beginFrame();
            App.terminate_system_scheduler.run(&App.world) catch unreachable;
            App.world.endFrame() catch unreachable;
            App.world.deinit();
            App.arena.deinit();
            sokol.gl.shutdown();
            sokol.gfx.shutdown();
        }

        export fn appEvent(ev: [*c]const sokol.app.Event) void {
            for (0..App.event_handler_count) |i| {
                App.event_handlers[i](ev);
            }
        }
    };

    const desc: sokol.app.Desc = .{
        .init_cb = Callbacks.appInit,
        .frame_cb = Callbacks.appFrame,
        .cleanup_cb = Callbacks.appCleanup,
        .event_cb = Callbacks.appEvent,
        .width = 1280,
        .height = 800,
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
