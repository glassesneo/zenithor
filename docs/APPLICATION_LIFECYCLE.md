# Application Lifecycle

Internal flow chart and detailed explanation of `zenithor.run()`.

## Overview

`zenithor.run(plugins, options)` is the entry point for all Zenithor applications. It:
1. Expands plugin dependencies into a complete dependency graph
2. Builds a Sparze World type from all plugin declarations
3. Creates and registers systems from plugins
4. Initializes core Sokol modules (gfx/gl/time)
5. Runs the main loop (startup → frames → terminate)
6. Handles cleanup on exit

## High-Level Flow

```
┌─────────────────────────────────────────────────┐
│ Application Entry Point                         │
│ pub fn main() void {                            │
│     zenithor.run(.{ MyPlugin }, .{});           │
│ }                                               │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│ Phase 1: Plugin Dependency Expansion            │
│ - Resolve transitive dependencies              │
│ - Detect circular dependencies                 │
│ - Topological sort for initialization order    │
│ - Add BuiltinPlugin automatically              │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│ Phase 2: World Construction                     │
│ - Collect Components/Resources/Events/Groups   │
│ - Deduplicate types across plugins             │
│ - Build World type signature                   │
│ - Initialize World instance                    │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│ Phase 3: System Registration                    │
│ - Create SystemSchedulers (startup/main/term)  │
│ - Introspect plugin `systems` declarations     │
│ - Register systems with stage/priority/config  │
│ - Register event handlers                      │
│ - Finalize schedulers (sort, validate)         │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│ Phase 4: Sokol Initialization                   │
│ - Initialize sokol.app (windowing, events)     │
│ - Initialize sokol.gfx (graphics backend)      │
│ - Initialize sokol.gl (immediate GL)           │
│ - Initialize sokol.time (high-precision timer) │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│ Phase 5: Main Loop                              │
│                                                 │
│ ┌─────────────────────────────────────────┐   │
│ │ Startup Phase (once)                    │   │
│ │ - Run startup systems (.first stage)    │   │
│ │ - Initialize resources                  │   │
│ │ - Spawn initial entities                │   │
│ └─────────────────────────────────────────┘   │
│                                                 │
│ ┌─────────────────────────────────────────┐   │
│ │ Frame Loop (until quit)                 │   │
│ │                                         │   │
│ │ For each frame:                         │   │
│ │   1. Process Sokol events               │   │
│ │      - Call event handlers              │   │
│ │      - Update input state               │   │
│ │                                         │   │
│ │   2. Run main systems (all stages)      │   │
│ │      - first → ... → last               │   │
│ │      - Catch errors → enqueue events    │   │
│ │                                         │   │
│ │   3. Commit render pass                 │   │
│ │      - Flush graphics buffers           │   │
│ │      - Present frame                    │   │
│ └─────────────────────────────────────────┘   │
│                                                 │
│ ┌─────────────────────────────────────────┐   │
│ │ Terminate Phase (once)                  │   │
│ │ - Run terminate systems                 │   │
│ │ - Save state if needed                  │   │
│ │ - Clean up resources                    │   │
│ └─────────────────────────────────────────┘   │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│ Phase 6: Cleanup                                │
│ - Shutdown Sokol modules                       │
│ - Deinitialize World                           │
│ - Free arena allocator                         │
└─────────────────────────────────────────────────┘
```

## Phase 1: Plugin Dependency Expansion

**Location**: `src/core/application.zig:expandPluginDependencies()`

### Process

1. **Collect Direct Dependencies**
   ```zig
   // User provides plugins
   zenithor.run(.{ MyGamePlugin }, .{});

   // Engine checks for `pub const Requires`
   MyGamePlugin.Requires = .{ TimePlugin };
   ```

2. **Transitive Expansion**
   ```zig
   // Recursively expand dependencies
   MyGamePlugin → TimePlugin
                 → (no further deps)

   // Result: { TimePlugin, MyGamePlugin }
   ```

3. **Add BuiltinPlugin**
   ```zig
   // Always included (Transform, Color, error events)
   Final: { BuiltinPlugin, TimePlugin, MyGamePlugin }
   ```

4. **Detect Circular Dependencies**
   ```zig
   // Compile-time error if:
   PluginA.Requires = .{PluginB};
   PluginB.Requires = .{PluginA};
   // → error: Circular dependency detected
   ```

5. **Topological Sort**
   ```zig
   // Order plugins for initialization
   // Dependencies before dependents
   Order: [BuiltinPlugin, TimePlugin, MyGamePlugin]
   ```

### Code Reference

`src/core/application.zig` (search for `expandPluginDependencies`)

## Phase 2: World Construction

**Location**: `src/core/application.zig:buildWorld()`

### Process

1. **Collect Plugin Declarations**
   ```zig
   // For each plugin, gather:
   TimePlugin.Components = .{};
   TimePlugin.Resources = .{ Time };
   TimePlugin.Events = .{};
   TimePlugin.Groups = .{};

   MyGamePlugin.Components = .{ Circle, Rectangle };
   MyGamePlugin.Resources = .{ RenderingOptions };
   MyGamePlugin.Events = .{};
   MyGamePlugin.Groups = .{};
   ```

2. **Deduplicate Types**
   ```zig
   // If multiple plugins export the same type, include once
   All Components: { Transform, Color, Circle, Rectangle }
   All Resources: { Time, RenderingOptions }
   All Events: { GameLoopError, EventLoopError }
   All Groups: {}
   ```

3. **Build TypeTupleType**
   ```zig
   // Create a tuple type whose fields are named "0", "1", "2", ...
   const ComponentsTuple = TypeTupleType(4, .{ Transform, Color, Circle, Rectangle });

   // Instantiate to get the tuple VALUE expected by Sparze:
   const components_tuple: ComponentsTuple = .{}; // evaluates to `.{ Transform, Color, Circle, Rectangle }`
   ```

4. **Construct World Type**
   ```zig
   // Pass tuple VALUES to Sparze
   const World = sparze.World(
       .{ Transform, Color, Circle, Rectangle },  // Components
       .{ Time, RenderingOptions },               // Resources
       .{ GameLoopError, EventLoopError },        // Events
       .{},                                       // Groups
   );
   ```

5. **Initialize World Instance**
   ```zig
   var world = World.init(allocator);
   ```

### Key Implementation Detail: TypeTupleType

The `TypeTupleType` pattern converts a comptime list of types into a *tuple value* suitable for `sparze.World(...)`.

```zig
const std = @import("std");

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

const TupleType = TypeTupleType(2, .{ Position, Velocity });
const tuple_value: TupleType = .{}; // evaluates to `.{ Position, Velocity }`
```

This is necessary because Sparze expects tuple **values** (`.{ T1, T2 }`), not `std.meta.Tuple` types.

### Code Reference

`src/core/application.zig` (search for `TypeTupleType`)

## Phase 3: System Registration

**Location**: `src/core/application.zig:appInit()`

### Process

1. **Create SystemSchedulers**
   ```zig
   const SystemScheduler = system_module.SystemScheduler(World);
   var startup_scheduler = SystemScheduler.init();
   var main_scheduler = SystemScheduler.init();
   var terminate_scheduler = SystemScheduler.init();
   ```

2. **Introspect Plugin Systems**
   ```zig
   // For each plugin, check for `pub const systems`
   if (@hasDecl(Plugin, "systems")) {
       const systems_decl = Plugin.systems;

       if (@hasField(@TypeOf(systems_decl), "startup")) {
           inline for (systems_decl.startup) |decl| {
               startup_scheduler.registerDecl(decl, plugin_name, plugin_index);
           }
       }

       if (@hasField(@TypeOf(systems_decl), "main")) {
           inline for (systems_decl.main) |decl| {
               main_scheduler.registerDecl(decl, plugin_name, plugin_index);
           }
       }

       if (@hasField(@TypeOf(systems_decl), "terminate")) {
           inline for (systems_decl.terminate) |decl| {
               terminate_scheduler.registerDecl(decl, plugin_name, plugin_index);
           }
       }
   }
   ```

3. **Register Event Handlers**
   ```zig
   // Standard plugin event handler signature:
   //   fn(event: sokol.app.Event, world: anytype) void|!void
   if (@hasField(@TypeOf(systems_decl), "event_handlers")) {
       inline for (systems_decl.event_handlers) |handler_fn| {
           event_handlers[handler_count] = WrapperFor(handler_fn);
           handler_count += 1;
       }
   }
   ```

4. **Finalize Schedulers**
   ```zig
   startup_scheduler.finalize();
   main_scheduler.finalize();
   terminate_scheduler.finalize();
   ```

   Finalization:
   - Sorts systems by priority (stable sort)
   - Applies before/after constraints (topological sort)
   - Validates constraint tags (Debug/ReleaseSafe only)
   - Detects circular dependencies (Debug/ReleaseSafe only)

### Code Reference

`src/core/application.zig` (search for `appInit`)
`src/core/system.zig` (search for `finalize`)

## Phase 4: Sokol Initialization

**Location**: `src/core/application.zig:appInit()`

### Process

Sokol modules are initialized in `sokol.app.run()` callback:

```zig
fn appInit(state: ?*anyopaque) callconv(.c) void {
    // ... World and scheduler setup ...

    // Initialize core Sokol modules
    sokol.gfx.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });

    sokol.gl.setup(.{
        .logger = .{ .func = sokol.log.func },
    });

    sokol.time.setup();

    // Debug info
    if (builtin.mode == .Debug) {
        const backend = sokol.gfx.queryBackend();
        std.debug.print("[Zenithor] Graphics backend: {}\n", .{backend});
    }

    // Run startup systems
    world.beginFrame();
    startup_scheduler.run(&world);
    world.endFrame() catch unreachable;
}
```

**Critical**: `sokol.gfx`, `sokol.gl`, and `sokol.time` are initialized centrally. Other subsystems may be initialized by plugins (e.g. `imgui_plugin` initializes `sokol.imgui`).

### Code Reference

`src/core/application.zig` (search for `sokol.gfx.setup` / `sokol.time.setup`)

## Phase 5: Main Loop

### Startup Phase

**Location**: `src/core/application.zig:appInit()`

```zig
// Run once after initialization
startup_scheduler.run(&world);
```

Systems in startup schedulers:
- Initialize resources (e.g., `commands.setResource(Time, .{})`)
- Spawn initial entities
- Load saved game state
- Set up initial scene

### Frame Loop

**Location**: `src/core/application.zig:appFrame()`

Each frame:

1. **Event Processing**
   ```zig
   fn appEvent(ev: [*c]const sokol.app.Event, state: ?*anyopaque) callconv(.c) void {
       const app_state = @as(*AppState, @ptrCast(@alignCast(state)));
       for (0..app_state.event_handler_count) |i| {
           app_state.event_handlers[i](ev, &app_state.world) catch |err| {
               var queue = app_state.world.getEventStoragePtrMut(BuiltinPlugin.EventLoopError);
               queue.enqueue(.{ .err = err }) catch {};
           };
       }
   }
   ```

2. **System Execution**
   ```zig
   fn appFrame(state: ?*anyopaque) callconv(.c) void {
       const app_state = @as(*AppState, @ptrCast(@alignCast(state)));
       app_state.world.beginFrame();
       app_state.system_scheduler.run(&app_state.world);
       app_state.world.endFrame() catch unreachable;
   }
   ```

   Systems run in stage order (see docs/SYSTEM_ORDERING.md):
   ```
   .first → .pre_update → .update → .post_update →
   .pre_render → .render → .render_submit → .post_render →
   .last → .post_process
   ```

3. **Error Handling**
   ```zig
   // In SystemScheduler.run()
   system_fn(world) catch |err| {
       var queue = world.getEventStoragePtrMut(BuiltinPlugin.GameLoopError);
       queue.enqueue(.{ .err = err }) catch {};
   };
   ```

### Terminate Phase

**Location**: `src/core/application.zig:appCleanup()`

```zig
fn appCleanup(state: ?*anyopaque) callconv(.c) void {
    const app_state = @as(*AppState, @ptrCast(@alignCast(state)));
    app_state.world.beginFrame();
    app_state.terminate_system_scheduler.run(&app_state.world);
    app_state.world.endFrame() catch unreachable;
    app_state.deinit();

    // Shutdown core Sokol modules in reverse order.
    // Note: sokol.time does not require explicit shutdown.
    sokol.gl.shutdown();
    sokol.gfx.shutdown();
}
```

Terminate systems:
- Save game state
- Clean up resources
- Log final statistics
- Write crash dumps

### Code Reference

`src/core/application.zig` (search for `appCleanup`)

## Phase 6: Cleanup

**Location**: `src/core/application.zig:AppState.deinit()`

```zig
fn deinit(self: *AppState) void {
    self.world.deinit();
    self.arena.deinit();
}
```

Cleanup order:
1. **World.deinit()** - Frees entity storage, components, resources
2. **Arena.deinit()** - Frees entire arena allocator (includes schedulers, metadata)

### Code Reference

`src/core/application.zig` (search for `fn deinit`)

## Memory Management

### Allocator Hierarchy

```
┌─────────────────────────────────────────────┐
│ Base Allocator                              │
│ - std.heap.page_allocator (native)          │
│ - std.heap.c_allocator (WASM)               │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│ Arena Allocator (AppState)                  │
│ - Single allocation pool                    │
│ - Freed on exit                             │
└─────────────────┬───────────────────────────┘
                  │
                  ├─► World
                  ├─► System Schedulers
                  ├─► Event Handlers
                  └─► Plugin metadata
```

**IMPORTANT**: Avoid nesting arena allocators. On native targets, pass a base allocator via `zenithor.run(..., .{ .allocator = your_allocator })` and Zenithor will create a single arena for the application's lifetime. On WASM, Zenithor uses `std.heap.c_allocator`.

### Code Reference

`src/core/application.zig` (search for `initArena` / `finishInit`)

## Lifecycle Hooks

Plugins can hook into specific lifecycle points:

| Hook | When | Purpose | Example |
|------|------|---------|---------|
| `startup` | After Sokol init, before first frame | Initialize resources, spawn entities | Load save file |
| `main.first` | Start of each frame | Early frame setup | Update delta time |
| `main.last` | End of each frame | Late frame cleanup | Reset input state |
| `terminate` | Before Sokol shutdown | Clean up, save state | Write save file |
| `event_handlers` | On Sokol events (async) | Process input, window events | Handle mouse clicks |

## Error Propagation

```
System Error
     │
     ├─ Caught by SystemScheduler.run()
     │
     ├─ Enqueued as GameLoopError event
     │
     ├─ Application continues
     │
     └─ User systems can read GameLoopError events
        └─ Implement error recovery, logging, etc.


Event Handler Error
     │
     ├─ Caught by appEvent()
     │
     ├─ Enqueued as EventLoopError event
     │
     ├─ Application continues
     │
     └─ User systems can read EventLoopError events
```

Fallback: If event allocation fails, error is printed to debug output.

### Code Reference

`src/core/application.zig` (search for `EventLoopError`)
`src/core/system.zig` (search for `GameLoopError`)

## Debug vs Release Builds

**Debug and ReleaseSafe**:
- System registration overflow checks
- Event handler overflow checks
- Constraint validation (missing tags, circular dependencies)
- Backend info printed on startup

**ReleaseFast and ReleaseSmall**:
- No overflow checks or constraint validation panics
- No debug output
- Maximum performance

### Code Reference

src/core/CLAUDE.md:Debug vs Release Builds

## Execution Timeline Example

```
T=0ms    | appInit()
         |   ├─ Expand plugins: { MyPlugin, TimePlugin, BuiltinPlugin }
         |   ├─ Build World with all Components/Resources/Events
         |   ├─ Register systems from all plugins
         |   ├─ Finalize schedulers (sort, validate)
         |   ├─ Initialize Sokol modules
         |   └─ Run startup systems
         |       └─ MyPlugin.init() spawns entities
         |
T=16ms   | Frame 1: appFrame()
         |   ├─ Event processing (appEvent callbacks)
         |   ├─ Run main systems:
         |   │   ├─ .first: TimePlugin.updateTime()
         |   │   ├─ .update: MyPlugin.updateGame()
         |   │   └─ .render: MyRenderPlugin.renderShapes()
         |   └─ .render_submit: a render plugin commits the frame (e.g. via `sokol.gfx.commit()`)
         |
T=32ms   | Frame 2: appFrame()
         |   ├─ ... (repeat)
         |
...
         |
T=5000ms | User closes window
         |
         | appCleanup()
         |   ├─ Run terminate systems
         |   │   └─ MyPlugin.saveState()
         |   ├─ Shutdown Sokol modules
         |   └─ AppState.deinit()
         |       ├─ World.deinit()
         |       └─ Arena.deinit()
```

## See Also

- docs/PLUGIN_DEVELOPMENT.md - Plugin structure and systems
- docs/SYSTEM_ORDERING.md - System execution order
- src/core/application.zig - Full implementation
- src/core/system.zig - SystemScheduler implementation
- [Sparze Documentation](https://github.com/glassesneo/sparze/blob/main/CLAUDE.md) - World, Query, Events
