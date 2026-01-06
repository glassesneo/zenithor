# Plugin Development Guide

A step-by-step guide for creating Zenithor plugins.

## What is a Plugin?

A plugin is a Zig module that extends Zenithor's functionality by:
- Declaring Components, Resources, Events, and Groups
- Registering systems that run in specific stages
- Optionally depending on other plugins

Plugins are compiled into the application at build time, enabling zero-cost abstractions and complete type safety.

## Plugin Structure

Plugins are plain Zig `struct`s. Declarations are mostly optional (the engine checks with `@hasDecl`), but it's recommended to define empty tuples for clarity.

```zig
	// Recommended: Component types (can be empty)
	pub const Components = .{ MyComponent, AnotherComponent };

	// Recommended: Resource types (can be empty)
	pub const Resources = .{ MyResource };

	// Recommended: Event types (can be empty)
	pub const Events = .{ MyEvent };

	// Optional: Group types (can be empty)
	pub const Groups = .{ MyGroup };

// Optional: Plugin dependencies
pub const Requires = .{ SomeOtherPlugin };

// Optional: System declarations
pub const systems = .{
    .startup = &.{ /* startup systems */ },
    .main = &.{ /* regular systems */ },
    .terminate = &.{ /* cleanup systems */ },
    .event_handlers = &.{ /* Sokol event handlers */ },
};
```

## Step 1: Create Plugin Directory

```bash
mkdir -p plugins/my_plugin/src
cd plugins/my_plugin
```

Create `build.zig.zon`:

```zig
.{
    .name = "my_plugin",
    .version = "0.1.0",
    .minimum_zig_version = "0.15.1",
    .dependencies = .{},
    .paths = .{
        "build.zig.zon",
        "src",
    },
}
```

## Step 2: Define Components

Components are pure data structures attached to entities:

```zig
// plugins/my_plugin/src/root.zig
const zenithor = @import("zenithor");
const sparze = @import("sparze");

// Simple component
pub const Health = struct {
    current: f32,
    max: f32,
};

// Component with default values
pub const Armor = struct {
    defense: f32 = 10.0,
    durability: f32 = 100.0,
};

// Tag component (empty struct, uses TagStorage)
pub const Player = struct {};

// Export components
pub const Components = .{ Health, Armor, Player };
```

## Step 3: Define Resources

Resources are global singletons accessible to all systems:

```zig
// Game-wide state
pub const GameState = struct {
    score: u32 = 0,
    level: u32 = 1,
    paused: bool = false,
};

// Non-serializable resource (transient state)
pub const FrameStats = struct {
    fps: f32 = 0.0,
    frame_time: f32 = 0.0,

    pub const serialized = false; // Don't save to disk
};

pub const Resources = .{ GameState, FrameStats };
```

## Step 4: Define Events

Events are temporary messages processed within a frame:

```zig
// Gameplay event
pub const DamageEvent = struct {
    target: u32, // Entity ID
    amount: f32,
    source: u32,
};

// UI event
pub const ButtonClickEvent = struct {
    button_id: u32,
};

pub const Events = .{ DamageEvent, ButtonClickEvent };
```

## Step 5: Write Systems

Systems contain your game logic and run every frame (or once for startup/terminate):

```zig
const Stage = zenithor.Stage;
const SystemConfig = zenithor.SystemConfig;
const Resource = zenithor.Resource;
const ResourceMut = zenithor.ResourceMut;
const EventReader = zenithor.EventReader;
const EventWriter = zenithor.EventWriter;
const SingleQuery = zenithor.SingleQuery;

// Startup system (runs once at initialization)
fn initGame(commands: anytype) !void {
    commands.setResource(GameState, .{ .score = 0, .level = 1 });

    // Spawn player entity
    _ = try commands.createEntityWith(.{
        Player{},
        Health{ .current = 100, .max = 100 },
        zenithor.Transform{ .x = 0, .y = 0, .z = 0 },
    });
}

// Regular system (runs every frame)
fn updateHealth(
    damage_events: EventReader(DamageEvent),
    health_query: SingleQuery(Health),
) void {
    for (damage_events.read()) |event| {
        for (health_query.entities, health_query.components) |_, *health| {
            health.current = @max(0, health.current - event.amount);
        }
    }
}

// System with resource access
fn updateStats(
    game_state: Resource(GameState),
    frame_stats: ResourceMut(FrameStats),
    time: Resource(@import("time_plugin").Time),
) !void {
    if (game_state.value.paused) return;

    frame_stats.value.fps = time.value.fps;
    frame_stats.value.frame_time = time.value.delta_time;
}

// Event-driven system
fn checkGameOver(
    health_query: SingleQuery(Health),
    writer: EventWriter(ButtonClickEvent),
) !void {
    for (health_query.entities, health_query.components) |_, health| {
        if (health.current <= 0) try writer.enqueue(.{ .button_id = 999 });
    }
}

// Cleanup system (runs once on shutdown)
fn cleanup() !void {
    // Save high score, release resources, etc.
}
```

## Step 6: Register Systems

Declare systems in the `systems` tuple:

```zig
pub const systems = .{
    // Startup systems run once at initialization
    .startup = &.{
        .{ .system = initGame, .stage = .first },
    },

    // Main systems run every frame
    .main = &.{
        // Default priority (0), runs in registration order
        .{ .system = updateHealth, .stage = .update, .config = .{
            .tags = &.{"health-system"},
        } },

        // Higher priority system (runs later)
        .{ .system = updateStats, .stage = .update, .config = .{
            .priority = 10
        } },

        // System with ordering constraints
        .{ .system = checkGameOver, .stage = .post_update, .config = .{
            .after = &.{"health-system"},
        } },
    },

    // Terminate systems run once on shutdown
    .terminate = &.{
        .{ .system = cleanup, .stage = .last },
    },

    // Event handlers process Sokol input/window events
    .event_handlers = &.{handleInput},
};

// Event handler signature: (sokol.app.Event, world) !void
fn handleInput(event: sokol.app.Event, world: anytype) void {
    const kb = world.getResourcePtrMut(@import("input_plugin").Keyboard);
    // Process input...
}
```

### System Descriptor Fields

Each system descriptor supports:
- `.system` (required) - Function reference
- `.stage` (required) - Stage enum (`.first`, `.pre_update`, `.update`, `.post_update`, `.pre_render`, `.render`, `.post_render`, `.last`, `.post_process`)
- `.config` (optional) - SystemConfig struct:
  - `priority: i16 = 0` - Lower values run first
  - `tags: []const []const u8 = &.{}` - Tags for this system
  - `before: []const []const u8 = &.{}` - Run before these tags
  - `after: []const []const u8 = &.{}` - Run after these tags

## Step 7: Add Plugin Dependencies

If your plugin requires other plugins, declare them with `Requires`:

```zig
const TimePlugin = @import("time_plugin");
const InputPlugin = @import("input_plugin");

pub const Requires = .{ TimePlugin, InputPlugin };
```

The engine automatically includes dependencies (transitively) and detects circular dependencies at compile time.

## Integrating with Render Pass

If your plugin needs to render content, depend on `renderer_plugin`:

```zig
const Renderer = @import("renderer_plugin");

pub const Requires = .{Renderer};

fn myRenderSystem() void {
    // Draw calls here - automatically inside render pass
}

pub const systems = .{
    .main = &.{
        .{ .system = myRenderSystem, .stage = .render },
    },
};
```

**System guarantees**:
- `beginPass` runs FIRST in `.render` stage (priority -32768, lowest)
- `endPass` runs LAST in `.render` stage (priority 32760, very high)
- `commit` runs FIRST in `.post_render` stage (priority -32768, lowest)
- All `.render` systems run inside a valid render pass

**Modifying background color**:
```zig
fn setBackgroundColor(pass_action: ResourceMut(Renderer.PassAction)) void {
    pass_action.value.colors[0].clear_value = .{ .r = 0.1, .g = 0.1, .b = 0.2, .a = 1.0 };
}
```

For late rendering (overlays, UI), use high priority in `.render` stage:
```zig
.{ .system = overlaySystem, .stage = .render, .config = .{
    .priority = 1000,  // Renders late, before endPass
} },
```

## Step 8: Integrate with Build System

Add your plugin to the project's `build.zig`:

```zig
// In build.zig, add to the plugin module creation section (see existing plugins)
const my_plugin_mod = b.addModule("my_plugin", .{
    .root_source_file = b.path("plugins/my_plugin/src/root.zig"),
    .target = target,
    .optimize = optimize,
    .imports = exported_imports[0..], // zenithor/sokol/sparze
});
exe.root_module.addImport("my_plugin", my_plugin_mod);
```

## Step 9: Use Plugin in Application

```zig
const zenithor = @import("zenithor");
const MyPlugin = @import("my_plugin");

pub fn main() void {
    zenithor.run(.{ MyPlugin }, .{});
}
```

## Complete Example: Velocity Plugin

```zig
// plugins/velocity/src/root.zig
const zenithor = @import("zenithor");
const sparze = @import("sparze");

// Component
pub const Velocity = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

pub const Components = .{Velocity};
pub const Resources = .{};
pub const Events = .{};

// Require Time plugin for delta time
const TimePlugin = @import("time_plugin");
pub const Requires = .{TimePlugin};

// System
fn applyVelocity(
    time: sparze.Resource(TimePlugin.Time),
    entities: sparze.Query(struct { zenithor.Transform, Velocity }),
) !void {
    const dt = time.value.delta_time;
    for (entities.entities) |entity| {
        const pos = entities.getComponentMut(entity, zenithor.Transform);
        const vel = entities.getComponent(entity, Velocity);

        pos.x += vel.x * dt;
        pos.y += vel.y * dt;
        pos.z += vel.z * dt;
    }
}

pub const systems = .{
    .main = &.{
        .{ .system = applyVelocity, .stage = .update },
    },
};
```

## Testing Strategies

### Unit Tests

Test individual systems in isolation:

```zig
const std = @import("std");
const zenithor = @import("zenithor");
const sparze = @import("sparze");

test "damage system reduces health" {
    const World = sparze.World(
        .{ Health },
        .{},
        .{ DamageEvent },
        .{},
    );

    var world = World.init(std.testing.allocator);
    defer world.deinit();

    // Create entity with health
    const entity = try world.createEntityWith(.{
        Health{ .current = 100, .max = 100 },
    });

    // Enqueue damage event
    try world.getEventWriter(DamageEvent).enqueue(.{
        .target = entity,
        .amount = 25,
    });

    // Run system
    try world.runSystem(updateHealth);

    // Verify health reduced
    const health = world.getComponent(entity, Health);
    try std.testing.expectEqual(75.0, health.current);
}
```

### Integration Tests

Test plugin interaction with examples:

```zig
// examples/my_plugin_test.zig
const zenithor = @import("zenithor");
const MyPlugin = @import("my_plugin");
const Shapes2DPlugin = @import("shapes2d_plugin");

pub fn main() void {
    zenithor.run(.{ MyPlugin, Shapes2DPlugin }, .{});
}
```

Build and run:
```bash
zig build test                  # Unit tests
zig build run-my_plugin_test    # Integration test (after adding example to build.zig)
```

## Best Practices

### Do's
- ✅ Keep components as pure data (no methods)
- ✅ Put logic in systems, not components
- ✅ Use Resources for global state
- ✅ Use Events for one-time messages
- ✅ Declare plugin dependencies explicitly
- ✅ Tag systems for ordering constraints
- ✅ Mark transient resources with `serialized = false`
- ✅ Use tag components (empty structs) for entity classification

### Don'ts
- ❌ Don't call `sokol.gfx.setup()`/`sokol.gl.setup()` (renderer plugin owns these) or `sokol.time.setup()` (time_plugin owns this)
- ❌ Don't use `try` in void return systems (use `!void` signature)
- ❌ Don't create circular plugin dependencies
- ❌ Don't store allocators in components (use commands parameter)
- ❌ Don't mutate components in event handlers directly (use commands)
- ❌ Don't use global variables (use Resources instead)

## Allocator Usage

Systems that need dynamic memory allocation should request the allocator as a parameter. Sparze automatically injects the World's allocator, which is already platform-aware:

- **WASM**: Uses `std.heap.c_allocator`
- **Native**: Uses `std.heap.page_allocator` (or user-specified via `zenithor.run(..., .{ .allocator = my_allocator })`)

### Correct Pattern

```zig
fn mySystem(
    allocator: std.mem.Allocator,  // ← Sparze injects world.allocator
    commands: anytype,
    my_resource: zenithor.ResourceMut(MyResource),
) !void {
    // Use the injected allocator for any dynamic allocations
    const buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer);
    
    // Pass to resource methods that need allocation
    try my_resource.addItem(allocator, item);
}
```

### Incorrect Pattern (Do Not Use)

```zig
// ❌ WRONG: Manual platform detection bypasses zenithor's abstraction
fn getAllocator() std.mem.Allocator {
    const builtin = @import("builtin");
    return if (builtin.target.cpu.arch.isWasm())
        std.heap.c_allocator
    else
        std.heap.page_allocator;
}

fn badSystem(my_resource: zenithor.ResourceMut(MyResource)) !void {
    // ❌ This can cause allocator mismatch bugs!
    try my_resource.addItem(getAllocator(), item);
}
```

**Why the manual pattern is wrong:**
1. Ignores user-specified allocator from `zenithor.run()` options
2. Can cause allocator mismatch if resource `deinit()` uses a different allocator
3. Duplicates logic that Zenithor already handles

### Resource Init with Allocator

Resources that need an allocator should store it during initialization. Sparze calls `init(allocator)` automatically with the World's allocator:

```zig
pub const MyResource = struct {
    items: std.ArrayList(Item),
    allocator: std.mem.Allocator,

    /// Sparze auto-calls this with world.allocator
    pub fn init(allocator: std.mem.Allocator) MyResource {
        return .{
            .items = std.ArrayList(Item).init(allocator),
            .allocator = allocator,
        };
    }

    /// Sparze auto-calls this during World.deinit()
    pub fn deinit(self: *MyResource, allocator: std.mem.Allocator) void {
        _ = allocator; // Use self.allocator for consistency
        self.items.deinit();
    }

    pub fn addItem(self: *MyResource, item: Item) !void {
        try self.items.append(item);
    }
};
```

## Advanced Topics

### Custom Serialization

For non-POD resources, implement custom serializer:

```zig
pub const MyResource = struct {
    data: std.ArrayList(u8),

    pub const Serializer = struct {
        pub fn serialize(self: MyResource, writer: anytype) !void {
            try writer.writeInt(u32, @intCast(self.data.items.len), .little);
            try writer.writeAll(self.data.items);
        }

        pub fn deserialize(allocator: std.mem.Allocator, reader: anytype) !MyResource {
            const len = try reader.readInt(u32, .little);
            var data = try std.ArrayList(u8).initCapacity(allocator, len);
            try reader.readNoEof(data.items[0..len]);
            data.items.len = len;
            return .{ .data = data };
        }
    };
};
```

### Groups for Performance

Define groups for frequently queried component combinations:

```zig
pub const PlayerGroup = struct { Player, Health, zenithor.Transform };
pub const Groups = .{PlayerGroup};

// In system
fn updatePlayers(players: sparze.Group(PlayerGroup)) !void {
    for (players.entities) |entity| {
        const health = players.getComponent(entity, Health);
        const pos = players.getComponentMut(entity, zenithor.Transform);
        // Faster than Query for fixed component sets
    }
}
```

## Troubleshooting

**"Type not found in World"**
- Ensure component/resource is in plugin's Components/Resources tuple
- Check that plugin is included in zenithor.run()

**"System not running"**
- Verify system is in `systems` declaration
- Check stage matches expected timing
- Use priority/constraints if ordering matters

**"Circular dependency detected"**
- Review plugin Requires chains
- Break cycle by extracting shared types to a common plugin

**"WASM stack overflow"**
- Increase stack size: `zig build -Dtarget=wasm32-emscripten -Dstack-size=8`
- Move large allocations from stack to heap using commands parameter

## See Also

- docs/SYSTEM_ORDERING.md - System execution order details
- docs/APPLICATION_LIFECYCLE.md - Engine initialization flow
- [Sparze Documentation](https://github.com/glassesneo/sparze/blob/main/CLAUDE.md) - ECS framework reference
- examples/ - Working plugin examples
