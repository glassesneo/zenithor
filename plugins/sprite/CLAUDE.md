# Sprite Plugin

ECS-integrated 2D textured sprite rendering with asset handle caching, sprite sheets, and Z-depth ordering.

## Components

- **Sprite** - Display settings: size, UV region, flip, anchor point
- **TextureRef** - Links to texture asset with cached GPU handles
- **SpriteSheet** - Grid metadata for atlas-based sprites
- **SpriteIndex** - Current cell index within a sprite sheet

## Usage

```zig
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Color = zenithor.Color;
const Scale = zenithor.Scale;
const SpritePlugin = @import("sprite_plugin");
const AssetPlugin = @import("asset_plugin");

// Basic sprite (uses natural texture size)
fn setup(
    commands: anytype,
    registry: zenithor.ResourceMut(AssetPlugin.AssetRegistry),
    embedded: zenithor.ResourceMut(AssetPlugin.EmbeddedAssets),
    allocator: std.mem.Allocator,
) !void {
    // Register embedded texture
    try embedded.register(allocator, "player.png", @embedFile("assets/player.png"));
    
    // Create handle and request load
    const locator = AssetPlugin.AssetLocator.embedded("player.png");
    const handle = try registry.createHandle(AssetPlugin.Texture, locator);
    
    // Spawn sprite entity
    _ = try commands.createEntityWith(.{
        Transform{ .x = 100, .y = 100 },
        SpritePlugin.Sprite{},  // Uses natural size
        SpritePlugin.TextureRef{ .handle = handle },
    });
}

// Sprite with explicit size and center anchor
_ = try commands.createEntityWith(.{
    Transform{ .x = 400, .y = 300 },
    SpritePlugin.Sprite{
        .width = 64,
        .height = 64,
        .anchor_x = 0.5,  // Centered
        .anchor_y = 0.5,
    },
    SpritePlugin.TextureRef{ .handle = handle },
    Color.red,  // Optional tint
});

// Sprite with scale component
_ = try commands.createEntityWith(.{
    Transform{ .x = 200, .y = 200 },
    SpritePlugin.Sprite{},
    SpritePlugin.TextureRef{ .handle = handle },
    Scale{ .x = 2.0, .y = 2.0 },  // 2x size
});

// Sprite sheet animation
_ = try commands.createEntityWith(.{
    Transform{ .x = 300, .y = 300 },
    SpritePlugin.Sprite{},
    SpritePlugin.TextureRef{ .handle = spritesheet_handle },
    SpritePlugin.SpriteSheet{
        .cell_width = 32,
        .cell_height = 32,
        .columns = 4,
        .rows = 4,
    },
    SpritePlugin.SpriteIndex{ .index = 0 },  // First frame
});
```

## Anchor Point

Determines where Transform position is relative to the sprite's bounding box.

```
anchor = (0, 0) - Top-left (default)     anchor = (0.5, 0.5) - Center
┌──────────┐                              ┌──────────┐
│ * Position                              │          │
│          │                              │    *     │
│          │                              │          │
└──────────┘                              └──────────┘
```

Default is top-left (0, 0) for consistency with Rectangle and 2D coordinate system.

## Sprite Sheets

For atlas textures with uniform grid cells:

```zig
SpriteSheet{
    .cell_width = 32,   // Pixels per cell
    .cell_height = 32,
    .columns = 8,       // Cells per row
    .rows = 4,          // Number of rows
    .padding = 1,       // Gap between cells (optional)
    .margin = 2,        // Border around sheet (optional)
}
```

Cell index is linear: 0 = top-left, incrementing left-to-right, top-to-bottom.

## Z-Ordering

Sprites respect `Transform.z` for depth ordering with other 2D shapes:
- Lower Z = rendered in front
- Higher Z = rendered behind

## System Tags

- `sprite-resolve` - Texture handle resolution (pre_render, priority 50)
- `sprite-render` - Sprite drawing (render, priority 115)

## Critical Notes

**IMPORTANT**: SpritePlugin requires AssetPlugin for texture loading. Ensure textures are loaded via `AssetPlugin.AssetRequest` events before sprites will render.

**IMPORTANT**: TextureRef caches GPU handles automatically. Hot-reload is supported - when asset generation changes, cache is invalidated and re-resolved.

**Size precedence**: `Sprite.width/height` > `SpriteSheet.cell_width/height` > `TextureRef.natural_width/height`. Scale component multiplies the final size.
