# CLAUDE.md

Guidance for working with the Zenithor repository (concise).

## What Zenithor Is

Zenithor is a Zig-based, plugin-driven game engine framework using Sokol for graphics/windowing, Sparze for ECS, and Dear ImGui for UI. It supports native and WebAssembly targets and exposes small example programs under `examples/`.

## Quick Build & Run

- Run tests: `zig build test`
- Build a native example: `zig build demo_window`
- Build a wasm example: `zig build demo_2d -Dtarget=wasm32-emscripten`
- Run a native example: `zig build run-demo_window`
- Serve wasm examples (dev server): `zig build serve-examples -Dtarget=wasm32-emscripten`
- Serve with filesystem support: `zig build serve-examples -Dtarget=wasm32-emscripten -Dfilesystem`
- Build library: `zig build`
- Install: `zig build install`

Examples include: `demo_window`, `demo_2d`, `demo_imgui`, `demo_input`, `demo_time`, `demo_zindex`, `demo_circle`, `demo_resources`, `demo_events`.

Graphics backend overrides:
- `-Dgl` (OpenGL), `-Dgles3` (OpenGL ES3), `-Dwgpu` (WebGPU), `-Dimgui-docking` (ImGui docking)

WASM filesystem support (required for serialization/save files):
- `-Dfilesystem` (enables Emscripten IDBFS, increases binary ~50KB, allows file I/O in browser)

WASM stack size configuration:
- `-Dstack-size=<MB>` (default: 5MB, range: 1-16MB, increase if experiencing stack overflow with large save files)

## iOS Builds (Experimental - Known Limitations)

**Current Status:** iOS build infrastructure is partially configured but **not fully functional** due to Zig 0.15.1 limitations.

**Prerequisites:**
- Install Xcode from the App Store (provides iOS SDK and frameworks)
- Run: `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`
- Restart your Nix shell after installation

**Build commands (currently broken):**
- iOS Simulator (Apple Silicon): `zig build demo_window -Dtarget=aarch64-ios-simulator`
- iOS Simulator (Intel Mac): `zig build demo_window -Dtarget=x86_64-ios-simulator`
- iOS Device (ARM64): `zig build demo_window -Dtarget=aarch64-ios`

**Known Issues:**
- **Blocker:** Zig 0.15.1's bundled libc++ has compatibility issues with iOS cross-compilation
- Error occurs during final executable linking when Zig's libc++ tries to compile for iOS target
- C libraries (cimgui, sokol) compile successfully, but linking fails with libc++ type errors

**What Works:**
- ✅ iOS SDK detection via `xcrun` and `DEVELOPER_DIR`
- ✅ C/C++ compilation with iOS system headers
- ✅ iOS framework discovery and linking configuration
- ✅ Automatic iOS vs simulator target detection

**Potential Solutions (not yet tested):**
- Upgrade to Zig 0.16.x or newer when available (may have improved iOS support)
- Use Xcode's native build system instead of Zig for iOS targets
- Investigate custom libc++ configuration or patches for iOS

**Notes:**
- iOS builds use system Xcode SDKs (not managed by Nix due to Apple licensing restrictions)
- macOS builds continue using Nix-managed SDK for reproducibility
- The Nix shell automatically detects and configures iOS SDK paths when Xcode is installed
- Metal backend is used by default for iOS (Sokol's default)
- Building for physical devices requires additional code signing configuration (not covered here)

## Web Dev & Debugging (WASM)

- Use `zig build serve-examples -Dtarget=wasm32-emscripten` to build and run the dev server (serves `zig-out/web`).
- Use the provided MCP chrome-devtools helpers for automated debugging (screenshots, console, network, evaluate scripts).
- Primary workflow: build+serve, navigate page, take screenshots, inspect console/network, iterate with hot reload.

## Plugin System

**Plugin Structure:**
```zig
pub const Components = .{ MyComponent };
pub const Resources = .{ DeltaTime, Score };
pub const Events = .{ CollisionEvent };
pub const Groups = &.{ MyGroup };

pub fn build(world: anytype, registry: SystemRegistry) !void {
    // Initialize resources
    try world.setResource(DeltaTime, .{ .dt = 0.016 });
    
    // Register systems
    registry.registerStartupSystem(initSystem, .first);
    registry.registerSystem(updateSystem, .update);
}
```

- Plugins are compile-time types that may declare `Components`, `Resources`, `Events`, `Groups` and must expose a `build()` function to register systems and initialize resources.
- `build()` may accept `allocator: std.mem.Allocator`, `world: anytype`, and/or `registry: SystemRegistry` in any order; the engine detects and supplies parameters at compile time.
- Builtin plugin (`src/core/builtin.zig`) is always included (provides `Transform`).
- Default plugins live under `plugins/*/src/root.zig` and must be registered by examples via `zenithor.run(.{ PluginA, PluginB })`.
- The main `build.zig` creates plugin modules and supplies imports (zenithor, sokol, sparze).

## World, Systems & Resources

**System Stages:**
- `first` (startup), `update` (main loop), `render` (drawing), `last` (cleanup)
- Startup systems run once, regular systems every frame, terminate systems on shutdown

**System Parameters (Query Filters):**
```zig
// Single component/tag iteration (fast)
fn movementSystem(query: SingleQuery(Position)) !void {
    for (query.components) |*pos| { /* ... */ }
}

// Multi-component query (flexible)
fn combatSystem(query: Query(struct { Position, Health })) !void {
    for (query.entities) |entity| {
        const pos = query.getComponent(entity, Position);
        const health = query.getComponentMut(entity, Health);
    }
}

// Optimized hot-path grouping
const MovementGroup = struct { Position, Velocity };
fn physicsSystem(movement: Group(MovementGroup)) !void {
    const positions = movement.getMutArrayOf(Position);
    const velocities = movement.getArrayOf(Velocity);
    for (positions, velocities) |*pos, vel| { /* ... */ }
}
```

**Resources Usage:**
```zig
fn systemWithResources(dt: zenithor.Resource(DeltaTime), score: zenithor.Resource(Score)) !void {
    const delta = dt.value.dt;        // Access via .value
    score.value.points += 100;         // Mutate via .value
}
```

- `buildWorld()` deduplicates `Components`, `Resources`, and `Events` from all plugins at compile time
- Resources are global singletons; initialize in `build()` with `world.setResource(...)`
- Groups require `world.createGroup()` and are most efficient for hot paths
- Query types: `SingleQuery`, `SingleTag`, `Query`, `TagQuery`, `Group` (fastest)

## Events (Brief)

- Events are frame-delayed: write with `EventWriter` in frame N, read with `EventReader` in frame N+1.
- Use event chains for multi-frame workflows (collision → damage → death).

## Development Workflow

**Create New Example:**
1. Add to `examples` array in `build.zig`
2. Create `examples/{name}.zig` with `main()` that calls `zenithor.run(.{ PluginA, PluginB })`

**Add New Plugin:**
1. Create `plugins/your_plugin/src/root.zig` and `build.zig.zon` (no zenithor dependency)
2. Define `Components`, `Resources`, `Events`, `Groups` tuples and `build()` function
3. Update `build.zig` to load plugin module and add imports
4. Export plugin in `src/root.zig`

**Common Plugin Example:**
```zig
// plugins/physics/src/root.zig
const Position = struct { x: f32, y: f32 };
const Velocity = struct { x: f32, y: f32 };

pub const Components = .{ Position, Velocity };

pub fn build(world: anytype, registry: SystemRegistry) !void {
    // Setup group for efficient physics queries
    try world.createGroup(struct { Position, Velocity });
    registry.registerSystem(physicsSystem, .update);
}

fn physicsSystem(movement: Group(struct { Position, Velocity })) !void {
    const positions = movement.getMutArrayOf(Position);
    const velocities = movement.getArrayOf(Velocity);
    for (positions, velocities) |*pos, vel| {
        pos.x += vel.x;
        pos.y += vel.y;
    }
}
```

- Unit tests use Zig's `test` blocks and run via `zig build test`
- All Sokol modules initialized centrally in `src/core/application.zig` — plugins must NOT call `sokol.*.setup()`

## Environment & CI

- Use the provided Nix flake (`flake.nix`) for a reproducible dev shell (`nix develop`) with Zig 0.15.1, ZLS, zon2nix and Deno.
- On macOS, CUPS headers are required for Sokol; the Nix shell sets `CUPS_INCLUDE_DIR`.
- CI (`.github/workflows/`) runs tests and builds native and wasm examples (including WebGPU).

## Key References & Constraints

- Minimum Zig version: 0.15.1
- Plugins must not call `sokol.*.setup()`/`shutdown()`; Sokol modules are initialized centrally in `src/core/application.zig`.
- Groups are full-owning and may not overlap (validated at compile time).
- Tag components are empty structs (`struct {}`) and use `TagStorage`.

For more detailed usage examples (systems, queries, events), see `examples/`.
