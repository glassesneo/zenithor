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
// Constants
// =============================================================================

/// Maximum vertices for 3D staging buffer
const MAX_3D_VERTICES = 65536;
/// Maximum indices for 3D staging buffer
const MAX_3D_INDICES = 262144;

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
    // Skip serialization (runtime-only GPU state)
    pub const serialized = false;

    // Shaders for each type
    shader_unlit: sokol.gfx.Shader = .{},
    shader_blinn_phong: sokol.gfx.Shader = .{},
    shader_pbr: sokol.gfx.Shader = .{},
    // Pipelines for each shader type
    pipeline_unlit: Pipeline = .{},
    pipeline_blinn_phong: Pipeline = .{},
    pipeline_pbr: Pipeline = .{},
    // GPU buffers (vertex/index)
    vertex_buffer: sokol.gfx.Buffer = .{},
    index_buffer: sokol.gfx.Buffer = .{},
    // Heap-allocated staging buffers for per-frame geometry building
    vertices: []sokol.shape.Vertex = &.{},
    indices: []u16 = &.{},
    allocator: ?std.mem.Allocator = null,
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

fn init(commands: anytype, allocator: std.mem.Allocator) !void {
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

    // Initialize 3D resources eagerly (not lazily)
    var state = Render3DState{};
    state.allocator = allocator;
    try init3DResources(&state);

    commands.setResource(Render3DState, state);
    commands.setResource(Camera3D, .{});
    commands.setResource(Light3D, .{});
}

/// Initialize 3D resources (shaders, pipelines, buffers).
/// Called by init() during application startup.
fn init3DResources(state: *Render3DState) !void {
    // Allocate heap buffers for per-frame geometry building (replaces stack allocation)
    const allocator = state.allocator orelse return error.AllocatorNotSet;
    state.vertices = try allocator.alloc(sokol.shape.Vertex, MAX_3D_VERTICES);
    errdefer allocator.free(state.vertices);
    state.indices = try allocator.alloc(u16, MAX_3D_INDICES);
    errdefer allocator.free(state.indices);

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

    // Create shaders and pipelines for unlit shader
    state.shader_unlit = sokol.gfx.makeShader(unlit_shader.unlitShaderDesc(sokol.gfx.queryBackend()));
    errdefer sokol.gfx.destroyShader(state.shader_unlit);
    state.pipeline_unlit = sokol.gfx.makePipeline(.{
        .shader = state.shader_unlit,
        .layout = layout,
        .index_type = .UINT16,
        .cull_mode = .BACK,
        .depth = depth_state,
    });
    errdefer sokol.gfx.destroyPipeline(state.pipeline_unlit);

    // Create shaders and pipelines for Blinn-Phong shader
    state.shader_blinn_phong = sokol.gfx.makeShader(blinn_phong_shader.blinnPhongShaderDesc(sokol.gfx.queryBackend()));
    errdefer sokol.gfx.destroyShader(state.shader_blinn_phong);
    state.pipeline_blinn_phong = sokol.gfx.makePipeline(.{
        .shader = state.shader_blinn_phong,
        .layout = layout,
        .index_type = .UINT16,
        .cull_mode = .BACK,
        .depth = depth_state,
    });
    errdefer sokol.gfx.destroyPipeline(state.pipeline_blinn_phong);

    // Create shaders and pipelines for PBR shader
    state.shader_pbr = sokol.gfx.makeShader(pbr_shader.pbrShaderDesc(sokol.gfx.queryBackend()));
    errdefer sokol.gfx.destroyShader(state.shader_pbr);
    state.pipeline_pbr = sokol.gfx.makePipeline(.{
        .shader = state.shader_pbr,
        .layout = layout,
        .index_type = .UINT16,
        .cull_mode = .BACK,
        .depth = depth_state,
    });
    errdefer sokol.gfx.destroyPipeline(state.pipeline_pbr);

    // Create GPU vertex/index buffers
    state.vertex_buffer = sokol.gfx.makeBuffer(.{
        .size = MAX_3D_VERTICES * @sizeOf(sokol.shape.Vertex),
        .usage = .{ .vertex_buffer = true, .stream_update = true },
    });
    errdefer sokol.gfx.destroyBuffer(state.vertex_buffer);

    state.index_buffer = sokol.gfx.makeBuffer(.{
        .size = MAX_3D_INDICES * @sizeOf(u16),
        .usage = .{ .index_buffer = true, .stream_update = true },
    });
    errdefer sokol.gfx.destroyBuffer(state.index_buffer);
}

fn setDefaults() void {
    sokol.gl.defaults();
}

fn setup2d() void {
    sokol.gl.matrixModeProjection();
    sokol.gl.ortho(0, sokol.app.widthf(), sokol.app.heightf(), 0, -1, 1);
}

// 2D drawing systems (unchanged)
fn drawPoint(points: Query(struct { Point, Transform, ?Color })) void {
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

fn drawLine(lines: Query(struct { Line, Transform, ?Color })) void {
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

fn drawTriangle(triangles: Query(struct { Triangle, Transform, ?Color })) void {
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

fn drawRectangle(rectangles: Query(struct { Rectangle, Transform, ?Color })) void {
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

fn drawCircle(circles: Query(struct { Circle, Transform, ?Color })) void {
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

/// Command buckets for batching draw calls by shader type
const CommandBuckets = struct {
    const max_commands = 1024;

    unlit: [max_commands]DrawCommand = undefined,
    unlit_count: usize = 0,
    blinn: [max_commands]DrawCommand = undefined,
    blinn_count: usize = 0,
    pbr: [max_commands]DrawCommand = undefined,
    pbr_count: usize = 0,

    fn add(self: *CommandBuckets, shader: ShaderType, cmd: DrawCommand) void {
        switch (shader) {
            .unlit => {
                if (self.unlit_count >= max_commands) {
                    if (is_debug) @panic("Too many unlit draw commands");
                    return;
                }
                self.unlit[self.unlit_count] = cmd;
                self.unlit_count += 1;
            },
            .blinn_phong => {
                if (self.blinn_count >= max_commands) {
                    if (is_debug) @panic("Too many blinn_phong draw commands");
                    return;
                }
                self.blinn[self.blinn_count] = cmd;
                self.blinn_count += 1;
            },
            .pbr => {
                if (self.pbr_count >= max_commands) {
                    if (is_debug) @panic("Too many pbr draw commands");
                    return;
                }
                self.pbr[self.pbr_count] = cmd;
                self.pbr_count += 1;
            },
        }
    }

    fn total(self: *const CommandBuckets) usize {
        return self.unlit_count + self.blinn_count + self.pbr_count;
    }
};

/// Check if buffer has capacity for more geometry (with 4KB safety margin)
fn checkBufferCapacity(buf: sokol.shape.Buffer, max_vertices: usize, max_indices: usize) bool {
    const vertex_limit = max_vertices * @sizeOf(sokol.shape.Vertex) - 4096;
    const index_limit = max_indices * @sizeOf(u16) - 4096;
    if (buf.vertices.data_size >= vertex_limit or buf.indices.data_size >= index_limit) {
        if (is_debug) @panic("Vertex/index buffer overflow");
        return false;
    }
    return true;
}

/// Draw all commands in the unlit bucket
fn drawUnlitBucket(
    cmds: []const DrawCommand,
    pip: Pipeline,
    bindings: sokol.gfx.Bindings,
) void {
    if (cmds.len == 0) return;
    sokol.gfx.applyPipeline(pip);
    sokol.gfx.applyBindings(bindings);
    for (cmds) |cmd| {
        sokol.gfx.applyUniforms(0, sokol.gfx.asRange(&unlit_shader.VsParams{
            .mvp = cmd.mvp,
        }));
        sokol.gfx.draw(cmd.base_element, cmd.num_elements, 1);
    }
}

/// Draw all commands in the Blinn-Phong bucket
fn drawBlinnPhongBucket(
    cmds: []const DrawCommand,
    pip: Pipeline,
    bindings: sokol.gfx.Bindings,
    light: Light3D,
    camera: Camera3D,
) void {
    if (cmds.len == 0) return;
    sokol.gfx.applyPipeline(pip);
    sokol.gfx.applyBindings(bindings);
    for (cmds) |cmd| {
        sokol.gfx.applyUniforms(0, sokol.gfx.asRange(&blinn_phong_shader.VsParams{
            .mvp = cmd.mvp,
            .model = cmd.model,
        }));
        sokol.gfx.applyUniforms(1, sokol.gfx.asRange(&blinn_phong_shader.FsParams{
            .light_pos = light.position,
            ._pad0 = 0,
            .view_pos = camera.eye,
            .shininess = cmd.material.shininess,
            .light_color = light.color,
            .ambient_strength = light.ambient_strength,
            .specular_strength = cmd.material.specular_strength,
            ._pad1 = 0,
            ._pad2 = 0,
            ._pad3 = 0,
        }));
        sokol.gfx.draw(cmd.base_element, cmd.num_elements, 1);
    }
}

/// Draw all commands in the PBR bucket
fn drawPbrBucket(
    cmds: []const DrawCommand,
    pip: Pipeline,
    bindings: sokol.gfx.Bindings,
    light: Light3D,
    camera: Camera3D,
) void {
    if (cmds.len == 0) return;
    sokol.gfx.applyPipeline(pip);
    sokol.gfx.applyBindings(bindings);
    for (cmds) |cmd| {
        sokol.gfx.applyUniforms(0, sokol.gfx.asRange(&pbr_shader.VsParams{
            .mvp = cmd.mvp,
            .model = cmd.model,
        }));
        sokol.gfx.applyUniforms(1, sokol.gfx.asRange(&pbr_shader.FsParams{
            .light_pos = light.position,
            ._pad0 = 0,
            .view_pos = camera.eye,
            .metallic = cmd.material.metallic,
            .light_color = light.color,
            .roughness = cmd.material.roughness,
            .ambient_strength = light.ambient_strength,
            ._pad1 = 0,
            ._pad2 = 0,
            ._pad3 = 0,
        }));
        sokol.gfx.draw(cmd.base_element, cmd.num_elements, 1);
    }
}

fn beginPass(options: Resource(RenderingOptions)) void {
    sokol.gfx.beginPass(.{
        .action = options.value.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
}

fn draw3D(
    boxes: Query(struct { Box3D, Transform, ?Color, ?Material }),
    spheres: Query(struct { Sphere3D, Transform, ?Color, ?Material }),
    cylinders: Query(struct { Cylinder3D, Transform, ?Color, ?Material }),
    tori: Query(struct { Torus3D, Transform, ?Color, ?Material }),
    planes: Query(struct { Plane3D, Transform, ?Color, ?Material }),
    camera: Resource(Camera3D),
    light: Resource(Light3D),
    state: ResourceMut(Render3DState),
    // Commands for Rotation/Scale lookup (avoids comptime branch quota explosion from adding
    // ?Rotation/?Scale to each shape query - would exceed Zig's 3000 branch limit)
    commands: anytype,
) !void {
    // Access sparse sets for Rotation/Scale lookups
    const rotation_set = commands.getSparseSetPtr(Rotation);
    const scale_set = commands.getSparseSetPtr(Scale);

    // Use heap-allocated staging buffers from state (no stack allocation)
    var buf = sokol.shape.Buffer{
        .vertices = .{ .buffer = sokol.shape.asRange(state.value.vertices) },
        .indices = .{ .buffer = sokol.shape.asRange(state.value.indices) },
    };

    // Derive capacity from actual slice lengths to ensure consistency
    const max_vertices: usize = state.value.vertices.len;
    const max_indices: usize = state.value.indices.len;

    // Command buckets for batching draw calls by shader type
    var buckets = CommandBuckets{};

    // Calculate view-projection matrix
    // Note: Mat4/multiply use row-major convention. When sent to column-major GLSL shaders,
    // the implicit transpose means row-major (model * view * proj) becomes column-major (proj * view * model).
    const aspect = sokol.app.widthf() / sokol.app.heightf();
    const view = lookAt(camera.value.eye, camera.value.target, camera.value.up);
    const proj = perspective(camera.value.fov, aspect, camera.value.near, camera.value.far);
    const vp = multiply(view, proj);

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
        if (!checkBufferCapacity(buf, max_vertices, max_indices)) break;

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

        buckets.add(material.shader, cmd);
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

        // Check buffer capacity before building shape
        if (!checkBufferCapacity(buf, max_vertices, max_indices)) break;

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

        buckets.add(material.shader, cmd);
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

        // Check buffer capacity before building shape
        if (!checkBufferCapacity(buf, max_vertices, max_indices)) break;

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

        buckets.add(material.shader, cmd);
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

        // Check buffer capacity before building shape
        if (!checkBufferCapacity(buf, max_vertices, max_indices)) break;

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

        buckets.add(material.shader, cmd);
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

        // Check buffer capacity before building shape
        if (!checkBufferCapacity(buf, max_vertices, max_indices)) break;

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

        buckets.add(material.shader, cmd);
    }

    // Total count for statistics
    const total_count = buckets.total();

    // Only upload and draw if we have 3D objects
    if (total_count > 0) {
        // Upload vertex/index data to GPU
        sokol.gfx.updateBuffer(state.value.vertex_buffer, .{
            .ptr = state.value.vertices.ptr,
            .size = buf.vertices.data_size,
        });
        sokol.gfx.updateBuffer(state.value.index_buffer, .{
            .ptr = state.value.indices.ptr,
            .size = buf.indices.data_size,
        });

        // Setup bindings
        var bindings = sokol.gfx.Bindings{};
        bindings.vertex_buffers[0] = state.value.vertex_buffer;
        bindings.index_buffer = state.value.index_buffer;

        // Draw each shader bucket using helper functions
        drawUnlitBucket(buckets.unlit[0..buckets.unlit_count], state.value.pipeline_unlit, bindings);
        drawBlinnPhongBucket(buckets.blinn[0..buckets.blinn_count], state.value.pipeline_blinn_phong, bindings, light.value.*, camera.value.*);
        drawPbrBucket(buckets.pbr[0..buckets.pbr_count], state.value.pipeline_pbr, bindings, light.value.*, camera.value.*);
    }

    state.value.draw_count = @intCast(total_count);
}

fn draw2D() void {
    // Draw sokol.gl content (2D)
    // All the 2D rendering commands recorded (drawTriangle, drawCircle) are executed here
    sokol.gl.draw();
}

fn endPass() void {
    sokol.gfx.endPass();
}

fn commit() void {
    sokol.gfx.commit();
}

fn cleanup(state: ResourceMut(Render3DState)) void {
    // Free heap-allocated staging buffers
    if (state.value.allocator) |allocator| {
        if (state.value.vertices.len > 0) allocator.free(state.value.vertices);
        if (state.value.indices.len > 0) allocator.free(state.value.indices);
    }

    // Destroy GPU resources to prevent memory corruption on shutdown
    // Note: Pipelines must be destroyed before shaders they reference
    if (state.value.vertex_buffer.id != 0) sokol.gfx.destroyBuffer(state.value.vertex_buffer);
    if (state.value.index_buffer.id != 0) sokol.gfx.destroyBuffer(state.value.index_buffer);
    if (state.value.pipeline_unlit.id != 0) sokol.gfx.destroyPipeline(state.value.pipeline_unlit);
    if (state.value.pipeline_blinn_phong.id != 0) sokol.gfx.destroyPipeline(state.value.pipeline_blinn_phong);
    if (state.value.pipeline_pbr.id != 0) sokol.gfx.destroyPipeline(state.value.pipeline_pbr);
    if (state.value.shader_unlit.id != 0) sokol.gfx.destroyShader(state.value.shader_unlit);
    if (state.value.shader_blinn_phong.id != 0) sokol.gfx.destroyShader(state.value.shader_blinn_phong);
    if (state.value.shader_pbr.id != 0) sokol.gfx.destroyShader(state.value.shader_pbr);

    // Zero out all fields to prevent accidental reuse or double-free
    state.value.vertices = &.{};
    state.value.indices = &.{};
    state.value.allocator = null;
    state.value.vertex_buffer = .{};
    state.value.index_buffer = .{};
    state.value.pipeline_unlit = .{};
    state.value.pipeline_blinn_phong = .{};
    state.value.pipeline_pbr = .{};
    state.value.shader_unlit = .{};
    state.value.shader_blinn_phong = .{};
    state.value.shader_pbr = .{};
    state.value.draw_count = 0;
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
        .{ .system = beginPass, .stage = .render },
        .{ .system = draw3D, .stage = .render_submit, .config = .{ .tags = &.{"3d-render"} } },
        .{ .system = draw2D, .stage = .render_submit, .config = .{ .tags = &.{"2d-render"} } },
        .{ .system = endPass, .stage = .post_render },
        .{ .system = commit, .stage = .post_render, .config = .{} },
    },
    .terminate = &.{
        .{ .system = cleanup, .stage = .first },
    },
};
