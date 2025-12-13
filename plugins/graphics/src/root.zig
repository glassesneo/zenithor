const sparze = @import("sparze");
const SingleQuery = sparze.SingleQuery;
const Query = sparze.Query;
const Resource = sparze.Resource;
const ResourceMut = sparze.ResourceMut;
const sokol = @import("sokol");
const Pipeline = sokol.gfx.Pipeline;

const zenithor = @import("zenithor");
const Transform = zenithor.Transform;
const Rotation = zenithor.Rotation;
const Scale = zenithor.Scale;
const Color = zenithor.Color;
const Stage = zenithor.Stage;
const SystemConfig = zenithor.SystemConfig;
const std = @import("std");
const builtin = @import("builtin");

// Shader imports (generated modules from build.zig)
const pbr_shader = @import("pbr_shader");
const blinn_phong_shader = @import("blinn_phong_shader");
const unlit_shader = @import("unlit_shader");

// New shader system imports
const shader_spec = @import("shader_spec.zig");
const shader_registry = @import("shader_registry.zig");
const material_mod = @import("material.zig");
const UnlitShader = @import("shaders/unlit.zig");
const BlinnPhongShader = @import("shaders/blinn_phong.zig");
const PbrShader = @import("shaders/pbr.zig");

const is_debug = builtin.mode == .Debug;

// =============================================================================
// Plugin Factory Function
// =============================================================================

/// Create a graphics plugin with custom shader configuration
///
/// Example:
/// ```zig
/// const Graphics = graphics_plugin.Plugin(.{ UnlitShader, BlinnPhongShader, PbrShader });
/// ```
pub fn Plugin(comptime shaders: anytype) type {
    // Validate shaders at compile time - ensures all conform to ShaderSpec contract
    shader_spec.validateShaderSpecs(shaders);

    return struct {
        // Store validated shaders for future dynamic shader configuration.
        // Currently the implementation uses the three built-in shaders (unlit, blinn_phong, pbr).
        pub const validated_shaders = shaders;
        // =============================================================================
        // Constants
        // =============================================================================

        /// Maximum vertices for 3D staging buffer
        const MAX_3D_VERTICES = 65536;
        /// Maximum indices for 3D staging buffer
        const MAX_3D_INDICES = 262144;

        // =============================================================================
        // Type Exports
        // =============================================================================

        pub const PassAction = sokol.gfx.PassAction;

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

        /// 3D Shaders resource - stores shader and pipeline handles
        pub const Render3DShaders = struct {
            shader_unlit: sokol.gfx.Shader = .{},
            pipeline_unlit: sokol.gfx.Pipeline = .{},
            shader_blinn_phong: sokol.gfx.Shader = .{},
            pipeline_blinn_phong: sokol.gfx.Pipeline = .{},
            shader_pbr: sokol.gfx.Shader = .{},
            pipeline_pbr: sokol.gfx.Pipeline = .{},
        };

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

        // Debug logging helper (native debug builds only)

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

            // Initialize shader registry with layout and depth state
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

            // Create shaders directly (WASM-compatible)
            const backend = sokol.gfx.queryBackend();

            const shader_unlit = sokol.gfx.makeShader(UnlitShader.shaderDesc(backend));
            var pipeline_desc_unlit = UnlitShader.pipelineDesc(layout);
            pipeline_desc_unlit.shader = shader_unlit;
            pipeline_desc_unlit.depth = depth_state;
            const pipeline_unlit = sokol.gfx.makePipeline(pipeline_desc_unlit);

            const shader_blinn_phong = sokol.gfx.makeShader(BlinnPhongShader.shaderDesc(backend));
            var pipeline_desc_blinn_phong = BlinnPhongShader.pipelineDesc(layout);
            pipeline_desc_blinn_phong.shader = shader_blinn_phong;
            pipeline_desc_blinn_phong.depth = depth_state;
            const pipeline_blinn_phong = sokol.gfx.makePipeline(pipeline_desc_blinn_phong);

            const shader_pbr = sokol.gfx.makeShader(PbrShader.shaderDesc(backend));
            var pipeline_desc_pbr = PbrShader.pipelineDesc(layout);
            pipeline_desc_pbr.shader = shader_pbr;
            pipeline_desc_pbr.depth = depth_state;
            const pipeline_pbr = sokol.gfx.makePipeline(pipeline_desc_pbr);

            // Store shaders in simple resource
            commands.setResource(Render3DShaders, .{
                .shader_unlit = shader_unlit,
                .pipeline_unlit = pipeline_unlit,
                .shader_blinn_phong = shader_blinn_phong,
                .pipeline_blinn_phong = pipeline_blinn_phong,
                .shader_pbr = shader_pbr,
                .pipeline_pbr = pipeline_pbr,
            });

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
            if (buffers.value.initialized) {
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
            const allocator = buffers.value.allocator orelse return error.AllocatorNotSet;
            buffers.value.vertices = try allocator.alloc(sokol.shape.Vertex, MAX_3D_VERTICES);
            errdefer allocator.free(buffers.value.vertices);
            buffers.value.indices = try allocator.alloc(u16, MAX_3D_INDICES);
            errdefer allocator.free(buffers.value.indices);

            // Create GPU vertex/index buffers
            buffers.value.vertex_buffer = sokol.gfx.makeBuffer(.{
                .size = MAX_3D_VERTICES * @sizeOf(sokol.shape.Vertex),
                .usage = .{ .vertex_buffer = true, .stream_update = true },
            });
            errdefer sokol.gfx.destroyBuffer(buffers.value.vertex_buffer);

            buffers.value.index_buffer = sokol.gfx.makeBuffer(.{
                .size = MAX_3D_INDICES * @sizeOf(u16),
                .usage = .{ .index_buffer = true, .stream_update = true },
            });
            errdefer sokol.gfx.destroyBuffer(buffers.value.index_buffer);

            buffers.value.initialized = true;
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
            buffers: ResourceMut(Render3DBuffers),
            shader_res: Resource(Render3DShaders),
            // Commands for Rotation/Scale lookup (avoids comptime branch quota explosion from adding
            // ?Rotation/?Scale to each shape query - would exceed Zig's 3000 branch limit)
            commands: anytype,
        ) !void {
            // Early return if 3D buffers not initialized (no 3D entities)
            if (!buffers.value.initialized) {
                return;
            }
            // Access sparse sets for Rotation/Scale lookups
            const rotation_set = commands.getSparseSetPtr(Rotation);
            const scale_set = commands.getSparseSetPtr(Scale);

            // Use heap-allocated staging buffers from buffers resource (no stack allocation)
            var buf = sokol.shape.Buffer{
                .vertices = .{ .buffer = sokol.shape.asRange(buffers.value.vertices) },
                .indices = .{ .buffer = sokol.shape.asRange(buffers.value.indices) },
            };

            // Derive capacity from actual slice lengths to ensure consistency
            const max_vertices: usize = buffers.value.vertices.len;
            const max_indices: usize = buffers.value.indices.len;

            // Command buckets for batching draw calls by shader type
            // Use std.mem.zeroes for proper zero-initialization on WASM
            var buckets = std.mem.zeroes(CommandBuckets);

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
                sokol.gfx.updateBuffer(buffers.value.vertex_buffer, .{
                    .ptr = buffers.value.vertices.ptr,
                    .size = buf.vertices.data_size,
                });
                sokol.gfx.updateBuffer(buffers.value.index_buffer, .{
                    .ptr = buffers.value.indices.ptr,
                    .size = buf.indices.data_size,
                });

                // Setup bindings
                var bindings = sokol.gfx.Bindings{};
                bindings.vertex_buffers[0] = buffers.value.vertex_buffer;
                bindings.index_buffer = buffers.value.index_buffer;

                // Draw each shader bucket (pipelines created at startup)
                if (buckets.unlit_count > 0) {
                    drawUnlitBucket(buckets.unlit[0..buckets.unlit_count], shader_res.value.pipeline_unlit, bindings);
                }
                if (buckets.blinn_count > 0) {
                    drawBlinnPhongBucket(buckets.blinn[0..buckets.blinn_count], shader_res.value.pipeline_blinn_phong, bindings, light.value.*, camera.value.*);
                }
                if (buckets.pbr_count > 0) {
                    drawPbrBucket(buckets.pbr[0..buckets.pbr_count], shader_res.value.pipeline_pbr, bindings, light.value.*, camera.value.*);
                }
            }

            buffers.value.draw_count = @intCast(total_count);
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

        fn cleanup(buffers: ResourceMut(Render3DBuffers), shader_res: Resource(Render3DShaders)) void {
            // Free heap-allocated staging buffers
            if (buffers.value.allocator) |allocator| {
                if (buffers.value.vertices.len > 0) allocator.free(buffers.value.vertices);
                if (buffers.value.indices.len > 0) allocator.free(buffers.value.indices);
            }

            // Destroy GPU buffers if initialized
            if (buffers.value.initialized) {
                if (buffers.value.vertex_buffer.id != 0) sokol.gfx.destroyBuffer(buffers.value.vertex_buffer);
                if (buffers.value.index_buffer.id != 0) sokol.gfx.destroyBuffer(buffers.value.index_buffer);
            }

            // Destroy shaders and pipelines
            if (shader_res.value.pipeline_unlit.id != 0) sokol.gfx.destroyPipeline(shader_res.value.pipeline_unlit);
            if (shader_res.value.shader_unlit.id != 0) sokol.gfx.destroyShader(shader_res.value.shader_unlit);
            if (shader_res.value.pipeline_blinn_phong.id != 0) sokol.gfx.destroyPipeline(shader_res.value.pipeline_blinn_phong);
            if (shader_res.value.shader_blinn_phong.id != 0) sokol.gfx.destroyShader(shader_res.value.shader_blinn_phong);
            if (shader_res.value.pipeline_pbr.id != 0) sokol.gfx.destroyPipeline(shader_res.value.pipeline_pbr);
            if (shader_res.value.shader_pbr.id != 0) sokol.gfx.destroyShader(shader_res.value.shader_pbr);

            // Zero out all fields to prevent accidental reuse or double-free
            buffers.value.vertices = &.{};
            buffers.value.indices = &.{};
            buffers.value.allocator = null;
            buffers.value.vertex_buffer = .{};
            buffers.value.index_buffer = .{};
            buffers.value.initialized = false;
            buffers.value.draw_count = 0;
        }

        // Declarative system registration (moved to const for Plugin wrapper)
        const graphics_systems = .{
            .startup = &.{
                .{ .system = init, .stage = .first },
            },
            .main = &.{
                .{ .system = setDefaults, .stage = .pre_render },
                .{ .system = setup2d, .stage = .pre_render },
                .{ .system = beginPass, .stage = .render, .config = .{ .tags = &.{"begin-pass"} } },
                .{ .system = drawPoint, .stage = .render, .config = .{ .after = &.{"begin-pass"} } },
                .{ .system = drawLine, .stage = .render, .config = .{ .after = &.{"begin-pass"} } },
                .{ .system = drawTriangle, .stage = .render, .config = .{ .after = &.{"begin-pass"} } },
                .{ .system = drawRectangle, .stage = .render, .config = .{ .after = &.{"begin-pass"} } },
                .{ .system = drawCircle, .stage = .render, .config = .{ .after = &.{"begin-pass"} } },
                .{ .system = ensure3DBuffers, .stage = .render_submit, .config = .{ .tags = &.{"3d-init"}, .before = &.{"3d-render"} } },
                .{ .system = draw3D, .stage = .render_submit, .config = .{ .tags = &.{"3d-render"} } },
                .{ .system = draw2D, .stage = .render_submit, .config = .{ .tags = &.{"2d-render"} } },
                .{ .system = endPass, .stage = .post_render },
                .{ .system = commit, .stage = .post_render, .config = .{} },
            },
            .terminate = &.{
                .{ .system = cleanup, .stage = .first },
            },
        };

        pub const Components = .{
            Point,
            Line,
            Triangle,
            Rectangle,
            Circle,
            Plane3D,
            Box3D,
            Sphere3D,
            Cylinder3D,
            Torus3D,
            Material,
        };

        pub const Resources = .{
            RenderingOptions,
            Camera3D,
            Light3D,
            Render3DBuffers,
            Render3DShaders,
        };

        pub const Events = .{};

        pub const systems = graphics_systems;
    };
}

pub const Default = Plugin(.{ UnlitShader, BlinnPhongShader, PbrShader });
