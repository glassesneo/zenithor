# Core Engine

Application lifecycle, builtin components (Transform, Color), system scheduling, and error handling.

## Key Files

- **application.zig** - zenithor.run(), plugin expansion, World construction, Sokol init, main loop
- **builtin.zig** - Transform, Color components (always included)
- **system.zig** - SystemScheduler (registration, sorting, constraint validation)

## Critical Rules

**IMPORTANT**: Core owns the `sokol.app` loop and initializes `sokol.time` in `application.zig`. Graphics initialization (`sokol.gfx` and `sokol.gl`) is handled by the `render_context` plugin. Subsystem plugins may initialize their own modules (e.g. `imgui_plugin` initializes `sokol.imgui`).

**IMPORTANT**: World type constructed from tuple VALUES: `sparze.World(.{Components}, .{Resources}, .{Events}, .{Groups})`

**IMPORTANT**: Memory uses a single arena allocator per application. On native targets, pass a base allocator via `zenithor.run(..., .{ .allocator = ... })`. On WASM, Zenithor uses `std.heap.c_allocator` and heap-allocates `AppState` because `sokol.app.run()` returns immediately.

**IMPORTANT**: Default order is registration order (plugin expansion order + declaration order), then `SystemScheduler.finalize()` applies priority sort and before/after constraints. See @docs/SYSTEM_ORDERING.md

## Builtin Components

```zig
Transform { x: f32, y: f32, z: f32 }              // Always available
Color { r: f32, g: f32, b: f32, a: f32 = 1.0 }   // Always available
```

Color constants: `.red`, `.green`, `.blue`, `.yellow`, `.cyan`, `.magenta`, `.white`, `.black`, `.orange`, `.purple`

## Builtin Events

```zig
GameLoopError { err: anyerror }    // System errors (non-serializable)
EventLoopError { err: anyerror }   // Event handler errors (non-serializable)
```

Systems can return `!void` - errors are caught and enqueued as events. Application continues execution.

## System Stages (execution order)

1. `first` → 2. `pre_update` → 3. `update` → 4. `post_update` → 5. `pre_render` → 6. `render` → 7. `post_render` → 8. `last` → 9. `post_process`

## Debug vs Release Builds

**Debug/ReleaseSafe**: Constraint validation, overflow checks, circular dependency detection
**ReleaseFast/ReleaseSmall**: No overflow checks or constraint validation panics

## Documentation

- **@docs/APPLICATION_LIFECYCLE.md** - Detailed zenithor.run() flow, World construction, Sokol init
- **@docs/SYSTEM_ORDERING.md** - System execution order, priority, constraints, topological sort
- **@docs/PLUGIN_DEVELOPMENT.md** - Plugin structure, system registration patterns
