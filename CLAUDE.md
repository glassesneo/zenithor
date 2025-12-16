# Zenithor

Plugin-driven 2D/3D game engine for Zig using Sokol (graphics), Sparze (ECS), and Dear ImGui (UI).

## Quick Start

```bash
zig build test                  # Run tests
zig build minimal_app           # Build native example
zig build run-minimal_app       # Run native example

# WASM builds
zig build rendering_2d -Dtarget=wasm32-emscripten
zig build serve-examples -Dtarget=wasm32-emscripten

# With WASM filesystem support (for serialization)
zig build serve-examples -Dtarget=wasm32-emscripten -Dfilesystem

# Graphics backend options
zig build <target> -Dgl        # OpenGL (default)
zig build <target> -Dgles3     # OpenGL ES3
zig build <target> -Dwgpu      # WebGPU
```

**Available examples**: `minimal_app`, `input_movement`, `rendering_2d`, `scene_3d`, `system_ordering`, `error_handling`, `serialization`, `imgui_overlay`, `plugin_authoring`, `showcase_3d`

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
│       └── system.zig         # SystemScheduler
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
    zenithor.run(.{ Graphics, Time, Input }, .{});
}
```

Entry point must call `zenithor.run(plugins, .{})` with a plugin tuple and the options placeholder. BuiltinPlugin added automatically.

## Plugin Development

### Plugin Structure

```zig
// plugins/my_plugin/src/root.zig
const zenithor = @import("zenithor");
const Stage = zenithor.Stage;
const SystemConfig = zenithor.SystemConfig;
const sparze = @import("sparze");

pub const MyComponent = struct { value: f32 };
pub const MyResource = struct { state: u32 };
pub const MyEvent = struct { entity_id: u32 };

pub const Components = .{ MyComponent };
pub const Resources = .{ MyResource };
pub const Events = .{ MyEvent };

// Declarative system registration
pub const systems = .{
    .startup = &.{
        .{ .system = init, .stage = .first },
    },
    .main = &.{
        .{ .system = mySystem, .stage = .update },
        .{ .system = advancedSystem, .stage = .update, .config = .{ .priority = -10, .tags = &.{"my-tag"} } },
    },
    .terminate = &.{
        .{ .system = cleanup, .stage = .last },
    },
    .event_handlers = &.{handleEvent},
};

fn init(commands: anytype) !void {
    // Startup logic
    commands.setResource(MyResource, .{ .state = 0 });
}

fn mySystem(res: sparze.ResourceMut(MyResource)) !void {
    res.value.state += 1;
}

fn advancedSystem(res: sparze.Resource(MyResource)) !void {
    // System with priority and tags
}

fn cleanup() !void {
    // Cleanup logic
}

fn handleEvent(event: sokol.app.Event, world: anytype) !void {
    // Event handler - must take (event, world) signature
}
```

### Plugin Dependencies

Plugins can declare dependencies on other plugins using `pub const Requires`. The engine automatically includes all required plugins when you include the dependent plugin.

```zig
// Plugin that depends on Time, Input, and Graphics
const TimePlugin = @import("time_plugin");
const InputPlugin = @import("input_plugin");
const GraphicsPlugin = @import("graphics_plugin");

pub const Requires = .{ TimePlugin, InputPlugin, GraphicsPlugin };
```

**Features:**
- **Transitive dependencies**: If A requires B, and B requires C, all three are included
- **Diamond dependency handling**: If A and B both require C, C is included only once
- **Circular dependency detection**: Compile-time error with clear message
- **Topological ordering**: Dependencies are initialized before dependents

### build() Parameters (any order, all optional)
- `allocator: std.mem.Allocator`
- `world: anytype` - For `setResource()`

### System Stages (execution order)
1. `first` - Early setup
2. `pre_update`, `update`, `post_update` - Game logic
3. `pre_render`, `render`, `render_submit`, `post_render` - Rendering
4. `last` - Late cleanup
5. `post_process` - Post-frame

### System Ordering

Systems within a stage are executed in a deterministic order based on:
1. **Plugin dependencies** (implicit) - Systems from dependency plugins run before dependent plugins
2. **Priority** (optional) - Lower priority values run first (default: 0)
3. **Before/After constraints** (optional) - Explicit ordering via tags

**System configuration semantics (declarative `systems` blocks):**
- `.priority` (default `0`): lower values run first within a stage
- `.tags`: tag this system for constraint references
- `.after = &.{"tag"}`: run after all systems tagged with `tag`
- `.before = &.{"tag"}`: run before all systems tagged with `tag`
- Constraints are stage-scoped; circular constraints cause compile-time errors (Debug/ReleaseSafe)

**Ordering resolution:**
1. Systems sorted by priority within each stage (stable sort preserves declaration order for equal priorities)
2. Constraints applied via topological sort while preserving priority order
3. Plugin dependency ordering is implicit (dependencies registered first)

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

### System Return Types

System functions and event handlers support both `void` and `!void` return types:

```zig
// Use void when the system cannot fail
fn simpleSystem(res: Resource(MyResource)) void {
    // No error handling needed
}

// Use !void when the system may return errors
fn fallibleSystem(commands: anytype) !void {
    _ = try commands.createEntityWith(.{ MyComponent{} });
}

// Event handlers also support both return types
fn handleEvent(event: sokol.app.Event, world: anytype) void {
    // Handle event without errors
}
```

Prefer `void` when the system doesn't use `try` or return errors.

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
- **Groups** must be declared at compile-time in plugin's `pub const Groups` tuple; they are automatically included in the World type signature (4th parameter)
- **Tag components** are empty structs (`struct {}`) using TagStorage
- **Debug and ReleaseSafe builds** include defensive validations (overflow checks, constraint validation, assertions) that are removed in ReleaseFast/ReleaseSmall builds for performance (see [Debug vs Release Builds](src/core/CLAUDE.md#debug-vs-release-builds))

## Testing

```bash
zig build test              # Native tests
zig build test-wasm         # WASM tests (if supported)
```

CI runs tests and builds all examples (native + WASM/WebGPU) via `.github/workflows/`.
