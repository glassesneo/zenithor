# Shapes2D Plugin

2D shape rendering using sokol.gl immediate mode: Point, Line, Triangle, Rectangle, Circle.

## Components

- **Point** - Single pixel point
- **Line** - Line from Transform position to offset (x, y)
- **Triangle** - Triangle with three vertices relative to Transform
- **Rectangle** - Axis-aligned rectangle (width x, height y)
- **Circle** - Circle with radius and configurable segments (default 32)

All shapes use optional Color component (defaults to red if absent).

## Usage

```zig
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Color = zenithor.Color;
const Shapes2D = @import("shapes2d_plugin");

// 2D circle
_ = try commands.createEntityWith(.{
    Transform{ .x = 100, .y = 100, .z = 0 },
    Shapes2D.Circle{ .radius = 50 },
    Color.blue,
});

// 2D rectangle (defaults to red)
_ = try commands.createEntityWith(.{
    Transform{ .x = 200, .y = 200, .z = 0 },
    Shapes2D.Rectangle{ .x = 150, .y = 100 },
});
```

## Critical Notes

**IMPORTANT**: Shapes2D depends on RendererPlugin for render pass lifecycle. RendererPlugin provides `beginPass/endPass/commit` and owns the `PassAction` resource for controlling clear color.

**2D Coordinate System**: Origin (0,0) at top-left, Y increases downward.

**Z-ordering**: Lower Z values render in front (closer to camera), higher Z values render behind.

**Default Color**: Entities without Color component default to red (1.0, 0.0, 0.0, 1.0).

## Documentation

- **@docs/PLUGIN_DEVELOPMENT.md** - Creating custom plugins
