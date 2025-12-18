# Graphics Plugin

2D shape rendering (Point, Line, Triangle, Rectangle, Circle) and 3D shape rendering (Plane, Box, Sphere, Cylinder, Torus) with multiple shader options.

## Components

**2D**: Point, Line, Triangle, Rectangle, Circle
**3D**: Plane3D, Box3D, Sphere3D, Cylinder3D, Torus3D
**3D Optional**: Rotation, Scale, Material (shader selection)

All shapes use optional Color component (defaults: 2D=red, 3D=white).

## Resources

- **Camera3D** - Position, target, up, FOV, near/far planes
- **Light3D** - Position, color, ambient strength

## Shaders

- **Unlit** - Simple vertex color, no lighting
- **Blinn-Phong** - Diffuse + specular with ambient (default)
- **PBR** - Physically-based rendering with metallic/roughness

## Usage

```zig
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Color = zenithor.Color;
const Graphics = @import("graphics_plugin").Default;

// 2D circle
_ = try commands.createEntityWith(.{
    Transform{ .x = 100, .y = 100, .z = 0 },
    Graphics.Circle{ .radius = 50 },
    Color.blue,
});

// 3D box with PBR material
_ = try commands.createEntityWith(.{
    Transform{ .x = 0, .y = 0, .z = 0 },
    Graphics.Box3D{ .width = 1, .height = 1, .depth = 1 },
    Graphics.Material{ .shader = .pbr, .metallic = 0.8, .roughness = 0.2 },
    Color.red,
});
```

## Critical Notes

**IMPORTANT**: Graphics depends on RenderContext plugin for render pass lifecycle. RenderContext provides `beginPass/endPass/commit` with stable tags and owns the `PassAction` resource for controlling clear color and depth.

**2D Coordinate System**: Origin (0,0) at top-left, Y increases downward
**3D Normal Transformation**: Correct only for uniform scale. Non-uniform scale causes lighting artifacts.
**Memory**: 3D rendering uses heap-allocated staging buffers (~3.6MB at startup)

## Documentation

- **@docs/PLUGIN_DEVELOPMENT.md** - Creating custom plugins
