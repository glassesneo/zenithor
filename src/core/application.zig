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
    return inline for (0..n) |i| {
        if (arr[i] == T) break true;
    } else false;
}

/// Expands plugin dependencies recursively, auto-including all required plugins
/// and detecting circular dependencies at compile time.
///
/// Takes a tuple of plugins and returns a tuple with all dependencies included
/// in topological order (dependencies before dependents).
///
/// Supports:
/// - `pub const Requires = .{Plugin1, Plugin2}` - mandatory dependencies
///
/// Deduplicates plugins (keeps first occurrence) and validates no circular dependencies.
fn expandPluginDependencies(comptime user_plugins: anytype) type {
    const PluginSet = struct {
        plugins: [100]type = undefined,
        count: usize = 0,
        visiting: [100]type = undefined,
        visiting_count: usize = 0,

        fn contains(self: *const @This(), comptime T: type) bool {
            return inline for (0..self.count) |i| {
                if (self.plugins[i] == T) break true;
            } else false;
        }

        fn isVisiting(self: *const @This(), comptime T: type) bool {
            return inline for (0..self.visiting_count) |i| {
                if (self.visiting[i] == T) break true;
            } else false;
        }

        fn add(self: *@This(), comptime T: type) void {
            if (!self.contains(T)) {
                self.plugins[self.count] = T;
                self.count += 1;
            }
        }

        fn pushVisiting(self: *@This(), comptime T: type) void {
            self.visiting[self.visiting_count] = T;
            self.visiting_count += 1;
        }

        fn popVisiting(self: *@This()) void {
            self.visiting_count -= 1;
        }

        fn expand(self: *@This(), comptime plugin: type) void {
            // Check for cycles
            if (self.isVisiting(plugin)) {
                @compileError("Circular plugin dependency detected involving " ++ @typeName(plugin));
            }

            // Skip if already processed
            if (self.contains(plugin)) {
                return;
            }

            // Mark as visiting
            self.pushVisiting(plugin);

            // Recursively expand required dependencies first
            if (@hasDecl(plugin, "Requires")) {
                inline for (plugin.Requires) |dep| {
                    self.expand(dep);
                }
            }

            // Add this plugin after its dependencies
            self.add(plugin);

            // Unmark from visiting
            self.popVisiting();
        }
    };

    var set = PluginSet{};
    inline for (user_plugins) |plugin| {
        set.expand(plugin);
    }

    // Build array of plugin types
    const result_array = blk: {
        var arr: [set.count]type = undefined;
        inline for (0..set.count) |i| {
            arr[i] = set.plugins[i];
        }
        break :blk arr;
    };
    const result_count = set.count;

    // Return a struct type that wraps the result
    return struct {
        pub const len = result_count;
        pub const plugins = result_array;

        pub fn get(comptime index: usize) type {
            return result_array[index];
        }
    };
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
    const components: [component_count]type = blk: {
        var components: [component_count]type = undefined;
        inline for (0..component_count) |i| {
            components[i] = tmp_components[i];
        }
        break :blk components;
    };
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
    const resources: [resource_count]type = blk: {
        var resources: [resource_count]type = undefined;
        inline for (0..resource_count) |i| {
            resources[i] = tmp_resources[i];
        }
        break :blk resources;
    };
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
    const events: [event_count]type = blk: {
        var events: [event_count]type = undefined;
        inline for (0..event_count) |i| {
            events[i] = tmp_events[i];
        }
        break :blk events;
    };
    const Events = std.meta.Tuple(&events);

    return sparze.World(Components, Resources, Events);
}

const ZenithorOptions = struct {
    // Omitted when targeting webassembly
    allocator: std.mem.Allocator = std.heap.page_allocator,
};

pub fn run(comptime user_plugins: anytype, options: ZenithorOptions) void {
    // Expand user plugins to include all dependencies (auto-include)
    const Expanded = expandPluginDependencies(user_plugins);

    // Combine expanded plugins with builtin plugin
    const allPlugins = .{BuiltinPlugin} ++ Expanded.plugins;

    const World = buildWorld(allPlugins);
    const SystemScheduler = system_module.SystemScheduler(World);

    const AppState = struct {
        const Self = @This();
        const max_event_handlers = 32;

        arena: std.heap.ArenaAllocator,
        allocator: std.mem.Allocator,
        world: World,
        system_scheduler: SystemScheduler,
        startup_system_scheduler: SystemScheduler,
        terminate_system_scheduler: SystemScheduler,
        event_handlers: [max_event_handlers]*const fn ([*c]const sokol.app.Event, *World) anyerror!void,
        event_handler_count: usize = 0,

        /// Creates an uninitialized AppState with arena allocator.
        /// IMPORTANT: Call `finishInit()` on the result after it's in its final memory location
        /// to avoid dangling pointer issues with the arena allocator.
        fn initArena(base_allocator: std.mem.Allocator) Self {
            return .{
                .arena = std.heap.ArenaAllocator.init(base_allocator),
                // These will be properly initialized by finishInit()
                .allocator = undefined,
                .world = undefined,
                .system_scheduler = .init(),
                .startup_system_scheduler = .init(),
                .terminate_system_scheduler = .init(),
                .event_handlers = undefined,
                .event_handler_count = 0,
            };
        }

        /// Finishes initialization after the struct is in its final memory location.
        /// This ensures the allocator pointer points to the stable arena location.
        fn finishInit(self: *Self) void {
            self.allocator = self.arena.allocator();
            self.world = World.init(self.allocator);
        }

        fn deinit(self: *Self) void {
            self.world.deinit();
            self.arena.deinit();
        }
    };

    const Callbacks = struct {
        export fn appInit(state: ?*anyopaque) callconv(.c) void {
            var app_state = @as(*AppState, @ptrCast(@alignCast(state)));

            // Create groups
            inline for (allPlugins) |P| {
                if (!@hasDecl(P, "Groups")) continue;
                inline for (P.Groups) |Group| {
                    app_state.world.createGroup(Group) catch unreachable;
                }
            }

            // Initialize resources and register systems for each plugin
            inline for (allPlugins, 0..) |Plugin, plugin_idx| {
                const plugin_name = @typeName(Plugin);

                // NEW: Declarative system registration via pub const systems
                if (@hasDecl(Plugin, "systems")) {
                    const systems_decl = Plugin.systems;

                    // Register startup systems
                    if (@hasField(@TypeOf(systems_decl), "startup")) {
                        inline for (systems_decl.startup) |decl| {
                            app_state.startup_system_scheduler.registerDecl(decl, plugin_name, @intCast(plugin_idx));
                        }
                    }

                    // Register main systems
                    if (@hasField(@TypeOf(systems_decl), "main")) {
                        inline for (systems_decl.main) |decl| {
                            app_state.system_scheduler.registerDecl(decl, plugin_name, @intCast(plugin_idx));
                        }
                    }

                    // Register terminate systems
                    if (@hasField(@TypeOf(systems_decl), "terminate")) {
                        inline for (systems_decl.terminate) |decl| {
                            app_state.terminate_system_scheduler.registerDecl(decl, plugin_name, @intCast(plugin_idx));
                        }
                    }

                    // Register event handlers (standardized signature: fn(event, world) !void)
                    if (@hasDecl(Plugin, "systems") and @hasField(@TypeOf(Plugin.systems), "event_handlers")) {
                        inline for (Plugin.systems.event_handlers) |handler_fn| {
                            if (builtin.mode == .Debug and app_state.event_handler_count >= AppState.max_event_handlers) {
                                std.debug.panic(
                                    "Event handler overflow: reached max capacity of {} handlers. " ++
                                        "Consider increasing max_event_handlers.",
                                    .{AppState.max_event_handlers},
                                );
                            }
                            // Create compile-time wrapper that captures handler_fn
                            const HandlerWrapper = struct {
                                fn call(ev: [*c]const sokol.app.Event, w: *World) !void {
                                    const handler_type_info = @typeInfo(@TypeOf(handler_fn));
                                    if (handler_type_info.@"fn".return_type.? == void) {
                                        handler_fn(ev.*, w);
                                    } else {
                                        try handler_fn(ev.*, w);
                                    }
                                }
                            };
                            // Store compile-time generated wrapper function
                            app_state.event_handlers[app_state.event_handler_count] = HandlerWrapper.call;
                            app_state.event_handler_count += 1;
                        }
                    }
                }
            }

            // Finalize system registration - sort by priority and apply constraints
            app_state.system_scheduler.finalize();
            app_state.startup_system_scheduler.finalize();
            app_state.terminate_system_scheduler.finalize();

            // Initialize sokol modules in dependency order:
            // 1. Graphics backend (gfx + gl) - required by imgui
            sokol.gfx.setup(.{
                .environment = sokol.glue.environment(),
                .logger = .{ .func = sokol.log.func },
            });

            sokol.gl.setup(.{
                .logger = .{ .func = sokol.log.func },
            });

            if (is_debug) {
                std.debug.print("Backend: {}\n", .{sokol.gfx.queryBackend()});
            }

            // 2. Time module - required by time-using plugins
            sokol.time.setup();

            app_state.world.beginFrame();
            app_state.startup_system_scheduler.run(&app_state.world);
            app_state.world.endFrame() catch unreachable;
        }

        export fn appFrame(state: ?*anyopaque) callconv(.c) void {
            var app_state = @as(*AppState, @ptrCast(@alignCast(state)));
            app_state.world.beginFrame();
            app_state.system_scheduler.run(&app_state.world);
            app_state.world.endFrame() catch unreachable;
        }

        export fn appCleanup(state: ?*anyopaque) callconv(.c) void {
            var app_state = @as(*AppState, @ptrCast(@alignCast(state)));
            app_state.world.beginFrame();
            app_state.terminate_system_scheduler.run(&app_state.world);
            app_state.world.endFrame() catch unreachable;
            app_state.deinit();

            // Shutdown sokol modules in reverse order of initialization
            // sokol.time does not require explicit shutdown
            sokol.gl.shutdown();
            sokol.gfx.shutdown();
        }

        export fn appEvent(ev: [*c]const sokol.app.Event, state: ?*anyopaque) callconv(.c) void {
            var app_state = @as(*AppState, @ptrCast(@alignCast(state)));
            for (0..app_state.event_handler_count) |i| {
                app_state.event_handlers[i](ev, &app_state.world) catch |err| {
                    var queue = app_state.world.getEventStoragePtrMut(BuiltinPlugin.EventLoopError);
                    queue.enqueue(.{ .err = err }) catch |alloc_err| {
                        std.debug.print("Failed to allocate memory: {any}\n", .{alloc_err});
                    };
                };
            }
        }
    };

    {
        const base_allocator: std.mem.Allocator = if (builtin.os.tag == .emscripten or builtin.cpu.arch.isWasm())
            std.heap.c_allocator
        else
            options.allocator;

        // On WASM, sokol.app.run() returns immediately (event-driven model),
        // so we must heap-allocate AppState to prevent dangling pointer issues.
        // On native platforms, sokol.app.run() blocks, so stack allocation works.
        const is_wasm = builtin.os.tag == .emscripten or builtin.cpu.arch.isWasm();

        if (is_wasm) {
            // Heap allocate for WASM - memory is managed by the arena and never freed
            // (the program runs until the browser tab is closed)
            const app_state = base_allocator.create(AppState) catch @panic("Failed to allocate AppState");
            app_state.* = AppState.initArena(base_allocator);
            app_state.finishInit();

            const desc: sokol.app.Desc = .{
                .user_data = app_state,
                .init_userdata_cb = Callbacks.appInit,
                .frame_userdata_cb = Callbacks.appFrame,
                .cleanup_userdata_cb = Callbacks.appCleanup,
                .event_userdata_cb = Callbacks.appEvent,
                .width = 1280,
                .height = 800,
                .icon = .{ .sokol_default = true },
                .window_title = "window",
                .logger = .{ .func = sokol.log.func },
                .win32 = .{ .console_attach = true },
            };

            sokol.app.run(desc);
        } else {
            // Stack allocate for native - sokol.app.run() blocks until exit
            var app_state = AppState.initArena(base_allocator);
            app_state.finishInit();

            const desc: sokol.app.Desc = .{
                .user_data = &app_state,
                .init_userdata_cb = Callbacks.appInit,
                .frame_userdata_cb = Callbacks.appFrame,
                .cleanup_userdata_cb = Callbacks.appCleanup,
                .event_userdata_cb = Callbacks.appEvent,
                .width = 1280,
                .height = 800,
                .icon = .{ .sokol_default = true },
                .window_title = "window",
                .logger = .{ .func = sokol.log.func },
                .win32 = .{ .console_attach = true },
            };

            sokol.app.run(desc);
        }
    }
}
