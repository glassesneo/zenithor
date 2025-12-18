# Core Engine

Central engine components (application lifecycle, builtin types, system scheduling).

## Files

**application.zig** - Application entry point and plugin system
**builtin.zig** - Always-included components (Transform, Color)
**system.zig** - System scheduling and registration infrastructure

## Key Functions

**zenithor.run(plugins: anytype)**
- Entry point for all Zenithor applications
- Expands plugin dependencies automatically via `expandPluginDependencies()`
- Combines user plugins with BuiltinPlugin (Transform, Color)
- Builds World from deduplicated Components/Resources/Events/Groups
- Passes tuple **values** (not `std.meta.Tuple` types) into `sparze.World`
- Creates system schedulers (startup, main, terminate)
- Introspects plugin declarations via `pub const systems`
- Initializes Sokol modules (app, gfx, gl, time, imgui)
- Runs main loop with frame timing

**buildWorld(plugins: anytype) type**
- Compile-time deduplication of Components, Resources, Events, Groups across all plugins
- Uses `collectPluginTypes()` to gather declarations into tuple **values** (e.g. `.{ Position, Velocity }`)
- Tuple values are built via `TypeTupleType`, a struct-of-comptime-types that materializes into a tuple when instantiated
- Returns Sparze World type built from those tuple values (signature: `sparze.World(.{ comps }, .{ resources }, .{ events }, .{ groups })`)

## World Construction

- **TypeTupleType**: creates a struct type with comptime type fields. Instantiating it (`.{}`) produces a tuple value like `.{ Position, Velocity }` that Sparze expects.
- **collectPluginTypes**: gathers and deduplicates plugin declarations (`Components`, `Resources`, `Events`, `Groups`), builds the TypeTupleType for the deduped list, and returns the tuple value.
- **World signature** (what `buildWorld` passes):
```zig
sparze.World(
    .{ Position, Velocity },              // Components (tuple of types)
    .{ DeltaTime },                       // Resources (tuple of types)
    .{},                                  // Events (tuple of types)
    .{ struct { Position, Velocity } },   // Groups (tuple of group structs)
);
```

## Builtin Components

**Transform** `{ x: f32, y: f32, z: f32 }`
- Standard position component (included in all projects)

**Color** `{ r: f32, g: f32, b: f32, a: f32 = 1.0 }`
- Standard color component with predefined constants:
  - `Color.red`, `Color.green`, `Color.blue`, `Color.yellow`, `Color.cyan`, `Color.magenta`
  - `Color.white`, `Color.black`, `Color.orange`, `Color.purple`

## Builtin Events

**GameLoopError** `{ err: anyerror }`
- Captures errors from systems during frame execution
- Automatically enqueued when any system returns an error
- Use `EventReader(GameLoopError)` to monitor and handle system failures
- Marked as non-serializable (`serialized = false`)

**EventLoopError** `{ err: anyerror }`
- Captures errors from event handlers (input, window events)
- Automatically enqueued when event handlers return errors
- Use `EventReader(EventLoopError)` to monitor and handle event failures
- Marked as non-serializable (`serialized = false`)

## Error Handling

Zenithor implements a graceful error handling system that allows systems and event handlers to fail without crashing the application.

**Design Philosophy**:
- Systems can return errors with `!void` signature
- Errors are caught and converted to events
- Application continues execution after failures
- Error monitoring is opt-in via event readers

**System Error Flow** (system.zig:369-381):
```zig
// Systems can fail
fn mySystem(res: Resource(MyResource)) !void {
    return error.SomethingWentWrong;
}

// SystemScheduler catches errors
scheduler.run(&world);  // Never throws

// Errors become events
var errors = EventReader(GameLoopError);
var iter = errors.iterator();
while (iter.next()) |err_event| {
    std.debug.print("System error: {any}\n", .{err_event.err});
}
```

**Event Handler Error Flow** (application.zig:287-312):
```zig
// Event handlers can fail
fn onMouseClick(mouse: Resource(Mouse)) !void {
    return error.HandlerFailed;
}

// Application catches errors automatically
// Errors queued as EventLoopError events
var errors = EventReader(EventLoopError);
```

**Error Recovery Pattern**:
```zig
fn errorMonitor(
    game_errors: EventReader(GameLoopError),
    event_errors: EventReader(EventLoopError),
    log: Resource(ErrorLog),
) !void {
    // Check game loop errors
    var game_iter = game_errors.iterator();
    while (game_iter.next()) |err| {
        log.value.record(err.err);
    }

    // Check event loop errors
    var event_iter = event_errors.iterator();
    while (event_iter.next()) |err| {
        log.value.record(err.err);
    }
}
```

**Fallback Behavior**:
- If error event allocation fails, error is printed to debug output (system.zig:375-377, application.zig:370)
- Debug builds print backend info on startup (application.zig:332-333)

**See Also**: `examples/error_handling.zig` for complete error handling demonstration

## System Scheduling

**Declarative System Registration** - Plugins declare systems via compile-time constants:
```zig
pub const systems = .{
    .startup = &.{
        .{ .system = init, .stage = .first },
    },
    .main = &.{
        .{ .system = update, .stage = .update },
        .{ .system = render, .stage = .render, .config = .{ .tags = &.{"rendering"}, .after = &.{"physics"} } },
    },
    .terminate = &.{
        .{ .system = cleanup, .stage = .first },
    },
    .event_handlers = &.{handleEvent},
};
```

**SystemConfig** - Optional configuration for system ordering
```zig
pub const SystemConfig = struct {
    priority: i16 = 0,                       // Lower values run first
    tags: []const []const u8 = &.{},         // Tags for this system
    before: []const []const u8 = &.{},       // Run before these tags
    after: []const []const u8 = &.{},        // Run after these tags
};
```

**Stages** (execution order)
1. `first` - Early frame setup (Time update, ImGui frame)
2. `pre_update` - Pre-game logic
3. `update` - Main game logic
4. `post_update` - Post-game logic
5. `pre_render` - Rendering preparation (GL setup, projection)
6. `render` - Drawing systems
7. `render_submit` - Pass submission (Graphics, ImGui render)
8. `post_render` - Pass finalization
9. `last` - Late frame cleanup (Input reset, frame count increment)
10. `post_process` - Post-frame processing

**System Types**
- **Startup systems**: Run once on initialization
- **Regular systems**: Run every frame in stage order
- **Terminate systems**: Run once on shutdown
- **Event handlers**: Process Sokol events (mouse, keyboard, window)

**System Ordering** (within each stage):
1. **Plugin dependency ordering** (implicit) - Plugins with `pub const Requires` dependencies registered in topological order
2. **Declarative introspection** - `application.zig:appInit()` discovers systems via `@hasDecl(Plugin, "systems")` and `@hasField()`
3. **Priority-based ordering** - Systems sorted by priority (ascending: -100 < 0 < 100) via stable sort
4. **Constraint resolution** - Before/after tags applied via topological sort that preserves priority order
5. **Finalization** - `finalize()` called on all schedulers before first frame

**Priority Override Behavior**:
- Priority is **global** across all plugins and can override plugin dependency ordering
- This allows flexibility when you need fine-grained control over system execution order
- Example: If PluginB depends on PluginA, but PluginB system has priority -50 and PluginA system has priority 0, PluginB runs first

**Implementation details** (system.zig):
- `registerDecl()` extracts system function, stage, and optional config from anonymous struct descriptors
- Builds complete `SystemConfig` from partial config fields (priority, tags, before, after)
- Creates wrapper that calls `world.runSystem(system_fn)` for parameter injection
- `SystemMetadata` stores function pointer, priority, plugin info (name, index), tags, and constraints
- `finalize()` validates constraints (missing tags, circular dependencies) and sorts systems
- Sorting uses stable topological sort (`std.sort.block`) that maintains registration order for equal priorities
- Validation runs in Debug and ReleaseSafe builds (compile-time panics for constraint violations)
- Zero runtime overhead after finalization (sorting happens once at init)

**Event Handler Registration** - Standardized signature `fn(event: sokol.app.Event, world: *World) !void`:
```zig
fn handleEvent(event: sokol.app.Event, world: anytype) !void {
    // Process Sokol event (mouse, keyboard, window)
    // World parameter allows event handlers to mutate game state
}

pub const systems = .{
    .event_handlers = &.{handleEvent},
};
```

Application wraps each handler with compile-time generated wrapper that converts `[*c]const sokol.app.Event` to `sokol.app.Event` and passes World pointer.

## Plugin Structure

```zig
// Complete plugin example with all features
const zenithor = @import("zenithor");
const Stage = zenithor.Stage;
const SystemConfig = zenithor.SystemConfig;

pub const MyComponent = struct { value: f32 };
pub const MyResource = struct { state: u32 };
pub const MyEvent = struct { entity_id: u32 };

pub const Components = .{MyComponent};
pub const Resources = .{MyResource};
pub const Events = .{MyEvent};

// Optional: Declare plugin dependencies
pub const Requires = .{SomeOtherPlugin};

// Declarative system registration
pub const systems = .{
    .startup = &.{
        .{ .system = init, .stage = .first },
    },
    .main = &.{
        .{ .system = update, .stage = .update },
        .{ .system = render, .stage = .render, .config = .{
            .priority = 10,
            .tags = &.{"rendering"},
            .after = &.{"physics"}
        } },
    },
    .terminate = &.{
        .{ .system = cleanup, .stage = .first },
    },
    .event_handlers = &.{handleEvent},
};

fn init() !void {
    //startup logic
    commands.setResource(MyResource, .{ .state = 0 });
}
fn update(res: zenithor.Resource(MyResource)) !void { /* frame logic */ }
fn render() !void { /* rendering */ }
fn cleanup() !void { /* shutdown */ }
fn handleEvent(event: sokol.app.Event, world: anytype) !void { /* event processing */ }
```

**System descriptor fields**:
- `system` (required) - System function reference
- `stage` (required) - Stage enum value (`.first`, `.update`, `.render`, etc.)
- `config` (optional) - Anonymous struct with any subset of SystemConfig fields

**Plugin declaration tuples** (all required, can be empty):
- `pub const Components = .{...}` - Component types
- `pub const Resources = .{...}` - Resource types  
- `pub const Events = .{...}` - Event types

**Plugin declarations** (all optional except Components/Resources/Events):
- `pub const Requires = .{...}` - Plugin dependencies (auto-included)
- `pub const systems = .{...}` - System declarations (startup, main, terminate, event_handlers)

## Sokol Initialization

**Centrally initialized** in application.zig:
- `sokol.app` - Windowing and main loop
- `sokol.gfx` - Graphics backend
- `sokol.gl` - Immediate mode GL (used by Graphics plugin)
- `sokol.time` - High-precision timing (used by Time plugin)
- `sokol.audio` - Audio subsystem

**Plugins must NOT call** `sokol.*.setup()` or `sokol.*.shutdown()`.

## Memory Management

- Single arena allocator per AppState (initialized in `AppState.init()`)
- Uses `std.heap.c_allocator` on WASM/Emscripten
- Uses configurable base allocator on native platforms (default: `std.heap.page_allocator`)
- Memory freed on application exit via `AppState.deinit()`
- **IMPORTANT**: Never nest arena allocators - pass base allocator to `AppState.init()`, which creates its own arena internally

## Debug vs Release Builds

The engine uses `builtin.mode == .Debug` to gate defensive checks that help catch bugs during development but are removed in release builds for performance.

**Debug-only validations** (skipped in release builds):
- **System registration overflow** (system.zig) - Panics if a stage exceeds `max_systems_per_stage` (1024)
- **Event handler overflow** (application.zig) - Panics if event handlers exceed `max_event_handlers` (32)
- **Graphics validation** (graphics plugin) - Panics if Circle.segments is 0 (division by zero)
- **Serialization assertions** (serialization plugin) - Asserts null-termination of save file paths

In release builds, these checks are omitted. Code continues execution without panicking, which may lead to undefined behavior if constraints are violated.

## Cross-Platform Notes

- WASM target: `wasm32-emscripten`
- Graphics backends: OpenGL (default), OpenGL ES3, WebGPU
- macOS requires CUPS headers (set via `CUPS_INCLUDE_DIR` in Nix shell)
