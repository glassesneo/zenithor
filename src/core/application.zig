const std = @import("std");
const log = std.log.scoped(.application);
const testing = std.testing;
const builtin = @import("builtin");

const is_debug = builtin.mode == .Debug;

const system_module = @import("system.zig");
const Stage = system_module.Stage;
const BuiltinPlugin = @import("builtin.zig");

const sparze = @import("sparze");
const sokol = @import("sokol");

// =============================================================================
// PLATFORM ABSTRACTION LAYER
// =============================================================================
// Stateless wrappers over sokol.app functions. These provide a stable API
// that hides the underlying platform layer from user code.
//
// **Design principle**: Users should never need to import `sokol` directly
// for common application operations.

/// Mouse cursor types for `setCursor()`.
pub const Cursor = sokol.app.MouseCursor;

// -----------------------------------------------------------------------------
// Window Functions
// -----------------------------------------------------------------------------

/// Returns the current window width in pixels.
pub fn windowWidth() i32 {
    return sokol.app.width();
}

/// Returns the current window height in pixels.
pub fn windowHeight() i32 {
    return sokol.app.height();
}

/// Returns the current window width as a float.
pub fn windowWidthF() f32 {
    return sokol.app.widthf();
}

/// Returns the current window height as a float.
pub fn windowHeightF() f32 {
    return sokol.app.heightf();
}

/// Returns the DPI scale factor (e.g., 2.0 on Retina displays).
pub fn dpiScale() f32 {
    return sokol.app.dpiScale();
}

/// Returns true if running in high-DPI mode.
pub fn isHighDpi() bool {
    return sokol.app.highDpi();
}

/// Returns true if the window is currently fullscreen.
pub fn isFullscreen() bool {
    return sokol.app.isFullscreen();
}

/// Toggles fullscreen mode.
pub fn toggleFullscreen() void {
    sokol.app.toggleFullscreen();
}

/// Sets the window title.
pub fn setWindowTitle(title: [:0]const u8) void {
    sokol.app.setWindowTitle(title);
}

// -----------------------------------------------------------------------------
// Cursor Functions
// -----------------------------------------------------------------------------

/// Shows or hides the mouse cursor.
pub fn showCursor(visible: bool) void {
    sokol.app.showMouse(visible);
}

/// Returns true if the cursor is currently visible.
pub fn isCursorVisible() bool {
    return sokol.app.mouseShown();
}

/// Locks the mouse cursor to the window (for FPS-style camera controls).
/// When locked, the cursor is hidden and mouse movement is reported as deltas.
pub fn lockCursor(locked: bool) void {
    sokol.app.lockMouse(locked);
}

/// Returns true if the cursor is currently locked.
pub fn isCursorLocked() bool {
    return sokol.app.mouseLocked();
}

/// Sets the mouse cursor shape.
pub fn setCursor(cursor: Cursor) void {
    sokol.app.setMouseCursor(cursor);
}

/// Returns the current mouse cursor shape.
pub fn getCursor() Cursor {
    return sokol.app.getMouseCursor();
}

/// Convenience function: captures the cursor for FPS-style controls.
/// Hides and locks the cursor in one call.
pub fn captureCursor(captured: bool) void {
    showCursor(!captured);
    lockCursor(captured);
}

// -----------------------------------------------------------------------------
// Clipboard Functions
// -----------------------------------------------------------------------------

/// Copies a string to the system clipboard.
pub fn setClipboard(text: [:0]const u8) void {
    sokol.app.setClipboardString(text);
}

/// Returns the current clipboard contents (empty string if unavailable).
pub fn getClipboard() [:0]const u8 {
    return sokol.app.getClipboardString();
}

// -----------------------------------------------------------------------------
// Application Lifecycle Functions
// -----------------------------------------------------------------------------

/// Requests the application to quit. This triggers the cleanup phase.
/// The quit can be cancelled by calling `cancelQuit()` in an event handler.
pub fn requestQuit() void {
    sokol.app.requestQuit();
}

/// Cancels a pending quit request (call from QUIT_REQUESTED event handler).
pub fn cancelQuit() void {
    sokol.app.cancelQuit();
}

/// Immediately terminates the application without cleanup.
/// Prefer `requestQuit()` for graceful shutdown.
pub fn quit() void {
    sokol.app.quit();
}

/// Returns the total number of frames rendered since app start.
pub fn frameCount() u64 {
    return sokol.app.frameCount();
}

/// Returns the duration of the last frame in seconds.
/// Note: For game logic, prefer using TimePlugin.Time.delta_time instead.
pub fn frameDuration() f64 {
    return sokol.app.frameDuration();
}

// -----------------------------------------------------------------------------
// Mobile/Virtual Keyboard Functions
// -----------------------------------------------------------------------------

/// Shows or hides the virtual keyboard (mobile platforms only).
pub fn showKeyboard(visible: bool) void {
    sokol.app.showKeyboard(visible);
}

/// Returns true if the virtual keyboard is currently shown.
pub fn isKeyboardVisible() bool {
    return sokol.app.keyboardShown();
}

// -----------------------------------------------------------------------------
// File Drop Functions
// -----------------------------------------------------------------------------

/// Returns the number of files dropped onto the window.
/// Only valid during/after a FILES_DROPPED event.
pub fn getDroppedFileCount() i32 {
    return sokol.app.getNumDroppedFiles();
}

/// Returns the path of a dropped file by index.
/// Only valid during/after a FILES_DROPPED event.
pub fn getDroppedFilePath(index: i32) [:0]const u8 {
    return sokol.app.getDroppedFilePath(index);
}

// =============================================================================
// END PLATFORM ABSTRACTION LAYER
// =============================================================================

fn containsType(comptime arr: anytype, comptime T: type, comptime n: usize) bool {
    return inline for (0..n) |i| {
        if (arr[i] == T) break true;
    } else false;
}

/// Creates a type tuple struct that holds type values for Sparze World.
/// Returns a struct type like `struct { comptime type = Position, comptime type = Velocity }`.
/// When instantiated with `.{}`, it creates the tuple value `.{ Position, Velocity }`.
fn TypeTupleType(comptime count: usize, comptime types: [count]type) type {
    var fields: [count]std.builtin.Type.StructField = undefined;
    inline for (0..count) |i| {
        fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = type,
            .default_value_ptr = @ptrCast(&types[i]),
            .is_comptime = true,
            .alignment = 0,
        };
    }
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

/// Helper to calculate max possible types from plugins for array sizing.
fn maxTypesFromPlugins(comptime plugins: anytype, comptime type_kind: []const u8) usize {
    var total: usize = 0;
    inline for (plugins) |P| {
        if (@hasDecl(P, type_kind)) {
            total += @field(P, type_kind).len;
        }
    }
    return total;
}

/// Collects and deduplicates types from plugins into a tuple.
/// Returns a tuple value like `.{ Position, Velocity }` for Sparze World.
fn collectPluginTypes(comptime plugins: anytype, comptime type_kind: []const u8) blk: {
    @setEvalBranchQuota(10000);
    const max_types = maxTypesFromPlugins(plugins, type_kind);

    // Collect and deduplicate types
    var tmp_list: [max_types]type = undefined;
    var count: usize = 0;
    for (plugins) |P| {
        if (@hasDecl(P, type_kind)) {
            for (@field(P, type_kind)) |T| {
                if (!containsType(tmp_list, T, count)) {
                    tmp_list[count] = T;
                    count += 1;
                }
            }
        }
    }

    // Build final array
    var types: [count]type = undefined;
    for (0..count) |i| {
        types[i] = tmp_list[i];
    }

    break :blk TypeTupleType(count, types);
} {
    return .{};
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

/// Build the `sparze.World` type for the full plugin set.
///
/// Ubiquitous language: **World construction**, **plugin declarations**, **type tuple values**.
/// The engine collects `Components`, `Resources`, `Events`, and `Groups` from plugins (when present),
/// deduplicates them, and passes the resulting tuple *values* into `sparze.World(...)`.
pub fn buildWorld(comptime plugins: anytype) type {
    @setEvalBranchQuota(25000);
    const Components = collectPluginTypes(plugins, "Components");
    const Resources = collectPluginTypes(plugins, "Resources");
    const Events = collectPluginTypes(plugins, "Events");
    const Groups = collectPluginTypes(plugins, "Groups");

    return sparze.World(Components, Resources, Events, Groups);
}

/// Options for `zenithor.run(...)`.
///
/// Ubiquitous language: **base allocator**, **AppState arena**, **WASM lifecycle**.
const ZenithorOptions = struct {
    /// Base allocator used to create the application's arena on native targets.
    ///
    /// On WASM targets, Zenithor uses `std.heap.c_allocator` regardless of this option.
    allocator: std.mem.Allocator = std.heap.page_allocator,
};

/// Entry point for Zenithor applications.
///
/// Ubiquitous language: **plugin dependency expansion**, **system scheduling**, **stages**.
///
/// Plugins are compile-time types (usually `struct`s). Zenithor will:
/// - Expand `pub const Requires = .{ ... }` dependencies (topological order, compile-time cycle check).
/// - Build the `World` from optional plugin declarations: `Components`, `Resources`, `Events`, `Groups`.
/// - Register systems from `pub const systems = .{ ... }` (startup/main/terminate).
///
/// Sokol events are automatically buffered in `SokolEventQueue` and processed by systems via `SokolEvents` parameter.
pub fn run(comptime user_plugins: anytype, options: ZenithorOptions) void {
    // Expand user plugins to include all dependencies (auto-include)
    const Expanded = expandPluginDependencies(user_plugins);

    // Combine expanded plugins with builtin plugin
    const allPlugins = .{BuiltinPlugin} ++ Expanded.plugins;

    const World = buildWorld(allPlugins);
    const SystemScheduler = system_module.SystemScheduler(World);

    const AppState = struct {
        const Self = @This();

        arena: std.heap.ArenaAllocator,
        allocator: std.mem.Allocator,
        world: World,
        system_scheduler: SystemScheduler,
        startup_system_scheduler: SystemScheduler,
        terminate_system_scheduler: SystemScheduler,

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

            // Initialize resources and register systems for each plugin
            inline for (allPlugins, 0..) |Plugin, plugin_idx| {
                const plugin_name = @typeName(Plugin);

                // Declarative system registration via pub const systems
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
                }
            }

            // Finalize system registration - sort by priority and apply constraints
            app_state.system_scheduler.finalize();
            app_state.startup_system_scheduler.finalize();
            app_state.terminate_system_scheduler.finalize();

            // All Sokol subsystems initialized by plugins:
            // - Graphics (gfx + gl) by renderer plugin
            // - Time by time_plugin
            // Core only manages app loop and plugin orchestration

            app_state.world.beginFrame();
            app_state.startup_system_scheduler.run(&app_state.world);
            app_state.world.endFrame() catch unreachable;
        }

        export fn appFrame(state: ?*anyopaque) callconv(.c) void {
            var app_state = @as(*AppState, @ptrCast(@alignCast(state)));
            app_state.world.beginFrame();
            app_state.world.getResourcePtrMut(BuiltinPlugin.SokolEventQueue).drainToFrame();
            app_state.system_scheduler.run(&app_state.world);
            app_state.world.endFrame() catch unreachable;
        }

        export fn appCleanup(state: ?*anyopaque) callconv(.c) void {
            var app_state = @as(*AppState, @ptrCast(@alignCast(state)));
            app_state.world.beginFrame();
            app_state.terminate_system_scheduler.run(&app_state.world);
            app_state.world.endFrame() catch unreachable;
            app_state.deinit();

            // Shutdown sokol modules
            // Graphics (gfx + gl) shutdown by renderer plugin
            // sokol.time does not require explicit shutdown
        }

        export fn appEvent(ev: [*c]const sokol.app.Event, state: ?*anyopaque) callconv(.c) void {
            var app_state = @as(*AppState, @ptrCast(@alignCast(state)));
            var queue = app_state.world.getResourcePtrMut(BuiltinPlugin.SokolEventQueue);
            queue.enqueue(ev.*);
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
