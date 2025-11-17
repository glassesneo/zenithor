# Zenithor

Plugin-driven 2D/3D game engine for Zig using Sokol (graphics), Sparze (ECS), and Dear ImGui (UI).

## Quick Start

```bash
zig build test                  # Run tests
zig build demo_window           # Build native example
zig build run-demo_window       # Run native example

# WASM builds
zig build demo_2d -Dtarget=wasm32-emscripten
zig build serve-examples -Dtarget=wasm32-emscripten

# With WASM filesystem support (for serialization)
zig build serve-examples -Dtarget=wasm32-emscripten -Dfilesystem

# Graphics backend options
zig build <target> -Dgl        # OpenGL (default)
zig build <target> -Dgles3     # OpenGL ES3
zig build <target> -Dwgpu      # WebGPU
```

**Available examples**: `demo_window`, `demo_2d`, `demo_imgui`, `demo_input`, `demo_time`, `demo_zindex`, `demo_circle`, `demo_resources`, `demo_events`

## Architecture

**Compile-time plugin system** - Plugins declare Components/Resources/Events and register systems. BuiltinPlugin (Transform, Color) always included.

**ECS via Sparze** - Compile-time type resolution, zero runtime lookup, cache-friendly storage. See [Sparze docs](https://github.com/glassesneo/sparze/blob/main/CLAUDE.md) for Query/Group/Event details.

**Sokol for I/O** - Cross-platform graphics, windowing, input, audio (initialized centrally in core).

## Directory Structure

```
zenithor/
├── src/
│   ├── root.zig           # Public API exports
│   └── core/              # Engine core (see src/core/CLAUDE.md)
│       ├── application.zig    # Main loop, plugin system, Sokol init
│       ├── builtin.zig        # Transform, Color (always included)
│       └── system.zig         # SystemScheduler, SystemRegistry
├── plugins/               # Standard plugins (see plugin CLAUDE.md files)
│   ├── graphics/          # 2D shapes (Point, Line, Triangle, Rectangle, Circle)
│   ├── time/              # Delta time, FPS tracking
│   ├── input/             # Mouse, Keyboard resources
│   ├── imgui/             # Dear ImGui integration
│   └── serialization/     # Save/load game state
├── examples/              # Example programs
├── build.zig              # Build system (creates plugin modules)
└── CLAUDE.md              # This file
```

## Documentation Index

### Core Engine
- **[Core Components](src/core/CLAUDE.md)** - Application lifecycle, builtin types, system scheduling

### Standard Plugins
- **[Graphics](plugins/graphics/CLAUDE.md)** - 2D shape rendering
- **[Time](plugins/time/CLAUDE.md)** - Frame timing and FPS
- **[Input](plugins/input/CLAUDE.md)** - Mouse and keyboard
- **[ImGui](plugins/imgui/CLAUDE.md)** - Debug UI and tools
- **[Serialization](plugins/serialization/CLAUDE.md)** - Save/load state

### External Dependencies
- **[Sparze](https://github.com/glassesneo/sparze/blob/main/CLAUDE.md)** - ECS framework (World, Query, Group, Events, Resources)

## Creating an Application

```zig
const zenithor = @import("zenithor");
const Graphics = @import("graphics_plugin");
const Time = @import("time_plugin");
const Input = @import("input_plugin");

pub fn main() void {
    zenithor.run(.{ Graphics, Time, Input });
}
```

Entry point must call `zenithor.run()` with plugin tuple. BuiltinPlugin added automatically.

## Plugin Development

### Plugin Structure

```zig
// plugins/my_plugin/src/root.zig
const zenithor = @import("zenithor");
const SystemRegistry = zenithor.SystemRegistry;
const sparze = @import("sparze");

pub const MyComponent = struct { value: f32 };
pub const MyResource = struct { state: u32 };
pub const MyEvent = struct { entity_id: u32 };

pub const Components = .{ MyComponent };
pub const Resources = .{ MyResource };
pub const Events = .{ MyEvent };

pub fn build(world: anytype, registry: SystemRegistry) !void {
    try world.setResource(MyResource, .{ .state = 0 });
    registry.registerSystem(mySystem, .update);
}

fn mySystem(res: sparze.Resource(MyResource)) !void {
    res.value.state += 1;
}
```

### build() Parameters (any order, all optional)
- `allocator: std.mem.Allocator`
- `world: anytype` - For `setResource()`, `createGroup()`
- `registry: SystemRegistry` - For system registration

### System Stages (execution order)
1. `first` - Early setup
2. `pre_update`, `update`, `post_update` - Game logic
3. `pre_render`, `render`, `render_submit`, `post_render` - Rendering
4. `last` - Late cleanup
5. `post_process` - Post-frame

### Sparze System Parameters
```zig
fn mySystem(
    query: Query(struct { Position, Velocity }),
    delta: Resource(DeltaTime),
    writer: EventWriter(CollisionEvent),
    commands: anytype,
) !void {
    // ... system logic
}
```

See [Sparze CLAUDE.md](https://github.com/glassesneo/sparze/blob/main/CLAUDE.md) for full parameter types and query filters.

## Build Configuration

**WASM filesystem** (required for serialization):
```bash
zig build <target> -Dtarget=wasm32-emscripten -Dfilesystem
```
Enables Emscripten IDBFS (~50KB binary increase).

**WASM stack size** (default 5MB):
```bash
zig build <target> -Dtarget=wasm32-emscripten -Dstack-size=8
```
Increase if stack overflow with large save files (range: 1-16MB).

**ImGui docking**:
```bash
zig build <target> -Dimgui-docking
```

## Development Environment

**Nix flake** provides reproducible dev shell:
```bash
nix develop  # Zig 0.15.1, ZLS, zon2nix, Deno
```

**macOS**: Nix shell sets `CUPS_INCLUDE_DIR` for Sokol (CUPS headers required).


## Constraints

- **Zig 0.15.1+** required
- **Plugins must NOT** call `sokol.*.setup()`/`shutdown()` (centrally initialized)
- **Groups** are full-owning, cannot overlap (validated at compile time)
- **Tag components** are empty structs (`struct {}`) using TagStorage
- **Debug builds** include defensive validations (overflow checks, assertions) that are removed in release builds for performance (see [Debug vs Release Builds](src/core/CLAUDE.md#debug-vs-release-builds))

## Testing

```bash
zig build test              # Native tests
zig build test-wasm         # WASM tests (if supported)
```

CI runs tests and builds all examples (native + WASM/WebGPU) via `.github/workflows/`.
