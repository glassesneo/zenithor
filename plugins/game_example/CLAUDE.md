# Game Example Plugin

Demonstrates the plugin dependency system with a simple game.

## Purpose

This plugin showcases how to:
- Declare dependencies on other plugins using `pub const Requires`
- Use types and resources from dependent plugins
- Build a complete game feature as a plugin

## Dependencies

```zig
pub const Requires = .{ TimePlugin, InputPlugin, GraphicsPlugin };
```

When a user includes only `GamePlugin` in `zenithor.run()`, the dependency system automatically includes Time, Input, and Graphics plugins. This eliminates manual dependency tracking.

## Components

**Player** `{ speed: f32 = 200.0 }`
- Player-controlled entity with movement speed

**Enemy** `{ speed: f32 = 50.0, direction: f32 = 1.0 }`
- AI-controlled enemy that bounces horizontally

**Score** `{ value: u32 = 0 }`
- Player score component

## Events

**EnemyDefeated** `{ points: u32 }`
- Fired when player collides with enemy

**GameOver** `{}`
- Fired when game ends (placeholder)

## Systems

**setupGame** (startup, `.first`)
- Creates player entity (blue circle)
- Spawns 3 enemy entities (red rectangles)

**playerMovement** (`.update`)
- WASD keyboard movement
- Right-click mouse movement (move toward cursor)
- Boundary clamping

**enemyMovement** (`.update`)
- Horizontal movement with edge bouncing

**checkCollisions** (`.post_update`)
- Circle-rectangle collision detection
- Destroys enemies on contact
- Awards points and fires events

**handleGameEvents** (`.post_update`)
- Prints event notifications

## Usage

```zig
const zenithor = @import("zenithor");
const GamePlugin = @import("game_example");

pub fn main() void {
    // Only GamePlugin needed - dependencies auto-included!
    zenithor.run(.{GamePlugin});
}
```

## Controls

- **WASD** - Move player
- **Right Mouse Button** (hold) - Move toward cursor
- **Collision with red rectangles** - Defeat enemy (+10 points)

## Implementation Notes

- Uses types from dependent plugins (Time, Mouse, Keyboard, Circle, Rectangle)
- Demonstrates system ordering (.update → .post_update for collision)
- Shows event-based communication (EnemyDefeated events)
- Example of startup systems for initial setup
