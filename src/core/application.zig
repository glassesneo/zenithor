const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

const is_debug = builtin.mode == .Debug;

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
    // === Collect and deduplicate Components ===

    // compute max possible length for components
    var total_component_len: usize = 0;
    inline for (plugins) |P| {
        if (!@hasDecl(P, "Components")) continue;
        inline for (P.Components) |_| {
            total_component_len += 1;
        }
    }

    // dedup components into temporary list
    var tmp_components: [total_component_len]type = undefined;
    var component_count: usize = 0;
    inline for (plugins) |P| {
        if (!@hasDecl(P, "Components")) continue;
        inline for (P.Components) |C| {
            if (!containsType(tmp_components, C, component_count)) {
                tmp_components[component_count] = C;
                component_count += 1;
            }
        }
    }

    // finalize exact-sized component list
    var components: [component_count]type = undefined;
    comptime {
        var i: usize = 0;
        while (i < component_count) : (i += 1) {
            components[i] = tmp_components[i];
        }
    }
    const Components = std.meta.Tuple(&components);

    // === Collect and deduplicate Resources ===

    // compute max possible length for resources
    var total_resource_len: usize = 0;
    inline for (plugins) |P| {
        if (!@hasDecl(P, "Resources")) continue;
        inline for (P.Resources) |_| {
            total_resource_len += 1;
        }
    }

    // dedup resources into temporary list
    var tmp_resources: [total_resource_len]type = undefined;
    var resource_count: usize = 0;
    inline for (plugins) |P| {
        if (!@hasDecl(P, "Resources")) continue;
        inline for (P.Resources) |R| {
            if (!containsType(tmp_resources, R, resource_count)) {
                tmp_resources[resource_count] = R;
                resource_count += 1;
            }
        }
    }

    // finalize exact-sized resource list
    var resources: [resource_count]type = undefined;
    comptime {
        var i: usize = 0;
        while (i < resource_count) : (i += 1) {
            resources[i] = tmp_resources[i];
        }
    }
    const Resources = std.meta.Tuple(&resources);

    // === Collect and deduplicate Events ===

    // compute max possible length for events
    var total_event_len: usize = 0;
    inline for (plugins) |P| {
        if (!@hasDecl(P, "Events")) continue;
        inline for (P.Events) |_| {
            total_event_len += 1;
        }
    }

    // dedup events into temporary list
    var tmp_events: [total_event_len]type = undefined;
    var event_count: usize = 0;
    inline for (plugins) |P| {
        if (!@hasDecl(P, "Events")) continue;
        inline for (P.Events) |E| {
            if (!containsType(tmp_events, E, event_count)) {
                tmp_events[event_count] = E;
                event_count += 1;
            }
        }
    }

    // finalize exact-sized event list
    var events: [event_count]type = undefined;
    comptime {
        var i: usize = 0;
        while (i < event_count) : (i += 1) {
            events[i] = tmp_events[i];
        }
    }
    const Events = std.meta.Tuple(&events);

    return sparze.World(Components, Resources, Events);
}

pub fn run(comptime user_plugins: anytype) void {
    // Combine user plugins with builtin plugin
    const allPlugins = .{BuiltinPlugin} ++ user_plugins;
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
            if (is_debug and event_handler_count >= max_event_handlers) {
                std.debug.panic(
                    "Event handler overflow: reached max capacity of {} handlers. " ++
                        "Consider increasing max_event_handlers in application.zig or reducing event handler registrations.",
                    .{max_event_handlers},
                );
            }
            const handler_fn_info = @typeInfo(@TypeOf(handler_fn)).@"fn";
            const AppType = @This(); // Capture the App struct type

            const wrapper = struct {
                fn handle(ev: [*c]const sokol.app.Event) void {
                    // Build tuple type at compile time (similar to build() wrapper)
                    const ArgsType = comptime blk: {
                        var fields: [handler_fn_info.params.len]std.builtin.Type.StructField = undefined;
                        for (handler_fn_info.params, 0..) |param, i| {
                            // First parameter is always Event, second (if present) is *World
                            const ArgType = if (i == 0)
                                (param.type orelse sokol.app.Event)
                            else
                                (param.type orelse *World);
                            fields[i] = std.builtin.Type.StructField{
                                .name = std.fmt.comptimePrint("{d}", .{i}),
                                .type = ArgType,
                                .is_comptime = false,
                                .alignment = @alignOf(ArgType),
                                .default_value_ptr = null,
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
                    inline for (handler_fn_info.params, 0..) |_, i| {
                        if (i == 0) {
                            args[i] = ev.*;
                        } else {
                            args[i] = &AppType.world;
                        }
                    }

                    @call(.auto, handler_fn, args) catch {};
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

            inline for (allPlugins) |Plugin| {
                if (@hasDecl(Plugin, "build")) {
                    const build_fn_info = @typeInfo(@TypeOf(Plugin.build)).@"fn";

                    // Create a wrapper function to construct args at runtime
                    const wrapper = struct {
                        fn call(alloc: std.mem.Allocator, reg: system_module.SystemRegistry, w: *World) !void {
                            // Build tuple type at compile time
                            const ArgsType = comptime blk: {
                                var fields: [build_fn_info.params.len]std.builtin.Type.StructField = undefined;
                                for (build_fn_info.params, 0..) |param, i| {
                                    // Handle generic parameters (anytype) - use *World
                                    const ArgType = param.type orelse *World;
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
                                // Handle generic parameters (anytype) - use *World
                                const ParamType = param.type orelse *World;
                                if (ParamType == std.mem.Allocator) {
                                    args[i] = alloc;
                                } else if (ParamType == system_module.SystemRegistry) {
                                    args[i] = reg;
                                } else if (ParamType == *World) {
                                    args[i] = w;
                                }
                            }

                            try @call(.auto, Plugin.build, args);
                        }
                    }.call;

                    try wrapper(allocator, registry, &App.world);
                }
            }

            // Initialize sokol modules in dependency order:
            // 1. Graphics backend (gfx + gl) - required by imgui
            sokol.gfx.setup(.{
                .environment = sokol.glue.environment(),
                .logger = .{ .func = sokol.log.func },
            });
            sokol.gl.setup(.{});
            std.debug.print("Backend: {}\n", .{sokol.gfx.queryBackend()});

            // 2. Time module - required by time-using plugins
            sokol.time.setup();

            // 3. ImGui - depends on gfx/gl
            sokol.imgui.setup(.{
                .logger = .{ .func = sokol.log.func },
            });

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

            // Shutdown sokol modules in reverse order of initialization
            sokol.imgui.shutdown();
            // sokol.time does not require explicit shutdown
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
    const Duplicate = struct { field: u16 };
    const Plugin1 = struct {
        pub const A = struct {};
        pub const B = struct {};
        pub const Components = .{ A, B, Duplicate };
        pub const Events = .{};
    };
    const Plugin2 = struct {
        pub const C = struct { field1: []const u8 };
        pub const D = struct { field1: []const u8 };
        pub const Components = .{ C, D, Duplicate }; // duplicated
        pub const Events = .{};
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
        pub const Components = .{struct {}};
        pub const Events = .{};
    };

    const World = buildWorld(.{Plugin});
    var world = World.init(testing.allocator);
    defer world.deinit();
}

test "buildWorld: deduplicates events across plugins" {
    const DuplicateEvent = struct { value: u32 };
    const Plugin1 = struct {
        pub const EventA = struct {};
        pub const EventB = struct {};
        pub const Components = .{};
        pub const Events = .{ EventA, EventB, DuplicateEvent };
    };
    const Plugin2 = struct {
        pub const EventC = struct { data: []const u8 };
        pub const EventD = struct { data: []const u8 };
        pub const Components = .{};
        pub const Events = .{ EventC, EventD, DuplicateEvent }; // duplicated
    };

    const World = buildWorld(.{ Plugin1, Plugin2 });
    var world = World.init(testing.allocator);
    defer world.deinit();

    // If we got here without compile errors, deduplication worked
}
