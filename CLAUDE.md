# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Zenithor is a Zig game engine framework built on a plugin-based Entity Component System (ECS) architecture. It uses Sokol for graphics/windowing, Sparze for ECS functionality, and Dear ImGui for UI. The project supports both native and WebAssembly compilation targets.

## Build System

### Common Build Commands

```bash
# Run unit tests
zig build test

# Build all native examples
zig build examples-native

# Build all web examples (wasm32-emscripten target)
zig build examples-web -Dtarget=wasm32-emscripten

# Build and run specific example (native)
zig build run-window
zig build run-2d_shapes
zig build run-imgui_demo

# Build and run specific example (web with hot reload)
zig build run-window -Dtarget=wasm32-emscripten
zig build run-2d_shapes -Dtarget=wasm32-emscripten

# Build library
zig build

# Install library artifact
zig build install
```

### Graphics Backend Options

By default, the build uses the platform-specific backend. Override with:

```bash
# Use OpenGL backend
zig build -Dgl

# Use OpenGL ES3 backend
zig build -Dgles3

# Use WebGPU backend (for wasm target)
zig build -Dwgpu -Dtarget=wasm32-emscripten

# Enable ImGui docking support
zig build -Dimgui-docking
```

### Web Development Server

The `server.ts` file provides a Deno-based development server with hot reload functionality for web builds. It:
- Serves files from `./zig-out/web` (or custom path via first argument)
- Watches for HTML and WASM file changes
- Automatically injects hot-reload WebSocket client into HTML
- Broadcasts reload notifications to connected clients

## Architecture

### Plugin System

Zenithor uses a compile-time plugin architecture. A **plugin** is a type that defines:

1. **Components** (required) - Tuple declaration of component types for the ECS
2. **build() function** (required) - Registers systems with the SystemRegistry
3. **Groups** (optional) - Tuple declaration for entity groupings in the ECS

Example plugin structure:
```zig
pub const Components = .{ MyComponent };
pub const Groups = &.{ MyGroup };

// Option 1: Without allocator parameter
pub fn build(registry: SystemRegistry) !void {
    registry.registerStartupSystem(initSystem, .first);
    registry.registerSystem(updateSystem, .update);
    registry.registerTerminateSystem(cleanupSystem, .last);
}

// Option 2: With allocator parameter (optional, order-independent)
pub fn build(allocator: std.mem.Allocator, registry: SystemRegistry) !void {
    // Allocator is the World's allocator, useful for plugin initialization
    registry.registerStartupSystem(initSystem, .first);
    registry.registerSystem(updateSystem, .update);
    registry.registerTerminateSystem(cleanupSystem, .last);
}

// Option 3: Parameters in any order
pub fn build(registry: SystemRegistry, allocator: std.mem.Allocator) !void {
    // Parameter order doesn't matter - engine detects types at compile time
    registry.registerStartupSystem(initSystem, .first);
    registry.registerSystem(updateSystem, .update);
    registry.registerTerminateSystem(cleanupSystem, .last);
}
```

**Note**: The `build()` function can optionally accept an `allocator` parameter. The engine automatically detects parameter types at compile time and constructs the appropriate argument tuple, so parameter order doesn't matter.

### Plugin Categories

**Builtin Plugin** (`src/core/builtin.zig`):
- Automatically loaded by the engine without user configuration
- Provides the Transform component used across the engine
- Always included in the World type

**Default Plugins** (`src/plugins/*`):
- Must be explicitly registered by users in `zenithor.run(.{ Plugin })` to access their features
- **GraphicsPlugin** (`src/plugins/graphics/root.zig`) - 2D shape rendering (Point, Line, Triangle, Rectangle)
- **ImGuiPlugin** (`src/plugins/imgui/root.zig`) - Dear ImGui integration with Window component
- **DebugPlugin** (`src/plugins/debug/root.zig`) - Runtime debugging tools with entity tracking, gizmos, and performance monitoring

### World Building

The `buildWorld()` function in `src/core/application.zig` performs compile-time component deduplication across all plugins. This ensures each component type appears exactly once in the final World type, regardless of how many plugins declare it.

### System Scheduling

Systems execute in a fixed stage order defined in `src/core/system.zig`:

1. `first` - Initialization tasks
2. `pre_update` - Pre-frame logic
3. `update` - Main game logic
4. `post_update` - Post-frame logic
5. `pre_render` - Render setup (e.g., camera, projection)
6. `render` - Drawing operations
7. `render_submit` - Submit rendering commands
8. `post_render` - Cleanup after rendering
9. `last` - Final frame tasks
10. `post_process` - Post-processing effects

Three system types are available:
- **Startup systems** - Run once during initialization
- **Regular systems** - Run every frame
- **Terminate systems** - Run once during shutdown

### Entry Point Flow

The `run()` function in `src/core/application.zig`:

1. Combines Builtin Plugin with user-provided Default Plugins
2. Builds deduplicated World type from all plugin components at compile time
3. Creates SystemScheduler instances for startup/regular/terminate systems
4. Registers Sokol callbacks (init, frame, cleanup, event)
5. Calls each plugin's `build()` function to register systems
6. Initializes Sokol (gfx, gl, imgui)
7. Runs the application main loop

Note: The ECS World loads component types from all `Components` tuples and executes all `build()` functions at compile time.

## Development Workflows

### Creating a New Example

1. Add example definition to `examples` array in `build.zig`
2. Create `examples/{name}.zig` with a `main()` function
3. Call `zenithor.run(.{ PluginA, PluginB })` with desired plugins
4. Build automatically generates individual and aggregate build steps

### Adding a New Plugin

1. Create plugin file (e.g., `src/plugins/my_plugin/root.zig`)
2. Define `Components` tuple with component types
3. Optionally define `Groups` array for entity groupings
4. Implement `build()` function to register systems:
   - Without allocator: `build(registry: SystemRegistry) !void`
   - With allocator: `build(allocator: std.mem.Allocator, registry: SystemRegistry) !void`
   - Parameters can be in any order - the engine detects types at compile time
5. Add plugin to `src/root.zig` exports
6. Include plugin in example/application via `zenithor.run(.{ MyPlugin })`

### Testing

Unit tests are co-located with source files using Zig's `test` blocks. The build system automatically discovers and runs all tests:

```bash
zig build test
```

## Environment Configuration

### Nix Development Shell

The `flake.nix` provides a reproducible development environment with:
- Zig 0.15.1 (via zig-overlay)
- ZLS 0.15.0 (Zig Language Server)
- zon2nix (for dependency management)
- Deno (for web development server)

### macOS-Specific Requirements

On macOS, the build requires CUPS headers for Sokol. The Nix shell sets `CUPS_INCLUDE_DIR` environment variable, which `build.zig` uses to add the include path to sokol_clib.

```bash
# The flake.nix handles this automatically
nix develop
```

### CI Configuration

GitHub Actions CI (`.github/workflows/zig-ci.yml`):
- Runs on Ubuntu with manual Zig installation
- Installs Mesa and X11 development libraries
- Executes tests, builds native examples, and builds wasm examples
- Tests both default backend and WebGPU backend for wasm

## Dependencies

Managed via `build.zig.zon`:

- **sokol-zig** - Cross-platform graphics/windowing library
- **sparze** - Entity Component System framework
- **dcimgui** - Dear ImGui C bindings with docking support

Sokol transitively depends on emsdk for WebAssembly compilation.

## Sparze ECS Integration

Zenithor uses Sparze as its underlying ECS framework. Understanding Sparze's architecture is essential for writing systems and plugins.

### Core ECS Concepts

**Entity** (`sparze.Entity`):
- 32-bit identifier: 16 bits for index, 16 bits for version
- Version-based recycling prevents stale references
- Managed by internal EntityRegistry with implicit free list

**Component Storage**:
- **SparseSet**: Default storage for regular components
  - Paginated sparse array (4096 entities per page) for O(1) entity→component lookup
  - Packed dense arrays for cache-friendly iteration
  - Group support: entities in groups stored at beginning of packed array
- **TagStorage**: Specialized storage for tag components (empty structs)
  - Uses DynamicBitSet for O(1) presence checking
  - Only 1 bit per entity index (memory-efficient)
  - Automatically used for `struct {}` components

**Tag Components**:
Tag components are zero-sized marker components used for entity categorization or state flags. They are defined as empty structs and automatically use optimized `TagStorage`.

```zig
// Define tag components as empty structs
const Player = struct {};
const Enemy = struct {};
const Active = struct {};

// Use tag-specific methods
try world.addTag(entity, Player);
if (world.hasComponent(entity, Player)) { /* ... */ }
world.removeTag(entity, Active);

// Systems with tag filters
fn playerSystem(query: SingleTag(Player)) !void {
    for (query.entities) |entity| {
        // Process all player entities
    }
}

fn bossEnemySystem(query: TagQuery(struct { Enemy, Boss })) !void {
    for (query.entities) |entity| {
        if (query.hasAllTags(entity)) {
            // Process entities that are both enemies and bosses
        }
    }
}
```

**Tag Component Usage**:
- **Marker components**: `Player`, `Enemy`, `NPC` - entity categorization
- **State flags**: `Active`, `Disabled`, `Selected` - entity state tracking
- **Group membership**: `UI`, `Renderable`, `Collidable` - system filtering
- **Events**: `Damaged`, `Died`, `LeveledUp` - single-frame event markers

### Query Filters and System Parameters

Systems receive query filters as parameters. These filters determine which entities the system operates on:

| Filter Type | Component Types | Count | Setup Required | Performance | Use Case |
|-------------|----------------|-------|----------------|-------------|----------|
| `SingleQuery(C)` | Regular | 1 | None | O(n) - Fast | Single component iteration |
| `SingleTag(T)` | Tag | 1 | None | O(n) - Fast | Single tag iteration |
| `Query(struct { A, B, ... })` | Mixed | 2+ | None | O(n) - Moderate | Ad-hoc multi-query (tags + components) |
| `TagQuery(struct { A, B, ... })` | Tag only | 2+ | None | O(n) - Moderate | Ad-hoc multi-tag queries |
| `Group(struct { A, B })` | Regular | 2+ | `createGroup()` required | O(n) - Fastest | Hot-path multi-component queries |

**When to use each**:
- **SingleQuery**: Iterating over entities with one regular component
- **SingleTag**: Iterating over entities with one tag component
- **Query**: Multi-component queries used occasionally or with varying component combinations (can mix tags and regular components)
- **TagQuery**: Multi-tag queries (tag components only, explicit type safety)
- **Group**: Hot-path multi-component queries (e.g., movement, rendering) where performance is critical

**Key differences**:
- **SingleQuery** and **SingleTag**: Direct iteration over packed arrays (SingleQuery) or bit sets (SingleTag)
- **Query** and **TagQuery**: Perform runtime intersection, iterating smallest set and checking for others
- **Query** works with mixed tags and regular components; **TagQuery** enforces tag-only at compile time
- **Group** has pre-organized memory layout with entities stored at start of all component arrays
- **Group** requires upfront `createGroup()` call and validation; **Query** and **TagQuery** have no setup overhead

### Writing Systems

Systems are plain functions that accept query filter parameters:

```zig
// Declare group type constants for readability
const MovementGroup = struct { Position, Velocity };
const CombatGroup = struct { Health, Armor };

// System with Group (optimized, requires createGroup)
fn movementSystem(movement: Group(MovementGroup)) !void {
    const positions = movement.getMutArrayOf(Position);
    const velocities = movement.getArrayOf(Velocity);
    for (positions, velocities) |*pos, vel| {
        pos.x += vel.x;
        pos.y += vel.y;
    }
}

// System with Query (flexible, no group setup required)
fn combatSystem(query: Query(struct { Position, Health })) !void {
    for (query.entities) |entity| {
        if (query.hasAllComponents(entity)) {
            const pos = query.getComponent(entity, Position).?;
            if (query.getComponentMut(entity, Health)) |health| {
                // Process entity
            }
        }
    }
}

// System with multiple query filters
fn complexSystem(
    movement: Group(MovementGroup),
    health: SingleQuery(Health),
    combat: Query(struct { Position, Armor }),
) !void {
    // Use multiple query filters in one system
}

// System with tag filters
fn playerSystem(query: SingleTag(Player)) !void {
    for (query.entities) |entity| {
        // Process all player entities
    }
}
```

**Group Validation**:
Groups must be validated at compile time to ensure no overlapping components:

```zig
// In plugin build() function
World.validateGroups(.{
    MovementGroup,
    CombatGroup,
});

try world.createGroup(MovementGroup);
try world.createGroup(CombatGroup);
```

**System Best Practices**:
1. **Declare group type constants** for readability and maintainability
2. **Define systems as plain functions** that accept query filter parameters
3. **Use Groups for hot-path queries** (e.g., movement, rendering)
4. **Use Query/TagQuery for occasional queries** with varying component combinations
5. **Validate all groups upfront** for compile-time safety

### Performance Optimizations

**SparseSet Optimizations**:
- Bit-shift indexing: `sparse_index >> 12` for page, `sparse_index & 0xFFF` for slot
- Direct `swapRemove()` on arrays to reduce memory copies
- ~20% faster component lookups, ~17% faster removes

**Reserve API**:
Pre-allocate capacity to avoid reallocations during bulk inserts:
```zig
try world.getSparseSetPtr(Position).reserve(expected_capacity);
```

**Command Buffer Optimizations**:
- Commands use inline array `[max_component_size]u8` instead of heap allocation
- Eliminates `allocator.dupe()` call per command
- 77.8x faster command buffer operations (98.7% speedup)

### Memory Management

- **Component pools**: Owned by World and deinitialized automatically
- **Command buffer**: Uses inline storage (no per-command allocation)
- **Tag storage**: Uses bit sets (1 bit per entity) for minimal memory overhead
- **Entity versioning**: Always use entity handles returned by create/destroy operations

### Integration with Zenithor

Zenithor's `buildWorld()` function (`src/core/application.zig`) creates the ECS World by:
1. Collecting all `Components` tuples from plugins
2. Performing compile-time component deduplication
3. Creating the World type: `World(struct { Component1, Component2, ... })`

Plugin `Groups` declarations are used to:
1. Validate groups at compile time
2. Create groups during initialization
3. Enable optimized group-based queries in systems

## Application Configuration

### Window Settings

Default window size is configured in `src/core/application.zig`:
```zig
.width = 1280,
.height = 800,
```

This provides sufficient space for debug UI windows and game content without overlapping.

### Debug Plugin

The Debug plugin (`src/plugins/debug/root.zig`) provides comprehensive debugging tools:

**Features:**
- **Entity Tracker** - Inspect components and their values with change highlighting
- **Gizmos** - Visual crosshair markers at entity positions
- **Entity ID Labels** - Display entity index next to gizmos (e.g., "42" or "42:v1")
- **Performance Metrics** - FPS, frame time graphs, and statistics
- **Lifecycle Log** - Track entity creation/destruction events

**Window Layout (1280x800):**
- Entity Tracker: (10, 10) - 420x700
- Performance Metrics: (440, 10) - 350x250
- Lifecycle Log: (440, 270) - 350x520

**Usage:**
```zig
// Mark entities for tracking
const entity = try commands.createEntityWith(.{
    Transform{ .x = 100, .y = 100, .z = 0 },
    DebugPlugin.Tracked{}, // Tag for debug tracking
});

// Display debug UI
fn debugSystem(commands: anytype, tracked: zenithor.SingleTag(DebugPlugin.Tracked)) !void {
    try DebugPlugin.openDebugWindow(.{
        Transform,
        Velocity,
        Health,
    }, commands, tracked.entities);
}
```

**Entity Structure:**
- Entities consist of a 16-bit **index** (slot identifier) and 16-bit **version** (generation counter)
- Access via `sparze.getIndex(entity)` and `sparze.getVersion(entity)`
- Debug UI displays index by default, with optional version toggle

See `src/plugins/debug/API.md` for complete API documentation.

## Important Notes

- Minimum Zig version: 0.15.1
- The build system automatically handles cimgui configuration based on `-Dimgui-docking` flag
- Web examples use Emscripten with specific memory and safety flags (see `buildWebExample()`)
- The build system clears various Nix environment variables in the shell hook to prevent build interference
- **Entity versioning**: Always use the entity handles returned by create/destroy operations. Stale entity handles will fail version checks.
- **Group ownership**: Groups use "full-owning" model where entities in the group are stored at the start of the packed array in all component sparse sets. This enables cache-friendly iteration but means groups cannot overlap (enforced at compile time).
- **Tag components**: Empty structs (`struct {}`) are automatically treated as tag components and use `TagStorage` instead of `SparseSet`. Use `world.addTag()` and `world.removeTag()` for tag-specific operations.
