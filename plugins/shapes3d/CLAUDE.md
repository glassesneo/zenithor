# Shapes3D Plugin

3D shape rendering using sokol.gfx retained mode with shaders: Plane, Box, Sphere, Cylinder, Torus.

## Components

- **Plane3D** - Flat surface (width × depth)
- **Box3D** - Cube/cuboid (width × height × depth)
- **Sphere3D** - Sphere (radius, slices, stacks)
- **Cylinder3D** - Cylinder (radius, height)
- **Torus3D** - Donut shape (radius, ring_radius)
- **Material** - Shader selection and parameters (shininess, metallic, roughness)

Optional components: Rotation, Scale, Color (defaults to white if absent)

## Resources

- **Camera3D** - View/projection parameters (eye, target, up, FOV, near/far planes)
- **Light3D** - Scene lighting (position, color, ambient strength)
- **Render3DBuffers** - Internal GPU buffers (non-serializable)
- **Render3DShaders** - Internal shader pipelines (non-serializable)

## Shaders

- **Unlit** - Simple vertex color, no lighting
- **Blinn-Phong** - Diffuse + specular with ambient (default)
- **PBR** - Physically-based rendering with metallic/roughness

## Usage

```zig
const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Rotation = zenithor.Rotation;
const Color = zenithor.Color;
const Shapes3D = @import("shapes3d_plugin");

// 3D box with PBR material
_ = try commands.createEntityWith(.{
    Transform{ .x = 0, .y = 0, .z = 0 },
    Shapes3D.Box3D{ .width = 1, .height = 1, .depth = 1 },
    Rotation{ .x = 0, .y = 0, .z = 0 },
    Shapes3D.Material{ .shader = .pbr, .metallic = 0.8, .roughness = 0.2 },
    Color.red,
});

// Configure camera
commands.setResource(Shapes3D.Camera3D, .{
    .eye = .{ 0, 3, 8 },
    .target = .{ 0, 0, 0 },
    .fov = 60.0,
});

// Configure lighting
commands.setResource(Shapes3D.Light3D, .{
    .position = .{ 5, 5, 5 },
    .color = .{ 1, 1, 1 },
    .ambient_strength = 0.15,
});
```

## Critical Notes

**IMPORTANT**: Shapes3D depends on RendererPlugin for render pass lifecycle.

**System Priorities**: 3D systems run at priorities 100 (buffer init) and 110 (drawing), before RendererPlugin.flushGL (200).

**Memory**: Uses ~3.6MB heap-allocated staging buffers (allocated lazily on first 3D entity).

**Normal Transformation**: Correct only for uniform scale. Non-uniform scale causes lighting artifacts.

## Documentation

- **@docs/PLUGIN_DEVELOPMENT.md** - Creating custom plugins
