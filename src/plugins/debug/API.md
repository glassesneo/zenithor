# Debug Plugin API

## Overview

The Debug plugin provides runtime inspection and visualization tools for entity-component debugging. It includes:
- **Entity Tracker** - Inspect components and their values in real-time
- **Gizmos** - Visual markers for entity positions
- **Entity ID Labels** - Display entity indices next to gizmos
- **Performance Metrics** - FPS, frame time, and entity statistics
- **Lifecycle Log** - Track entity creation and destruction events

## Components

### `Tracked` (Tag Component)

Mark entities for debugging and visualization.

```zig
pub const Tracked = struct {};
```

**Usage:**
```zig
const entity = try commands.createEntityWith(.{
    Transform{ .x = 100, .y = 100, .z = 0 },
    MyComponent{},
    DebugPlugin.Tracked{}, // Mark for tracking
});
```

## Functions

### `openDebugWindow`

Opens the main debug UI showing all tracked entities and their components.

```zig
pub fn openDebugWindow(
    ComponentTypes: anytype,
    commands: anytype,
    tracked_entities: []const sparze.Entity,
) !void
```

**Parameters:**
- `ComponentTypes` - Tuple of component types to display (e.g., `.{Transform, Velocity}`)
- `commands` - World commands interface for accessing component data
- `tracked_entities` - Slice of entities with the `Tracked` component

**Features:**
- Component inspector with change highlighting
- Entity gizmos (crosshair markers at entity positions)
- Entity ID labels (shows entity index, e.g., "42" or "42:v1" with version)

**Example:**
```zig
fn debugSystem(commands: anytype, tracked: zenithor.SingleTag(DebugPlugin.Tracked)) !void {
    try DebugPlugin.openDebugWindow(.{
        BuiltinPlugin.Transform,
        Velocity,
        Health,
        GraphicsPlugin.Rectangle,
    }, commands, tracked.entities);
}
```

### `openPerformanceWindow`

Displays performance metrics and statistics.

```zig
pub fn openPerformanceWindow() void
```

Shows:
- Current FPS and frame time
- Min/Max FPS tracking
- Frame time history graph (120 frames)
- Entity counts and lifecycle event statistics

**Example:**
```zig
// Called automatically by the Debug plugin's internal system
// Can also be called manually from any system
fn myDebugSystem() !void {
    DebugPlugin.openPerformanceWindow();
}
```

### `openLifecycleWindow`

Displays entity creation and destruction events.

```zig
pub fn openLifecycleWindow() void
```

Shows:
- Chronological event log (newest first)
- Entity index and version for each event
- Timestamp and frame number
- Color-coded by event type (green=created, red=destroyed)

**Example:**
```zig
// Called automatically by the Debug plugin's internal system
fn myDebugSystem() !void {
    DebugPlugin.openLifecycleWindow();
}
```

### `logEntityCreated`

Log an entity creation event.

```zig
pub fn logEntityCreated(entity: sparze.Entity) !void
```

**Parameters:**
- `entity` - The entity that was created

**Example:**
```zig
const entity = try commands.createEntity();
try DebugPlugin.logEntityCreated(entity);
```

### `logEntityDestroyed`

Log an entity destruction event.

```zig
pub fn logEntityDestroyed(entity: sparze.Entity) !void
```

**Parameters:**
- `entity` - The entity that will be destroyed

**Example:**
```zig
try DebugPlugin.logEntityDestroyed(entity);
try commands.destroyEntity(entity);
```

## UI Controls

### Entity Tracker Window

Located at **(10, 10)** with size **420x700**.

**Header Controls:**
| Button | Function |
|--------|----------|
| **Gizmos** | Toggle crosshair gizmos on/off |
| **IDs** | Toggle entity ID labels on/off |
| **Ver** | Toggle version display in IDs (e.g., "42" vs "42:v1") |

**Component Filters:**
- Collapsible section to show/hide specific component types
- Per-component checkboxes

**Entity Sections:**
- Collapsible tree view for each tracked entity
- Entity header shows: `Entity {index} (v{version})`
- Component values with change highlighting (flashes orange when modified)
- Type information and formatted values

### Performance Metrics Window

Located at **(440, 10)** with size **350x250**.

**Displays:**
- Current FPS (green text)
- Average frame time in milliseconds
- Min/Max FPS with reset button
- Frame time history graph
- Tracked entity count
- Total lifecycle events
- Current frame number

### Lifecycle Log Window

Located at **(440, 270)** with size **350x520**.

**Features:**
- Reverse chronological order (newest first)
- Event format: `[{time}s] Frame {frame} | Entity {index} (v{version}) {EVENT}`
- Color coding:
  - **Green**: CREATED events
  - **Red**: DESTROYED events
- Statistics: Created/Destroyed/Net count
- Auto-scroll to newest
- Clear button
- Maximum 1000 events (oldest removed automatically)

## Entity Structure

Entities consist of two 16-bit components:
- **Index**: Entity slot identifier (0-65535)
- **Version**: Generation counter (increments when slot is recycled)

**Access:**
```zig
const entity_index = sparze.getIndex(entity);
const entity_version = sparze.getVersion(entity);
```

## Entity ID Display Format

### Default (Index Only)
```
42    ← Entity at index 42
1     ← Entity at index 1
255   ← Entity at index 255
```

### With Version
```
42:v1   ← Entity at index 42, version 1
42:v2   ← Same slot recycled, now version 2
1:v1    ← Entity at index 1, version 1
```

**Display Details:**
- **Position**: Offset from entity by (gizmo_size + 5, -gizmo_size - 5) pixels
- **Color**: Yellow text (#FFFF00)
- **Background**: Semi-transparent black (70% opacity)
- **Rendering**: ImGui foreground draw list (always on top)

## Gizmo Visualization

**Crosshair gizmo** appears at each tracked entity's transform position:
- **Point**: Bright magenta circle
- **Cross**: Yellow horizontal and vertical lines
- **Size**: Configurable via `debug_state.gizmo_size` (default: 10.0 pixels)

## Change Detection

Components are automatically monitored for changes:
- Uses hash-based change detection
- Highlights component values for 60 frames after change
- Orange background on component tree nodes
- Brighter text color for modified values

## Window Layout (1280x800)

```
┌─────────────────────────────────────────────────────────┐
│ Window Title Bar                                        │
├──────────────────┬──────────────────────────────────────┤
│ Entity Tracker   │ Performance Metrics                  │
│ (10,10)          │ (440,10)                             │
│ 420x700          │ 350x250                              │
│                  ├──────────────────────────────────────┤
│                  │ Lifecycle Log                        │
│                  │ (440,270)                            │
│                  │ 350x520                              │
│                  │                                      │
│                  │                                      │
│                  │                                      │
├──────────────────┴──────────────────────────────────────┤
│ Demo Controls (10,720) 420x70                          │
└─────────────────────────────────────────────────────────┘
```

## Integration

### Minimal Setup

```zig
const DebugPlugin = zenithor.DebugPlugin;

pub fn main() !void {
    zenithor.run(.{ GraphicsPlugin, ImGuiPlugin, DebugPlugin, MyGame });
}

const MyGame = struct {
    pub const Components = .{ MyComponent };
    
    pub fn build(registry: SystemRegistry) !void {
        registry.registerSystem(debugInfo, .render);
    }
};

fn debugInfo(commands: anytype, tracked: zenithor.SingleTag(DebugPlugin.Tracked)) !void {
    try DebugPlugin.openDebugWindow(.{
        BuiltinPlugin.Transform,
        MyComponent,
    }, commands, tracked.entities);
}
```

### With Lifecycle Logging

```zig
fn spawner(commands: anytype) !void {
    const entity = try commands.createEntityWith(.{
        Transform{ .x = 100, .y = 100, .z = 0 },
        DebugPlugin.Tracked{},
    });
    try DebugPlugin.logEntityCreated(entity);
}

fn cleanup(commands: anytype, query: Query(struct { Health })) !void {
    for (query.entities) |entity| {
        if (query.getComponent(entity, Health)) |health| {
            if (health.current <= 0) {
                try DebugPlugin.logEntityDestroyed(entity);
                try commands.destroyEntity(entity);
            }
        }
    }
}
```

## Custom Component Formatting

Implement a `format` method for better debug display:

```zig
const Velocity = struct {
    x: f32,
    y: f32,

    pub fn format(self: Velocity, writer: anytype) !void {
        try writer.print("Velocity({d:.1} px/s, {d:.1} px/s)", .{ self.x, self.y });
    }
};
```

Without custom formatting, components are displayed using Zig's default `{any}` format.

## Performance Considerations

- Only tracked entities are processed
- Component change detection uses efficient hashing
- UI rendering only when windows are open
- Lifecycle log limited to 1000 events
- No heap allocations for entity ID text (uses stack buffer)

## Example

See `examples/debug_demo.zig` for a complete working example demonstrating:
- Entity tracking with multiple component types
- Lifecycle logging
- Component changes and highlighting
- Automatic spawning and destruction
- Custom component formatting

**Run the demo:**
```bash
zig build run-debug_demo
```
