# Core Engine

Central engine components (application lifecycle, builtin types, system scheduling).

## Files

**application.zig** - Application entry point and plugin system
**builtin.zig** - Always-included components (Transform, Color)
**system.zig** - System scheduling and registration infrastructure

## Key Functions

**zenithor.run(plugins: anytype)**
- Entry point for all Zenithor applications
- Combines user plugins with BuiltinPlugin (Transform, Color)
- Builds World from deduplicated Components/Resources/Events
- Creates system schedulers (startup, main, terminate)
- Initializes Sokol modules (app, gfx, gl, time, audio)
- Runs main loop with frame timing

**buildWorld(plugins: anytype) type**
- Compile-time deduplication of Components, Resources, Events across all plugins
- Returns Sparze World type with merged declarations
- Validates plugin structure (`Components`, `Resources`, `Events`, `build()` function)

## Builtin Components

**Transform** `{ x: f32, y: f32, z: f32 }`
- Standard position component (included in all projects)

**Color** `{ r: f32, g: f32, b: f32, a: f32 = 1.0 }`
- Standard color component with predefined constants:
  - `Color.red`, `Color.green`, `Color.blue`, `Color.yellow`, `Color.cyan`, `Color.magenta`
  - `Color.white`, `Color.black`, `Color.orange`, `Color.purple`

## System Scheduling

**SystemRegistry** - Plugin API for registering systems
```zig
pub const SystemRegistry = struct {
    registerSystem(system_fn, stage: Stage)
    registerStartupSystem(system_fn, stage: Stage)
    registerTerminateSystem(system_fn, stage: Stage)
    registerEventHandler(handler_fn)
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

## Plugin Structure

```zig
// Minimal plugin
pub const Components = .{ MyComponent };
pub const Resources = .{ MyResource };
pub const Events = .{ MyEvent };

pub fn build(world: anytype, registry: SystemRegistry) !void {
    try world.setResource(MyResource, .{});
    registry.registerSystem(mySystem, .update);
}
```

**build() parameter injection** (any order, all optional):
- `allocator: std.mem.Allocator`
- `world: anytype` (for resource init, group creation)
- `registry: SystemRegistry` (for system registration)

## Sokol Initialization

**Centrally initialized** in application.zig:
- `sokol.app` - Windowing and main loop
- `sokol.gfx` - Graphics backend
- `sokol.gl` - Immediate mode GL (used by Graphics plugin)
- `sokol.time` - High-precision timing (used by Time plugin)
- `sokol.audio` - Audio subsystem

**Plugins must NOT call** `sokol.*.setup()` or `sokol.*.shutdown()`.

## Memory Management

- Arena allocator for entire application lifetime
- Uses `std.heap.c_allocator` on WASM/Emscripten
- Uses `std.heap.page_allocator` on native platforms
- Memory freed on application exit

## Debug vs Release Builds

The engine uses `builtin.mode == .Debug` to gate defensive checks that help catch bugs during development but are removed in release builds for performance.

**Debug-only validations** (skipped in release builds):
- **System registration overflow** (system.zig:26) - Panics if a stage exceeds `max_systems_per_stage` (1024)
- **Event handler overflow** (application.zig:173) - Panics if event handlers exceed `max_event_handlers` (32)
- **Graphics validation** (graphics plugin) - Panics if Circle.segments is 0 (division by zero)
- **Serialization assertions** (serialization plugin) - Asserts null-termination of save file paths

In release builds, these checks are omitted. Code continues execution without panicking, which may lead to undefined behavior if constraints are violated.

## Cross-Platform Notes

- WASM target: `wasm32-emscripten`
- Graphics backends: OpenGL (default), OpenGL ES3, WebGPU
- macOS requires CUPS headers (set via `CUPS_INCLUDE_DIR` in Nix shell)
