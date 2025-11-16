# Graphics Plugin

2D shape rendering using Sokol GL.

## Components

**Point** (empty struct)
- Renders as a single point at Transform position

**Line** `{ x: f32, y: f32 }`
- Renders from Transform position to `(Transform.x + x, Transform.y + y)`

**Triangle** `{ x1, y1, x2, y2, x3, y3: f32 }`
- Three vertices relative to Transform position

**Rectangle** `{ x: f32, y: f32 }`
- Width and height from Transform position

**Circle** `{ radius: f32, segments: u32 = 32 }`
- Radius and approximation quality (higher segments = smoother)

All shapes use optional `Color` component (defaults to red if absent).

## Resources

**PassAction** (sokol.gfx.PassAction)
- Frame buffer clear settings (initialized to white background)

## Rendering Pipeline

Systems run in stages:
1. `.pre_render`: Set GL defaults, configure 2D orthographic projection
2. `.render`: Draw all shapes (Point → Line → Triangle → Rectangle → Circle)
3. `.render_submit`: Begin render pass
4. `.post_render`: End pass and commit

## Usage

```zig
const Graphics = @import("graphics");

// Create shapes
const e1 = try commands.createEntity();
try commands.addComponent(e1, Transform, .{ .x = 100, .y = 100, .z = 0 });
try commands.addComponent(e1, Graphics.Circle, .{ .radius = 50 });
try commands.addComponent(e1, Color, Color.blue);

const e2 = try commands.createEntity();
try commands.addComponent(e2, Transform, .{ .x = 200, .y = 200, .z = 0 });
try commands.addComponent(e2, Graphics.Rectangle, .{ .x = 80, .y = 60 });
```

**Coordinate System**: Origin (0, 0) at top-left, Y increases downward.
