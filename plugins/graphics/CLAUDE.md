# Graphics Plugin

2D shape rendering using Sokol GL and 3D shape rendering using Sokol GFX with multiple shader options.

## 2D Components

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

All 2D shapes use optional `Color` component (defaults to red if absent).

**2D Coordinate System**: Origin (0, 0) at top-left, Y increases downward.

## 3D Components

**Plane3D** `{ width: f32 = 1.0, depth: f32 = 1.0, tiles: u16 = 1 }`
- Flat plane in XZ plane

**Box3D** `{ width: f32 = 1.0, height: f32 = 1.0, depth: f32 = 1.0, tiles: u16 = 1 }`
- 3D box/cube

**Sphere3D** `{ radius: f32 = 0.5, slices: u16 = 16, stacks: u16 = 12 }`
- Sphere with configurable tessellation

**Cylinder3D** `{ radius: f32 = 0.5, height: f32 = 1.0, slices: u16 = 16, stacks: u16 = 1 }`
- Cylinder along Y axis

**Torus3D** `{ radius: f32 = 0.5, ring_radius: f32 = 0.2, sides: u16 = 16, rings: u16 = 16 }`
- Donut shape

3D shapes use `Transform` for position. Optional `Rotation` and `Scale` components for orientation and sizing. Optional `Color` component (defaults to white).

## Shader Selection

**ShaderType** enum: `.unlit`, `.blinn_phong`, `.pbr`

**Material** component for per-object shader selection:
```zig
pub const Material = struct {
    shader: ShaderType = .blinn_phong,
    // Blinn-Phong parameters
    shininess: f32 = 32.0,
    specular_strength: f32 = 0.5,
    // PBR parameters
    metallic: f32 = 0.0,
    roughness: f32 = 0.5,
};
```

## Resources

**RenderingOptions** - Background clear color and depth configuration (pass action)

**Camera3D** - 3D camera for view/projection:
```zig
pub const Camera3D = struct {
    eye: [3]f32 = .{ 0, 2, 5 },      // Camera position
    target: [3]f32 = .{ 0, 0, 0 },   // Look-at target
    up: [3]f32 = .{ 0, 1, 0 },       // Up vector
    fov: f32 = 60.0,                 // Field of view (degrees)
    near: f32 = 0.1,                 // Near plane
    far: f32 = 100.0,                // Far plane
};
```

**Light3D** - Global lighting:
```zig
pub const Light3D = struct {
    position: [3]f32 = .{ 5, 5, 5 },
    color: [3]f32 = .{ 1, 1, 1 },
    ambient_strength: f32 = 0.1,
};
```

## Rendering Pipeline

Systems run in stages:
1. `.pre_render`: Set GL defaults, configure 2D orthographic projection
2. `.render`: Draw all 2D shapes (Point, Line, Triangle, Rectangle, Circle)
3. `.render_submit`: Draw 3D shapes with depth testing, execute render pass

## Usage

### 2D Shapes
```zig
const Graphics = @import("graphics_plugin");

const e1 = try commands.createEntity();
try commands.addComponent(e1, Transform, .{ .x = 100, .y = 100, .z = 0 });
try commands.addComponent(e1, Graphics.Circle, .{ .radius = 50 });
try commands.addComponent(e1, Color, Color.blue);
```

### 3D Shapes
```zig
const Graphics = @import("graphics_plugin");

// Red box with default Blinn-Phong shading
_ = try commands.createEntityWith(.{
    Graphics.Box3D{ .width = 1.0, .height = 1.0, .depth = 1.0 },
    Transform{ .x = 0, .y = 0, .z = 0 },
    Color.red,
});

// Sphere with PBR material
_ = try commands.createEntityWith(.{
    Graphics.Sphere3D{ .radius = 0.5 },
    Transform{ .x = 2.0, .y = 0, .z = 0 },
    Color.green,
    Graphics.Material{ .shader = .pbr, .metallic = 0.8, .roughness = 0.2 },
});

// Rotated and scaled cylinder
_ = try commands.createEntityWith(.{
    Graphics.Cylinder3D{ .radius = 0.3, .height = 2.0 },
    Transform{ .x = -2.0, .y = 0, .z = 0 },
    Rotation{ .x = 0, .y = 0, .z = std.math.pi / 4.0 },  // 45° roll
    Scale{ .x = 1.0, .y = 2.0, .z = 1.0 },               // Stretch Y axis
    Color.blue,
});

// Animate camera
fn animateCamera(camera: ResourceMut(Graphics.Camera3D)) !void {
    camera.value.eye = .{ 5 * @cos(time), 3.0, 5 * @sin(time) };
}
```

## Shaders

**Unlit** - Simple vertex color, no lighting calculations
**Blinn-Phong** - Classic diffuse + specular lighting with ambient
**PBR** - Physically-based rendering with Cook-Torrance BRDF, GGX distribution, Fresnel-Schlick

## Known Limitations

1. **Normal Transformation with Non-Uniform Scale**: The shaders use `mat3(model) * normal` for normal transformation, which is only correct for uniform scale (equal X, Y, Z scaling). Non-uniform scaling causes incorrect lighting. For accurate lighting with non-uniform scale, use uniform scale or accept the visual artifacts.

2. **Per-Frame Geometry Rebuilding**: All 3D shapes are rebuilt into vertex/index buffers every frame. There is no static mesh caching. For large numbers of static objects, this may impact performance.

3. **Stack-Allocated Buffers**: 3D rendering uses ~2-3MB of stack-allocated vertex/index buffers. On WASM with default 5MB stack, this may cause overflow with complex scenes. Use `-Dstack-size=8` or higher for larger scenes.
