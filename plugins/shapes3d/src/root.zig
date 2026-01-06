const sparze = @import("sparze");
const Query = sparze.Query;
const Resource = sparze.Resource;
const ResourceMut = sparze.ResourceMut;
const sokol = @import("sokol");

const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Rotation = zenithor.Rotation;
const Scale = zenithor.Scale;
const Color = zenithor.Color;
const Stage = zenithor.Stage;
const std = @import("std");
const builtin = @import("builtin");
const RendererPlugin = @import("renderer_plugin");

// Shader spec imports
const UnlitShader = @import("shaders/unlit.zig");
const BlinnPhongShader = @import("shaders/blinn_phong.zig");
const PbrShader = @import("shaders/pbr.zig");

// Shared types
pub const types = @import("types.zig");
pub const VsUniformParams = types.VsUniformParams;
pub const FsUniformParams = types.FsUniformParams;

const is_debug = builtin.mode == .Debug;

// =============================================================================
// Constants
// =============================================================================

/// Maximum vertices for 3D staging buffer
const MAX_3D_VERTICES = 65536;
/// Maximum indices for 3D staging buffer
const MAX_3D_INDICES = 262144;

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
// Shader Registry
// =============================================================================

/// Entry for a registered shader (built-in or custom)
pub const ShaderEntry = struct {
    name: []const u8,
    shader: sokol.gfx.Shader,
    pipeline: sokol.gfx.Pipeline,
    applyVsUniforms: *const fn (params: VsUniformParams) void,
    applyFsUniforms: *const fn (params: FsUniformParams) void,
};

/// Registry of all available shaders (built-in and custom)
/// Replaces the old Render3DShaders resource with a unified system.
pub const ShaderRegistry = struct {
    pub const serialized = false; // Runtime-only GPU state

    const max_shaders = 16;

    entries: [max_shaders]?ShaderEntry = [_]?ShaderEntry{null} ** max_shaders,
    count: usize = 0,
    default_shader: []const u8 = "blinn_phong",
    layout: sokol.gfx.VertexLayoutState = .{},
    depth_state: sokol.gfx.DepthState = .{},

    /// Initialize the registry (called automatically by Sparze)
    pub fn init(allocator: std.mem.Allocator) ShaderRegistry {
        _ = allocator;
        return .{};
    }

    /// Deinitialize and destroy all shaders/pipelines
    pub fn deinit(self: *ShaderRegistry, allocator: std.mem.Allocator) void {
        _ = allocator;
        for (&self.entries) |*entry| {
            if (entry.*) |e| {
                if (e.pipeline.id != 0) sokol.gfx.destroyPipeline(e.pipeline);
                if (e.shader.id != 0) sokol.gfx.destroyShader(e.shader);
                entry.* = null;
            }
        }
        self.count = 0;
    }

    /// Register a shader spec (comptime interface)
    pub fn register(self: *ShaderRegistry, comptime Spec: type) void {
        if (self.count >= max_shaders) {
            if (is_debug) @panic("ShaderRegistry: too many shaders registered");
            return;
        }

        const backend = sokol.gfx.queryBackend();
        const shader = sokol.gfx.makeShader(Spec.shaderDesc(backend));
        var pipeline_desc = Spec.pipelineDesc(self.layout);
        pipeline_desc.shader = shader;
        pipeline_desc.depth = self.depth_state;
        const pipeline = sokol.gfx.makePipeline(pipeline_desc);

        self.entries[self.count] = ShaderEntry{
            .name = Spec.name,
            .shader = shader,
            .pipeline = pipeline,
            .applyVsUniforms = Spec.applyVsUniforms,
            .applyFsUniforms = Spec.applyFsUniforms,
        };
        self.count += 1;
    }

    /// Get shader entry by name
    pub fn get(self: *const ShaderRegistry, name: []const u8) ?ShaderEntry {
        for (self.entries[0..self.count]) |entry| {
            if (entry) |e| {
                if (std.mem.eql(u8, e.name, name)) {
                    return e;
                }
            }
        }
        return null;
    }

    /// Get shader entry by name, falling back to default if not found
    pub fn getOrDefault(self: *const ShaderRegistry, name: []const u8) ?ShaderEntry {
        return self.get(name) orelse self.get(self.default_shader);
    }
};

/// Material component for shader selection and parameters
pub const Material = struct {
    shader: []const u8 = "blinn_phong", // Shader name (unified for built-in and custom)
    // Blinn-Phong parameters
    shininess: f32 = 32.0,
    specular_strength: f32 = 0.5,
    // PBR parameters
    metallic: f32 = 0.0,
    roughness: f32 = 0.5,

    pub fn format(self: Material, writer: anytype) !void {
        try writer.print("Material(shader: {s})", .{self.shader});
    }

    /// Custom serializer for Material (shader name is not POD)
    /// Note: Custom shader names are preserved via string interning. Unknown shaders
    /// at deserialize time will use the stored name, which may fail at runtime if
    /// the shader isn't registered. This is intentional - it allows save files to
    /// work across sessions where custom shaders are registered.
    pub const Serializer = struct {
        const max_shader_name = 64;

        // String intern table for deserialized shader names
        // This allows custom shader names to persist across save/load cycles
        var intern_table: [16][max_shader_name]u8 = undefined;
        var intern_lens: [16]u8 = [_]u8{0} ** 16;
        var intern_count: usize = 0;

        pub fn serialize(mat: Material, writer: anytype) !void {
            // Write shader name as length-prefixed string
            const len: u8 = @intCast(@min(mat.shader.len, max_shader_name));
            try writer.writeByte(len);
            try writer.writeAll(mat.shader[0..len]);
            // Write POD fields
            try writer.writeAll(std.mem.asBytes(&mat.shininess));
            try writer.writeAll(std.mem.asBytes(&mat.specular_strength));
            try writer.writeAll(std.mem.asBytes(&mat.metallic));
            try writer.writeAll(std.mem.asBytes(&mat.roughness));
        }

        pub fn deserialize(reader: anytype) !Material {
            // Read shader name length with bounds check
            const len = try reader.readByte();
            if (len > max_shader_name) {
                // Corrupted data - skip invalid bytes and use default
                var skip_buf: [256]u8 = undefined;
                var remaining = len;
                while (remaining > 0) {
                    const to_read = @min(remaining, skip_buf.len);
                    _ = try reader.readAtLeast(skip_buf[0..to_read], to_read);
                    remaining -= @as(u8, @intCast(to_read));
                }
                // Skip POD fields too
                var pod_skip: [16]u8 = undefined;
                _ = try reader.readAtLeast(&pod_skip, 16);
                return .{ .shader = "blinn_phong" };
            }

            var shader_buf: [max_shader_name]u8 = undefined;
            _ = try reader.readAtLeast(shader_buf[0..len], len);

            // Map to compile-time strings for known shaders (avoids allocation)
            const shader_name: []const u8 = blk: {
                const read_name = shader_buf[0..len];
                if (std.mem.eql(u8, read_name, "unlit")) break :blk "unlit";
                if (std.mem.eql(u8, read_name, "blinn_phong")) break :blk "blinn_phong";
                if (std.mem.eql(u8, read_name, "pbr")) break :blk "pbr";
                if (std.mem.eql(u8, read_name, "rim")) break :blk "rim";
                // Unknown shader - intern the name for persistence
                // First check if already interned
                for (0..intern_count) |i| {
                    const interned = intern_table[i][0..intern_lens[i]];
                    if (std.mem.eql(u8, interned, read_name)) {
                        break :blk interned;
                    }
                }
                // Intern new name if space available
                if (intern_count < intern_table.len) {
                    @memcpy(intern_table[intern_count][0..len], read_name);
                    intern_lens[intern_count] = len;
                    const result = intern_table[intern_count][0..len];
                    intern_count += 1;
                    break :blk result;
                }
                // Intern table full - fall back to default
                break :blk "blinn_phong";
            };

            // Read POD fields
            var shininess: f32 = undefined;
            var specular_strength: f32 = undefined;
            var metallic: f32 = undefined;
            var roughness: f32 = undefined;
            _ = try reader.readAtLeast(std.mem.asBytes(&shininess), @sizeOf(f32));
            _ = try reader.readAtLeast(std.mem.asBytes(&specular_strength), @sizeOf(f32));
            _ = try reader.readAtLeast(std.mem.asBytes(&metallic), @sizeOf(f32));
            _ = try reader.readAtLeast(std.mem.asBytes(&roughness), @sizeOf(f32));
            return .{
                .shader = shader_name,
                .shininess = shininess,
                .specular_strength = specular_strength,
                .metallic = metallic,
                .roughness = roughness,
            };
        }
    };
};

// =============================================================================
// Resources
// =============================================================================

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

/// Lazily initialized 3D rendering buffers
/// Only allocated when first 3D entity is rendered
pub const Render3DBuffers = struct {
    // Skip serialization (runtime-only GPU state)
    pub const serialized = false;

    // GPU buffers (vertex/index)
    vertex_buffer: sokol.gfx.Buffer = .{},
    index_buffer: sokol.gfx.Buffer = .{},
    // Heap-allocated staging buffers for per-frame geometry building
    vertices: []sokol.shape.Vertex = &.{},
    indices: []u16 = &.{},
    allocator: ?std.mem.Allocator = null,
    // Initialization state
    initialized: bool = false,
    // Current frame's element ranges for batched drawing
    draw_count: u32 = 0,
};

// Note: Render3DShaders has been replaced by ShaderRegistry

// =============================================================================
// Helper Types
// =============================================================================

const Mat4 = [4][4]f32;

// =============================================================================
// Matrix Math Utilities
// =============================================================================

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
    // Setup vertex layout for sokol.shape
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

    // Initialize shader registry with layout and depth state
    var registry = ShaderRegistry{};
    registry.layout = layout;
    registry.depth_state = depth_state;

    // Register built-in shaders (same unified interface as custom shaders)
    registry.register(UnlitShader);
    registry.register(BlinnPhongShader);
    registry.register(PbrShader);

    commands.setResource(ShaderRegistry, registry);

    // Initialize 3D buffers resource (not yet allocated)
    var buffers = Render3DBuffers{};
    buffers.allocator = allocator;
    commands.setResource(Render3DBuffers, buffers);

    // Initialize 3D camera and lighting
    commands.setResource(Camera3D, .{});
    commands.setResource(Light3D, .{});
}

/// Ensure 3D buffers are initialized before rendering
/// Only allocates buffers when first 3D entity is encountered
fn ensure3DBuffers(
    buffers: ResourceMut(Render3DBuffers),
    boxes: Query(struct { Box3D }),
    spheres: Query(struct { Sphere3D }),
    cylinders: Query(struct { Cylinder3D }),
    tori: Query(struct { Torus3D }),
    planes: Query(struct { Plane3D }),
) !void {
    // Early return if already initialized or no 3D entities
    // Note: sparze.ResourceMut(T) returns *T directly (pointer)
    if (buffers.initialized) {
        return;
    }

    // Check if any 3D entities exist
    const has_3d_entities = boxes.entities.len > 0 or
        spheres.entities.len > 0 or
        cylinders.entities.len > 0 or
        tori.entities.len > 0 or
        planes.entities.len > 0;

    if (!has_3d_entities) {
        return;
    }

    // Allocate heap buffers for per-frame geometry building
    const allocator = buffers.allocator orelse return error.AllocatorNotSet;
    buffers.vertices = try allocator.alloc(sokol.shape.Vertex, MAX_3D_VERTICES);
    errdefer allocator.free(buffers.vertices);
    buffers.indices = try allocator.alloc(u16, MAX_3D_INDICES);
    errdefer allocator.free(buffers.indices);

    // Create GPU vertex/index buffers
    buffers.vertex_buffer = sokol.gfx.makeBuffer(.{
        .size = MAX_3D_VERTICES * @sizeOf(sokol.shape.Vertex),
        .usage = .{ .vertex_buffer = true, .stream_update = true },
    });
    errdefer sokol.gfx.destroyBuffer(buffers.vertex_buffer);

    buffers.index_buffer = sokol.gfx.makeBuffer(.{
        .size = MAX_3D_INDICES * @sizeOf(u16),
        .usage = .{ .index_buffer = true, .stream_update = true },
    });
    errdefer sokol.gfx.destroyBuffer(buffers.index_buffer);

    buffers.initialized = true;
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

/// Shader bucket for batching draw calls
const ShaderBucket = struct {
    shader_name: []const u8 = "",
    commands: [max_commands]DrawCommand = undefined,
    count: usize = 0,

    const max_commands = 1024;
};

/// Command buckets for batching draw calls by shader name (unified for all shaders)
/// Note: max_shaders is limited to 4 to keep stack usage reasonable (~800KB vs ~600KB original).
/// For more shaders, consider heap allocation or reducing max_commands.
const CommandBuckets = struct {
    const max_shaders = 4;

    buckets: [max_shaders]ShaderBucket = [_]ShaderBucket{.{}} ** max_shaders,
    bucket_count: usize = 0,

    /// Add a draw command to the appropriate shader bucket
    fn add(self: *CommandBuckets, shader_name: []const u8, cmd: DrawCommand) void {
        // Find existing bucket for this shader
        for (self.buckets[0..self.bucket_count]) |*bucket| {
            if (std.mem.eql(u8, bucket.shader_name, shader_name)) {
                if (bucket.count >= ShaderBucket.max_commands) {
                    if (is_debug) @panic("Too many draw commands for shader");
                    return;
                }
                bucket.commands[bucket.count] = cmd;
                bucket.count += 1;
                return;
            }
        }

        // Create new bucket for this shader
        if (self.bucket_count >= max_shaders) {
            if (is_debug) @panic("Too many different shaders in use");
            return;
        }

        self.buckets[self.bucket_count] = ShaderBucket{
            .shader_name = shader_name,
            .commands = undefined,
            .count = 1,
        };
        self.buckets[self.bucket_count].commands[0] = cmd;
        self.bucket_count += 1;
    }

    /// Get total command count across all buckets
    fn total(self: *const CommandBuckets) usize {
        var count: usize = 0;
        for (self.buckets[0..self.bucket_count]) |bucket| {
            count += bucket.count;
        }
        return count;
    }
};

/// Check if buffer has capacity for the upcoming shape geometry.
/// Uses the exact size needed for the shape rather than a fixed margin.
fn hasCapacityForShape(buf: sokol.shape.Buffer, max_vertices: usize, max_indices: usize, shape_sizes: sokol.shape.Sizes) bool {
    const vertex_capacity = max_vertices * @sizeOf(sokol.shape.Vertex);
    const index_capacity = max_indices * @sizeOf(u16);

    const needed_vertex_space = buf.vertices.data_size + shape_sizes.vertices.size;
    const needed_index_space = buf.indices.data_size + shape_sizes.indices.size;

    if (needed_vertex_space > vertex_capacity or needed_index_space > index_capacity) {
        if (is_debug) @panic("Vertex/index buffer overflow: shape requires more space than available");
        return false;
    }
    return true;
}

/// Draw all commands in a shader bucket using the unified shader interface
fn drawShaderBucket(
    bucket: ShaderBucket,
    entry: ShaderEntry,
    bindings: sokol.gfx.Bindings,
    light: Light3D,
    camera: Camera3D,
) void {
    if (bucket.count == 0) return;

    sokol.gfx.applyPipeline(entry.pipeline);
    sokol.gfx.applyBindings(bindings);

    // Build FS uniform params once (light/camera don't change per-command)
    const fs_base = FsUniformParams{
        .light_pos = light.position,
        .view_pos = camera.eye,
        .light_color = light.color,
        .ambient_strength = light.ambient_strength,
        .shininess = 0,
        .specular_strength = 0,
        .metallic = 0,
        .roughness = 0,
    };

    for (bucket.commands[0..bucket.count]) |cmd| {
        // Apply VS uniforms
        entry.applyVsUniforms(.{
            .mvp = cmd.mvp,
            .model = cmd.model,
        });

        // Apply FS uniforms with material params
        var fs_params = fs_base;
        fs_params.shininess = cmd.material.shininess;
        fs_params.specular_strength = cmd.material.specular_strength;
        fs_params.metallic = cmd.material.metallic;
        fs_params.roughness = cmd.material.roughness;
        entry.applyFsUniforms(fs_params);

        sokol.gfx.draw(cmd.base_element, cmd.num_elements, 1);
    }
}

fn draw3D(
    boxes: Query(struct { Box3D, Transform, ?Color, ?Material }),
    spheres: Query(struct { Sphere3D, Transform, ?Color, ?Material }),
    cylinders: Query(struct { Cylinder3D, Transform, ?Color, ?Material }),
    tori: Query(struct { Torus3D, Transform, ?Color, ?Material }),
    planes: Query(struct { Plane3D, Transform, ?Color, ?Material }),
    camera: Resource(Camera3D),
    light: Resource(Light3D),
    buffers: ResourceMut(Render3DBuffers),
    registry: Resource(ShaderRegistry),
    // Commands for Rotation/Scale lookup (avoids comptime branch quota explosion from adding
    // ?Rotation/?Scale to each shape query - would exceed Zig's 3000 branch limit)
    commands: anytype,
) !void {
    // Early return if 3D buffers not initialized (no 3D entities)
    // Note: sparze.Resource(T) / ResourceMut(T) return *const T / *T directly (pointer)
    if (!buffers.initialized) {
        return;
    }
    // Access sparse sets for Rotation/Scale lookups
    const rotation_set = commands.getSparseSetPtr(Rotation);
    const scale_set = commands.getSparseSetPtr(Scale);

    // Use heap-allocated staging buffers from buffers resource (no stack allocation)
    var buf = sokol.shape.Buffer{
        .vertices = .{ .buffer = sokol.shape.asRange(buffers.vertices) },
        .indices = .{ .buffer = sokol.shape.asRange(buffers.indices) },
    };

    // Derive capacity from actual slice lengths to ensure consistency
    const max_vertices: usize = buffers.vertices.len;
    const max_indices: usize = buffers.indices.len;

    // Command buckets for batching draw calls by shader type
    // Use std.mem.zeroes for proper zero-initialization on WASM
    var buckets = std.mem.zeroes(CommandBuckets);

    // Calculate view-projection matrix
    // Note: Mat4/multiply use row-major convention. When sent to column-major GLSL shaders,
    // the implicit transpose means row-major (model * view * proj) becomes column-major (proj * view * model).
    const aspect = sokol.app.widthf() / sokol.app.heightf();
    const view = lookAt(camera.eye, camera.target, camera.up);
    const proj = perspective(camera.fov, aspect, camera.near, camera.far);
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

        // Check buffer capacity for this specific box shape
        const box_sizes = sokol.shape.boxSizes(box.tiles);
        if (!hasCapacityForShape(buf, max_vertices, max_indices, box_sizes)) break;

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

        // Check buffer capacity for this specific sphere shape
        const sphere_sizes = sokol.shape.sphereSizes(sphere.slices, sphere.stacks);
        if (!hasCapacityForShape(buf, max_vertices, max_indices, sphere_sizes)) break;

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

        // Check buffer capacity for this specific cylinder shape
        const cylinder_sizes = sokol.shape.cylinderSizes(cylinder.slices, cylinder.stacks);
        if (!hasCapacityForShape(buf, max_vertices, max_indices, cylinder_sizes)) break;

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

        // Check buffer capacity for this specific torus shape
        const torus_sizes = sokol.shape.torusSizes(torus.sides, torus.rings);
        if (!hasCapacityForShape(buf, max_vertices, max_indices, torus_sizes)) break;

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

        // Check buffer capacity for this specific plane shape
        const plane_sizes = sokol.shape.planeSizes(plane.tiles);
        if (!hasCapacityForShape(buf, max_vertices, max_indices, plane_sizes)) break;

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
        // Shaders are eagerly initialized at startup (see init())
        // No lazy initialization needed - safe for WASM/WebGPU

        // Upload vertex/index data to GPU
        sokol.gfx.updateBuffer(buffers.vertex_buffer, .{
            .ptr = buffers.vertices.ptr,
            .size = buf.vertices.data_size,
        });
        sokol.gfx.updateBuffer(buffers.index_buffer, .{
            .ptr = buffers.indices.ptr,
            .size = buf.indices.data_size,
        });

        // Setup bindings
        var bindings = sokol.gfx.Bindings{};
        bindings.vertex_buffers[0] = buffers.vertex_buffer;
        bindings.index_buffer = buffers.index_buffer;

        // Draw each shader bucket using the unified registry
        for (buckets.buckets[0..buckets.bucket_count]) |bucket| {
            if (bucket.count == 0) continue;

            // Look up shader in registry
            if (registry.getOrDefault(bucket.shader_name)) |entry| {
                drawShaderBucket(bucket, entry, bindings, light.*, camera.*);
            } else if (is_debug) {
                std.debug.print("Warning: shader '{s}' not found in registry\n", .{bucket.shader_name});
            }
        }
    }

    buffers.draw_count = @intCast(total_count);
}

fn cleanup(buffers: ResourceMut(Render3DBuffers), registry: ResourceMut(ShaderRegistry)) void {
    // Free heap-allocated staging buffers
    if (buffers.allocator) |allocator| {
        if (buffers.vertices.len > 0) allocator.free(buffers.vertices);
        if (buffers.indices.len > 0) allocator.free(buffers.indices);
    }

    // Destroy GPU buffers if initialized
    if (buffers.initialized) {
        if (buffers.vertex_buffer.id != 0) sokol.gfx.destroyBuffer(buffers.vertex_buffer);
        if (buffers.index_buffer.id != 0) sokol.gfx.destroyBuffer(buffers.index_buffer);
    }

    // Destroy all registered shaders and pipelines via registry
    for (&registry.entries) |*entry| {
        if (entry.*) |e| {
            if (e.pipeline.id != 0) sokol.gfx.destroyPipeline(e.pipeline);
            if (e.shader.id != 0) sokol.gfx.destroyShader(e.shader);
            entry.* = null;
        }
    }
    registry.count = 0;

    // Zero out buffer fields to prevent accidental reuse or double-free
    buffers.vertices = &.{};
    buffers.indices = &.{};
    buffers.allocator = null;
    buffers.vertex_buffer = .{};
    buffers.index_buffer = .{};
    buffers.initialized = false;
    buffers.draw_count = 0;
}

// =============================================================================
// Plugin Declarations
// =============================================================================

pub const Components = .{
    Plane3D,
    Box3D,
    Sphere3D,
    Cylinder3D,
    Torus3D,
    Material,
};

pub const Resources = .{
    Camera3D,
    Light3D,
    Render3DBuffers,
    ShaderRegistry,
};

pub const Events = .{};

pub const Requires = .{RendererPlugin};

pub const systems = .{
    .startup = &.{
        .{ .system = init, .stage = .first },
    },
    .main = &.{
        .{ .system = ensure3DBuffers, .stage = .render, .config = .{
            .priority = 100,
            .tags = &.{"3d-init"},
        } },
        .{ .system = draw3D, .stage = .render, .config = .{
            .priority = 110,
            .after = &.{"3d-init"},
            .tags = &.{"3d-render"},
        } },
    },
    .terminate = &.{
        .{ .system = cleanup, .stage = .first },
    },
};
