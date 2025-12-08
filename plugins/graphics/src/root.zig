const sparze = @import("sparze");
const SingleQuery = sparze.SingleQuery;
const Query = sparze.Query;
const Resource = sparze.Resource;
const ResourceMut = sparze.ResourceMut;
const sokol = @import("sokol");
const Pipeline = sokol.gfx.Pipeline;
pub const PassAction = sokol.gfx.PassAction;

const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Rotation = zenithor.Rotation;
const Scale = zenithor.Scale;
const Color = zenithor.Color;
const Stage = zenithor.Stage;
const SystemConfig = zenithor.SystemConfig;
const std = @import("std");
const builtin = @import("builtin");

// Shader imports
const pbr_shader = @import("pbr_shader");
const blinn_phong_shader = @import("blinn_phong_shader");
const unlit_shader = @import("unlit_shader");

const is_debug = builtin.mode == .Debug;

// =============================================================================
// 2D Shape Components
// =============================================================================

pub const Point = struct {};

pub const Line = struct {
    x: f32,
    y: f32,

    pub fn format(self: Line, writer: anytype) !void {
        try writer.print("Line(end: x: {d:.2}, y: {d:.2})", .{ self.x, self.y });
    }
};

pub const Triangle = struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    x3: f32,
    y3: f32,

    pub fn format(self: Triangle, writer: anytype) !void {
        try writer.print("Triangle(v1: ({d:.2}, {d:.2}), v2: ({d:.2}, {d:.2}), v3: ({d:.2}, {d:.2}))", .{
            self.x1, self.y1,
            self.x2, self.y2,
            self.x3, self.y3,
        });
    }
};

pub const Rectangle = struct {
    x: f32,
    y: f32,

    pub fn format(self: Rectangle, writer: anytype) !void {
        try writer.print("Rectangle(width: {d:.2}, height: {d:.2})", .{ self.x, self.y });
    }
};

pub const Circle = struct {
    radius: f32,
    segments: u32 = 32, // Number of segments to approximate the circle

    pub fn format(self: Circle, writer: anytype) !void {
        try writer.print("Circle(radius: {d:.2}, segments: {})", .{ self.radius, self.segments });
    }
};

// =============================================================================
// 3D Shape Components
// =============================================================================

pub const Plane3D = struct {
    width: f32 = 1.0,
    depth: f32 = 1.0,
    tiles: u16 = 1,

    pub fn format(self: Plane3D, writer: anytype) !void {
        try writer.print("Plane3D(width: {d:.2}, depth: {d:.2}, tiles: {})", .{ self.width, self.depth, self.tiles });
    }
};

pub const Box3D = struct {
    width: f32 = 1.0,
    height: f32 = 1.0,
    depth: f32 = 1.0,
    tiles: u16 = 1,

    pub fn format(self: Box3D, writer: anytype) !void {
        try writer.print("Box3D(w: {d:.2}, h: {d:.2}, d: {d:.2})", .{ self.width, self.height, self.depth });
    }
};

pub const Sphere3D = struct {
    radius: f32 = 0.5,
    slices: u16 = 16,
    stacks: u16 = 12,

    pub fn format(self: Sphere3D, writer: anytype) !void {
        try writer.print("Sphere3D(radius: {d:.2}, slices: {}, stacks: {})", .{ self.radius, self.slices, self.stacks });
    }
};

pub const Cylinder3D = struct {
    radius: f32 = 0.5,
    height: f32 = 1.0,
    slices: u16 = 16,
    stacks: u16 = 1,

    pub fn format(self: Cylinder3D, writer: anytype) !void {
        try writer.print("Cylinder3D(radius: {d:.2}, height: {d:.2})", .{ self.radius, self.height });
    }
};

pub const Torus3D = struct {
    radius: f32 = 0.5,
    ring_radius: f32 = 0.2,
    sides: u16 = 16,
    rings: u16 = 16,

    pub fn format(self: Torus3D, writer: anytype) !void {
        try writer.print("Torus3D(radius: {d:.2}, ring_radius: {d:.2})", .{ self.radius, self.ring_radius });
    }
};

// =============================================================================
// Shader Selection
// =============================================================================

pub const ShaderType = enum {
    unlit,
    blinn_phong,
    pbr,
};

/// Material component for shader selection and parameters
pub const Material = struct {
    shader: ShaderType = .blinn_phong,
    // Blinn-Phong parameters
    shininess: f32 = 32.0,
    specular_strength: f32 = 0.5,
    // PBR parameters
    metallic: f32 = 0.0,
    roughness: f32 = 0.5,

    pub fn format(self: Material, writer: anytype) !void {
        try writer.print("Material(shader: {s})", .{@tagName(self.shader)});
    }
};

// =============================================================================
// Resources
// =============================================================================

pub const RenderingOptions = struct {
    pass_action: PassAction = .{},
};

/// Camera for 3D rendering
pub const Camera3D = struct {
    // View parameters
    eye: [3]f32 = .{ 0, 2, 5 },
    target: [3]f32 = .{ 0, 0, 0 },
    up: [3]f32 = .{ 0, 1, 0 },
    // Projection parameters
    fov: f32 = 60.0, // degrees
    near: f32 = 0.1,
    far: f32 = 100.0,
};

/// Global lighting for 3D
pub const Light3D = struct {
    position: [3]f32 = .{ 5, 5, 5 },
    color: [3]f32 = .{ 1, 1, 1 },
    ambient_strength: f32 = 0.1,
};

/// Internal state for 3D rendering
pub const Render3DState = struct {
    // Pipelines for each shader type
    pipeline_unlit: Pipeline = .{},
    pipeline_blinn_phong: Pipeline = .{},
    pipeline_pbr: Pipeline = .{},
    // Shared vertex/index buffers
    vertex_buffer: sokol.gfx.Buffer = .{},
    index_buffer: sokol.gfx.Buffer = .{},
    // Current frame's element ranges for batched drawing
    draw_count: u32 = 0,
};

// =============================================================================
// Components and Resources exports
// =============================================================================

pub const Components = .{
    // 2D shapes
    Point,
    Line,
    Triangle,
    Rectangle,
    Circle,
    // 3D shapes
    Plane3D,
    Box3D,
    Sphere3D,
    Cylinder3D,
    Torus3D,
    // Material
    Material,
};

pub const Resources = .{
    RenderingOptions,
    Camera3D,
    Light3D,
    Render3DState,
};

pub const Events = .{};

// =============================================================================
// Matrix Math Utilities
// =============================================================================

const Mat4 = [4][4]f32;

fn identity() Mat4 {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

fn multiply(a: Mat4, b: Mat4) Mat4 {
    var result: Mat4 = undefined;
    inline for (0..4) |row| {
        inline for (0..4) |col| {
            var sum: f32 = 0;
            inline for (0..4) |k| {
                sum += a[row][k] * b[k][col];
            }
            result[row][col] = sum;
        }
    }
    return result;
}

fn translation(x: f32, y: f32, z: f32) Mat4 {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ x, y, z, 1 },
    };
}

fn scaling(x: f32, y: f32, z: f32) Mat4 {
    return .{
        .{ x, 0, 0, 0 },
        .{ 0, y, 0, 0 },
        .{ 0, 0, z, 0 },
        .{ 0, 0, 0, 1 },
    };
}

fn rotationX(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, c, s, 0 },
        .{ 0, -s, c, 0 },
        .{ 0, 0, 0, 1 },
    };
}

fn rotationY(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        .{ c, 0, -s, 0 },
        .{ 0, 1, 0, 0 },
        .{ s, 0, c, 0 },
        .{ 0, 0, 0, 1 },
    };
}

fn rotationZ(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        .{ c, s, 0, 0 },
        .{ -s, c, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

fn buildModelMatrix(pos: Transform, rot: ?Rotation, scl: ?Scale) Mat4 {
    var m = identity();

    // Scale
    if (scl) |s| {
        m = multiply(m, scaling(s.x, s.y, s.z));
    }

    // Rotation (ZYX order: roll, then yaw, then pitch)
    if (rot) |r| {
        m = multiply(m, rotationX(r.x));
        m = multiply(m, rotationY(r.y));
        m = multiply(m, rotationZ(r.z));
    }

    // Translation
    m = multiply(m, translation(pos.x, pos.y, pos.z));

    return m;
}

fn lookAt(eye: [3]f32, target: [3]f32, up: [3]f32) Mat4 {
    const f = normalize3(.{
        target[0] - eye[0],
        target[1] - eye[1],
        target[2] - eye[2],
    });
    const s = normalize3(cross3(f, up));
    const u = cross3(s, f);

    return .{
        .{ s[0], u[0], -f[0], 0 },
        .{ s[1], u[1], -f[1], 0 },
        .{ s[2], u[2], -f[2], 0 },
        .{ -dot3(s, eye), -dot3(u, eye), dot3(f, eye), 1 },
    };
}

fn perspective(fov_deg: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const fov_rad = fov_deg * std.math.pi / 180.0;
    const f = 1.0 / @tan(fov_rad / 2.0);
    const nf = 1.0 / (near - far);

    return .{
        .{ f / aspect, 0, 0, 0 },
        .{ 0, f, 0, 0 },
        .{ 0, 0, (far + near) * nf, -1 },
        .{ 0, 0, 2 * far * near * nf, 0 },
    };
}

fn normalize3(v: [3]f32) [3]f32 {
    const len = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (len == 0) return .{ 0, 0, 0 };
    return .{ v[0] / len, v[1] / len, v[2] / len };
}

fn cross3(a: [3]f32, b: [3]f32) [3]f32 {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

fn dot3(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

fn colorToU32(c: Color) u32 {
    return sokol.shape.color4f(c.r, c.g, c.b, c.a);
}

// =============================================================================
// Systems
// =============================================================================

fn init(commands: anytype) !void {
    // Initialize pass action (background color)
    var rendering_options = RenderingOptions{};
    rendering_options.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.2, .g = 0.2, .b = 0.3, .a = 1 },
    };
    rendering_options.pass_action.depth = .{
        .load_action = .CLEAR,
        .clear_value = 1.0,
    };
    commands.setResource(RenderingOptions, rendering_options);

    // Initialize 3D state
    var state = Render3DState{};

    // Common pipeline settings for 3D
    var layout = sokol.gfx.VertexLayoutState{};
    layout.buffers[0] = sokol.shape.vertexBufferLayoutState();
    layout.attrs[0] = sokol.shape.positionVertexAttrState();
    layout.attrs[1] = sokol.shape.normalVertexAttrState();
    layout.attrs[2] = sokol.shape.texcoordVertexAttrState();
    layout.attrs[3] = sokol.shape.colorVertexAttrState();

    const depth_state = sokol.gfx.DepthState{
        .write_enabled = true,
        .compare = .LESS_EQUAL,
    };

    // Create pipeline for unlit shader
    state.pipeline_unlit = sokol.gfx.makePipeline(.{
        .shader = sokol.gfx.makeShader(unlit_shader.unlitShaderDesc(sokol.gfx.queryBackend())),
        .layout = layout,
        .index_type = .UINT16,
        .cull_mode = .BACK,
        .depth = depth_state,
    });

    // Create pipeline for Blinn-Phong shader
    state.pipeline_blinn_phong = sokol.gfx.makePipeline(.{
        .shader = sokol.gfx.makeShader(blinn_phong_shader.blinnPhongShaderDesc(sokol.gfx.queryBackend())),
        .layout = layout,
        .index_type = .UINT16,
        .cull_mode = .BACK,
        .depth = depth_state,
    });

    // Create pipeline for PBR shader
    state.pipeline_pbr = sokol.gfx.makePipeline(.{
        .shader = sokol.gfx.makeShader(pbr_shader.pbrShaderDesc(sokol.gfx.queryBackend())),
        .layout = layout,
        .index_type = .UINT16,
        .cull_mode = .BACK,
        .depth = depth_state,
    });

    // Create dynamic vertex/index buffers
    const max_vertices = 65536;
    const max_indices = 262144;

    state.vertex_buffer = sokol.gfx.makeBuffer(.{
        .size = max_vertices * @sizeOf(sokol.shape.Vertex),
        .usage = .{ .vertex_buffer = true, .stream_update = true },
    });

    state.index_buffer = sokol.gfx.makeBuffer(.{
        .size = max_indices * @sizeOf(u16),
        .usage = .{ .index_buffer = true, .stream_update = true },
    });

    commands.setResource(Render3DState, state);
    commands.setResource(Camera3D, .{});
    commands.setResource(Light3D, .{});
}

fn setDefaults() !void {
    sokol.gl.defaults();
}

fn setup2d() !void {
    sokol.gl.matrixModeProjection();
    sokol.gl.ortho(0, sokol.app.widthf(), sokol.app.heightf(), 0, -1, 1);
}

// 2D drawing systems (unchanged)
fn drawPoint(points: Query(struct { Point, Transform, ?Color })) !void {
    sokol.gl.beginPoints();
    for (points.entities) |entity| {
        if (!points.filter(entity)) continue;
        if (points.getOptional(entity, Color)) |color| {
            sokol.gl.c4f(color.r, color.g, color.b, color.a);
        } else {
            sokol.gl.c4f(1.0, 0.0, 0.0, 1.0);
        }
        const transform = points.getComponentMut(entity, Transform);
        sokol.gl.v3f(transform.x, transform.y, transform.z);
    }
    sokol.gl.end();
}

fn drawLine(lines: Query(struct { Line, Transform, ?Color })) !void {
    sokol.gl.beginLines();
    for (lines.entities) |entity| {
        if (!lines.filter(entity)) continue;
        if (lines.getOptional(entity, Color)) |color| {
            sokol.gl.c4f(color.r, color.g, color.b, color.a);
        } else {
            sokol.gl.c4f(1.0, 0.0, 0.0, 1.0);
        }
        const transform = lines.getComponentMut(entity, Transform);
        const line = lines.getComponentMut(entity, Line);
        sokol.gl.v3f(transform.x, transform.y, transform.z);
        sokol.gl.v3f(transform.x + line.x, transform.y + line.y, transform.z);
    }
    sokol.gl.end();
}

fn drawTriangle(triangles: Query(struct { Triangle, Transform, ?Color })) !void {
    sokol.gl.beginTriangles();
    for (triangles.entities) |entity| {
        if (!triangles.filter(entity)) continue;
        if (triangles.getOptional(entity, Color)) |color| {
            sokol.gl.c4f(color.r, color.g, color.b, color.a);
        } else {
            sokol.gl.c4f(1.0, 0.0, 0.0, 1.0);
        }
        const transform = triangles.getComponentMut(entity, Transform);
        const triangle = triangles.getComponentMut(entity, Triangle);
        sokol.gl.v3f(transform.x + triangle.x1, transform.y + triangle.y1, transform.z);
        sokol.gl.v3f(transform.x + triangle.x2, transform.y + triangle.y2, transform.z);
        sokol.gl.v3f(transform.x + triangle.x3, transform.y + triangle.y3, transform.z);
    }
    sokol.gl.end();
}

fn drawRectangle(rectangles: Query(struct { Rectangle, Transform, ?Color })) !void {
    sokol.gl.beginQuads();
    for (rectangles.entities) |entity| {
        if (!rectangles.filter(entity)) continue;
        if (rectangles.getOptional(entity, Color)) |color| {
            sokol.gl.c4f(color.r, color.g, color.b, color.a);
        } else {
            sokol.gl.c4f(1.0, 0.0, 0.0, 1.0);
        }
        const transform = rectangles.getComponentMut(entity, Transform);
        const rectangle = rectangles.getComponentMut(entity, Rectangle);
        sokol.gl.v3f(transform.x, transform.y, transform.z);
        sokol.gl.v3f(transform.x + rectangle.x, transform.y, transform.z);
        sokol.gl.v3f(transform.x + rectangle.x, transform.y + rectangle.y, transform.z);
        sokol.gl.v3f(transform.x, transform.y + rectangle.y, transform.z);
    }
    sokol.gl.end();
}

fn drawCircle(circles: Query(struct { Circle, Transform, ?Color })) !void {
    sokol.gl.beginTriangles();
    for (circles.entities) |entity| {
        if (!circles.filter(entity)) continue;
        const transform = circles.getComponentMut(entity, Transform);
        const circle = circles.getComponentMut(entity, Circle);

        if (circles.getOptional(entity, Color)) |color| {
            sokol.gl.c4f(color.r, color.g, color.b, color.a);
        } else {
            sokol.gl.c4f(1.0, 0.0, 0.0, 1.0);
        }

        // Draw circle as triangle fan
        if (circle.segments == 0) {
            if (is_debug) {
                @panic("Circle.segments must be at least 1 to avoid division by zero");
            }
            continue;
        }
        const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(circle.segments));

        for (0..circle.segments) |i| {
            const angle1 = @as(f32, @floatFromInt(i)) * angle_step;
            const angle2 = @as(f32, @floatFromInt(i + 1)) * angle_step;

            const x1 = transform.x + circle.radius * @cos(angle1);
            const y1 = transform.y + circle.radius * @sin(angle1);
            const x2 = transform.x + circle.radius * @cos(angle2);
            const y2 = transform.y + circle.radius * @sin(angle2);

            // Triangle from center to two consecutive points on circumference
            sokol.gl.v3f(transform.x, transform.y, transform.z); // Center
            sokol.gl.v3f(x1, y1, transform.z); // Point 1 on circumference
            sokol.gl.v3f(x2, y2, transform.z); // Point 2 on circumference
        }
    }
    sokol.gl.end();
}

// =============================================================================
// 3D Drawing System
// =============================================================================

const DrawCommand = struct {
    base_element: u32,
    num_elements: u32,
    model: Mat4,
    mvp: Mat4,
    color: Color,
    material: Material,
};

fn draw3D(
    boxes: Query(struct { Box3D, Transform, ?Color, ?Material }),
    spheres: Query(struct { Sphere3D, Transform, ?Color, ?Material }),
    cylinders: Query(struct { Cylinder3D, Transform, ?Color, ?Material }),
    tori: Query(struct { Torus3D, Transform, ?Color, ?Material }),
    planes: Query(struct { Plane3D, Transform, ?Color, ?Material }),
    camera: Resource(Camera3D),
    light: Resource(Light3D),
    state: ResourceMut(Render3DState),
    options: Resource(RenderingOptions),
    // Commands for Rotation/Scale lookup (avoids comptime branch quota explosion from adding
    // ?Rotation/?Scale to each shape query - would exceed Zig's 3000 branch limit)
    commands: anytype,
) !void {
    // Access sparse sets for Rotation/Scale lookups
    const rotation_set = commands.getSparseSetPtr(Rotation);
    const scale_set = commands.getSparseSetPtr(Scale);
    // Static buffers for shape generation
    const max_vertices = 65536;
    const max_indices = 262144;
    var vertices: [max_vertices]sokol.shape.Vertex = undefined;
    var indices: [max_indices]u16 = undefined;

    var buf = sokol.shape.Buffer{
        .vertices = .{ .buffer = sokol.shape.asRange(&vertices) },
        .indices = .{ .buffer = sokol.shape.asRange(&indices) },
    };

    // Draw command lists per shader type
    const max_commands = 256;
    var unlit_commands: [max_commands]DrawCommand = undefined;
    var unlit_count: usize = 0;
    var blinn_commands: [max_commands]DrawCommand = undefined;
    var blinn_count: usize = 0;
    var pbr_commands: [max_commands]DrawCommand = undefined;
    var pbr_count: usize = 0;

    // Calculate view-projection matrix
    // Note: Mat4/multiply use row-major convention. When sent to column-major GLSL shaders,
    // the implicit transpose means row-major (model * view * proj) becomes column-major (proj * view * model).
    const aspect = sokol.app.widthf() / sokol.app.heightf();
    const view = lookAt(camera.value.eye, camera.value.target, camera.value.up);
    const proj = perspective(camera.value.fov, aspect, camera.value.near, camera.value.far);
    const vp = multiply(view, proj);

    // Helper to add draw command with overflow check
    const addCommand = struct {
        fn add(
            draw_commands: *[max_commands]DrawCommand,
            count: *usize,
            cmd: DrawCommand,
        ) void {
            if (count.* >= max_commands) {
                if (is_debug) @panic("Too many draw commands for shader type");
                return; // Skip in release mode
            }
            draw_commands[count.*] = cmd;
            count.* += 1;
        }
    }.add;

    // Process Box3D entities
    for (boxes.entities) |entity| {
        if (!boxes.filter(entity)) continue;
        const box = boxes.getComponent(entity, Box3D);
        const transform = boxes.getComponent(entity, Transform);
        // Fetch Rotation/Scale via sparse set lookup (avoids comptime branch quota explosion)
        const rot = rotation_set.get(entity);
        const scl = scale_set.get(entity);
        const color = boxes.getOptional(entity, Color) orelse Color.white;
        const material = boxes.getOptional(entity, Material) orelse Material{};

        const model = buildModelMatrix(transform, rot, scl);

        // Check buffer capacity before building shape
        if (buf.vertices.data_size >= max_vertices * @sizeOf(sokol.shape.Vertex) - 1024 or
            buf.indices.data_size >= max_indices * @sizeOf(u16) - 1024)
        {
            if (is_debug) @panic("Vertex/index buffer overflow");
            break; // Skip remaining shapes in release mode
        }

        buf = sokol.shape.buildBox(buf, .{
            .width = box.width,
            .height = box.height,
            .depth = box.depth,
            .tiles = box.tiles,
            .color = colorToU32(color),
        });

        const range = sokol.shape.elementRange(buf);
        const cmd = DrawCommand{
            .base_element = range.base_element,
            .num_elements = range.num_elements,
            .model = model,
            .mvp = multiply(model, vp),
            .color = color,
            .material = material,
        };

        switch (material.shader) {
            .unlit => addCommand(&unlit_commands, &unlit_count, cmd),
            .blinn_phong => addCommand(&blinn_commands, &blinn_count, cmd),
            .pbr => addCommand(&pbr_commands, &pbr_count, cmd),
        }
    }

    // Process Sphere3D entities
    for (spheres.entities) |entity| {
        if (!spheres.filter(entity)) continue;
        const sphere = spheres.getComponent(entity, Sphere3D);
        const transform = spheres.getComponent(entity, Transform);
        const rot = rotation_set.get(entity);
        const scl = scale_set.get(entity);
        const color = spheres.getOptional(entity, Color) orelse Color.white;
        const material = spheres.getOptional(entity, Material) orelse Material{};

        const model = buildModelMatrix(transform, rot, scl);

        // Check buffer capacity
        if (buf.vertices.data_size >= max_vertices * @sizeOf(sokol.shape.Vertex) - 4096 or
            buf.indices.data_size >= max_indices * @sizeOf(u16) - 4096)
        {
            if (is_debug) @panic("Vertex/index buffer overflow");
            break;
        }

        buf = sokol.shape.buildSphere(buf, .{
            .radius = sphere.radius,
            .slices = sphere.slices,
            .stacks = sphere.stacks,
            .color = colorToU32(color),
        });

        const range = sokol.shape.elementRange(buf);
        const cmd = DrawCommand{
            .base_element = range.base_element,
            .num_elements = range.num_elements,
            .model = model,
            .mvp = multiply(model, vp),
            .color = color,
            .material = material,
        };

        switch (material.shader) {
            .unlit => addCommand(&unlit_commands, &unlit_count, cmd),
            .blinn_phong => addCommand(&blinn_commands, &blinn_count, cmd),
            .pbr => addCommand(&pbr_commands, &pbr_count, cmd),
        }
    }

    // Process Cylinder3D entities
    for (cylinders.entities) |entity| {
        if (!cylinders.filter(entity)) continue;
        const cylinder = cylinders.getComponent(entity, Cylinder3D);
        const transform = cylinders.getComponent(entity, Transform);
        const rot = rotation_set.get(entity);
        const scl = scale_set.get(entity);
        const color = cylinders.getOptional(entity, Color) orelse Color.white;
        const material = cylinders.getOptional(entity, Material) orelse Material{};

        const model = buildModelMatrix(transform, rot, scl);

        // Check buffer capacity
        if (buf.vertices.data_size >= max_vertices * @sizeOf(sokol.shape.Vertex) - 2048 or
            buf.indices.data_size >= max_indices * @sizeOf(u16) - 2048)
        {
            if (is_debug) @panic("Vertex/index buffer overflow");
            break;
        }

        buf = sokol.shape.buildCylinder(buf, .{
            .radius = cylinder.radius,
            .height = cylinder.height,
            .slices = cylinder.slices,
            .stacks = cylinder.stacks,
            .color = colorToU32(color),
        });

        const range = sokol.shape.elementRange(buf);
        const cmd = DrawCommand{
            .base_element = range.base_element,
            .num_elements = range.num_elements,
            .model = model,
            .mvp = multiply(model, vp),
            .color = color,
            .material = material,
        };

        switch (material.shader) {
            .unlit => addCommand(&unlit_commands, &unlit_count, cmd),
            .blinn_phong => addCommand(&blinn_commands, &blinn_count, cmd),
            .pbr => addCommand(&pbr_commands, &pbr_count, cmd),
        }
    }

    // Process Torus3D entities
    for (tori.entities) |entity| {
        if (!tori.filter(entity)) continue;
        const torus = tori.getComponent(entity, Torus3D);
        const transform = tori.getComponent(entity, Transform);
        const rot = rotation_set.get(entity);
        const scl = scale_set.get(entity);
        const color = tori.getOptional(entity, Color) orelse Color.white;
        const material = tori.getOptional(entity, Material) orelse Material{};

        const model = buildModelMatrix(transform, rot, scl);

        // Check buffer capacity
        if (buf.vertices.data_size >= max_vertices * @sizeOf(sokol.shape.Vertex) - 4096 or
            buf.indices.data_size >= max_indices * @sizeOf(u16) - 4096)
        {
            if (is_debug) @panic("Vertex/index buffer overflow");
            break;
        }

        buf = sokol.shape.buildTorus(buf, .{
            .radius = torus.radius,
            .ring_radius = torus.ring_radius,
            .sides = torus.sides,
            .rings = torus.rings,
            .color = colorToU32(color),
        });

        const range = sokol.shape.elementRange(buf);
        const cmd = DrawCommand{
            .base_element = range.base_element,
            .num_elements = range.num_elements,
            .model = model,
            .mvp = multiply(model, vp),
            .color = color,
            .material = material,
        };

        switch (material.shader) {
            .unlit => addCommand(&unlit_commands, &unlit_count, cmd),
            .blinn_phong => addCommand(&blinn_commands, &blinn_count, cmd),
            .pbr => addCommand(&pbr_commands, &pbr_count, cmd),
        }
    }

    // Process Plane3D entities
    for (planes.entities) |entity| {
        if (!planes.filter(entity)) continue;
        const plane = planes.getComponent(entity, Plane3D);
        const transform = planes.getComponent(entity, Transform);
        const rot = rotation_set.get(entity);
        const scl = scale_set.get(entity);
        const color = planes.getOptional(entity, Color) orelse Color.white;
        const material = planes.getOptional(entity, Material) orelse Material{};

        const model = buildModelMatrix(transform, rot, scl);

        // Check buffer capacity
        if (buf.vertices.data_size >= max_vertices * @sizeOf(sokol.shape.Vertex) - 1024 or
            buf.indices.data_size >= max_indices * @sizeOf(u16) - 1024)
        {
            if (is_debug) @panic("Vertex/index buffer overflow");
            break;
        }

        buf = sokol.shape.buildPlane(buf, .{
            .width = plane.width,
            .depth = plane.depth,
            .tiles = plane.tiles,
            .color = colorToU32(color),
        });

        const range = sokol.shape.elementRange(buf);
        const cmd = DrawCommand{
            .base_element = range.base_element,
            .num_elements = range.num_elements,
            .model = model,
            .mvp = multiply(model, vp),
            .color = color,
            .material = material,
        };

        switch (material.shader) {
            .unlit => addCommand(&unlit_commands, &unlit_count, cmd),
            .blinn_phong => addCommand(&blinn_commands, &blinn_count, cmd),
            .pbr => addCommand(&pbr_commands, &pbr_count, cmd),
        }
    }

    // Total count for statistics
    const total_count = unlit_count + blinn_count + pbr_count;

    // Always begin the render pass (even with no 3D objects, for 2D rendering)
    sokol.gfx.beginPass(.{
        .action = options.value.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });

    // Only upload and draw if we have 3D objects
    if (total_count > 0) {
        // Upload vertex/index data to GPU
        sokol.gfx.updateBuffer(state.value.vertex_buffer, .{
            .ptr = &vertices,
            .size = buf.vertices.data_size,
        });
        sokol.gfx.updateBuffer(state.value.index_buffer, .{
            .ptr = &indices,
            .size = buf.indices.data_size,
        });

        // Setup bindings
        var bindings = sokol.gfx.Bindings{};
        bindings.vertex_buffers[0] = state.value.vertex_buffer;
        bindings.index_buffer = state.value.index_buffer;

        // Draw unlit objects
        if (unlit_count > 0) {
            sokol.gfx.applyPipeline(state.value.pipeline_unlit);
            sokol.gfx.applyBindings(bindings);

            for (unlit_commands[0..unlit_count]) |cmd| {
                sokol.gfx.applyUniforms(0, sokol.gfx.asRange(&unlit_shader.VsParams{
                    .mvp = cmd.mvp,
                }));
                sokol.gfx.draw(cmd.base_element, cmd.num_elements, 1);
            }
        }

        // Draw Blinn-Phong objects
        if (blinn_count > 0) {
            sokol.gfx.applyPipeline(state.value.pipeline_blinn_phong);
            sokol.gfx.applyBindings(bindings);

            for (blinn_commands[0..blinn_count]) |cmd| {
                sokol.gfx.applyUniforms(0, sokol.gfx.asRange(&blinn_phong_shader.VsParams{
                    .mvp = cmd.mvp,
                    .model = cmd.model,
                }));
                sokol.gfx.applyUniforms(1, sokol.gfx.asRange(&blinn_phong_shader.FsParams{
                    .light_pos = light.value.position,
                    ._pad0 = 0,
                    .view_pos = camera.value.eye,
                    .shininess = cmd.material.shininess,
                    .light_color = light.value.color,
                    .ambient_strength = light.value.ambient_strength,
                    .specular_strength = cmd.material.specular_strength,
                    ._pad1 = 0,
                    ._pad2 = 0,
                    ._pad3 = 0,
                }));
                sokol.gfx.draw(cmd.base_element, cmd.num_elements, 1);
            }
        }

        // Draw PBR objects
        if (pbr_count > 0) {
            sokol.gfx.applyPipeline(state.value.pipeline_pbr);
            sokol.gfx.applyBindings(bindings);

            for (pbr_commands[0..pbr_count]) |cmd| {
                sokol.gfx.applyUniforms(0, sokol.gfx.asRange(&pbr_shader.VsParams{
                    .mvp = cmd.mvp,
                    .model = cmd.model,
                }));
                sokol.gfx.applyUniforms(1, sokol.gfx.asRange(&pbr_shader.FsParams{
                    .light_pos = light.value.position,
                    ._pad0 = 0,
                    .view_pos = camera.value.eye,
                    .metallic = cmd.material.metallic,
                    .light_color = light.value.color,
                    .roughness = cmd.material.roughness,
                    .ambient_strength = light.value.ambient_strength,
                    ._pad1 = 0,
                    ._pad2 = 0,
                    ._pad3 = 0,
                }));
                sokol.gfx.draw(cmd.base_element, cmd.num_elements, 1);
            }
        }
    }

    // Draw sokol.gl content (2D)
    sokol.gl.draw();

    sokol.gfx.endPass();
    sokol.gfx.commit();

    state.value.draw_count = @intCast(total_count);
}

fn cleanup(state: Resource(Render3DState)) !void {
    // Destroy GPU resources to prevent memory corruption on shutdown
    const s = state.value;
    if (s.vertex_buffer.id != 0) sokol.gfx.destroyBuffer(s.vertex_buffer);
    if (s.index_buffer.id != 0) sokol.gfx.destroyBuffer(s.index_buffer);
    if (s.pipeline_unlit.id != 0) sokol.gfx.destroyPipeline(s.pipeline_unlit);
    if (s.pipeline_blinn_phong.id != 0) sokol.gfx.destroyPipeline(s.pipeline_blinn_phong);
    if (s.pipeline_pbr.id != 0) sokol.gfx.destroyPipeline(s.pipeline_pbr);
}

// Declarative system registration
pub const systems = .{
    .startup = &.{
        .{ .system = init, .stage = .first },
    },
    .main = &.{
        .{ .system = setDefaults, .stage = .pre_render },
        .{ .system = setup2d, .stage = .pre_render },
        .{ .system = drawPoint, .stage = .render },
        .{ .system = drawLine, .stage = .render },
        .{ .system = drawTriangle, .stage = .render },
        .{ .system = drawRectangle, .stage = .render },
        .{ .system = drawCircle, .stage = .render },
        // 3D drawing (includes pass management)
        .{ .system = draw3D, .stage = .render_submit, .config = .{ .tags = &.{"3d-render"} } },
    },
    .terminate = &.{
        .{ .system = cleanup, .stage = .first },
    },
};
