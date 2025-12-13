/// Shader Registry - Compile-time shader management with lazy initialization
///
/// The ShaderRegistry manages GPU shaders and pipelines for all registered shaders.
/// It provides compile-time type safety and lazy initialization - shaders are only
/// created when first used.
///
/// Features:
/// - Compile-time shader registration (zero runtime lookup)
/// - Lazy GPU resource creation (only on first use)
/// - Type-safe shader handles
/// - Automatic cleanup of initialized resources
const std = @import("std");
const sokol = @import("sokol");
const shader_spec = @import("shader_spec.zig");

/// Generate a ShaderKey enum from a tuple of shader specs
fn ShaderKey(comptime Shaders: anytype) type {
    // Validate all shaders at compile time
    shader_spec.validateShaderSpecs(Shaders);

    // Build enum fields from shader names
    var enum_fields: [Shaders.len]std.builtin.Type.EnumField = undefined;
    inline for (Shaders, 0..) |Spec, i| {
        enum_fields[i] = .{
            .name = Spec.name,
            .value = i,
        };
    }

    return @Type(.{
        .@"enum" = .{
            .tag_type = std.math.IntFittingRange(0, Shaders.len - 1),
            .fields = &enum_fields,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
}

/// Type-safe shader handle that wraps a shader key
/// The Key type will be determined when the handle is created
pub fn ShaderHandle(comptime Key: type, comptime Spec: type) type {
    return struct {
        key: Key,

        // Store the spec type for validation
        pub const spec_type = Spec;

        pub fn getKey(self: @This()) Key {
            return self.key;
        }
    };
}

/// Shader Registry Resource - Manages shader lifecycle
pub fn ShaderRegistry(comptime Shaders: anytype) type {
    // Validate shaders at compile time
    shader_spec.validateShaderSpecs(Shaders);

    const Key = ShaderKey(Shaders);

    return struct {
        const Self = @This();

        /// Shader entry state
        const EntryState = enum {
            uninitialized,
            ready,
        };

        /// Single shader registry entry
        const Entry = struct {
            shader: sokol.gfx.Shader = .{},
            pipeline: sokol.gfx.Pipeline = .{},
            state: EntryState = .uninitialized,
        };

        entries: [Shaders.len]Entry,
        layout: sokol.gfx.VertexLayoutState,
        depth_state: sokol.gfx.DepthState,

        /// Initialize the registry with layout and depth state
        /// Does NOT create any GPU resources - use ensureReady() for lazy creation
        pub fn init(
            layout: sokol.gfx.VertexLayoutState,
            depth_state: sokol.gfx.DepthState,
        ) Self {
            return .{
                .entries = [_]Entry{.{}} ** Shaders.len,
                .layout = layout,
                .depth_state = depth_state,
            };
        }

        /// Get compile-time shader handle for a shader spec
        /// Compile error if Spec is not in the registry
        pub fn handle(comptime Spec: type) ShaderHandle(Key, Spec) {
            // Find the shader in the registry
            const key = blk: {
                inline for (Shaders, 0..) |RegisteredSpec, i| {
                    if (Spec == RegisteredSpec) {
                        break :blk @as(Key, @enumFromInt(i));
                    }
                }
                @compileError("Shader " ++ @typeName(Spec) ++ " not found in registry. " ++
                    "Available shaders: " ++ listShaderNames());
            };

            return .{ .key = key };
        }

        /// List all shader names (for error messages)
        fn listShaderNames() []const u8 {
            var names: []const u8 = "";
            for (Shaders, 0..) |Spec, i| {
                if (i > 0) names = names ++ ", ";
                names = names ++ Spec.name;
            }
            return names;
        }

        /// Ensure a shader is ready for use (lazy initialization)
        /// If already initialized, this is a no-op
        pub fn ensureReady(self: *Self, comptime Spec: type) void {
            const key = blk: {
                inline for (Shaders, 0..) |RegisteredSpec, i| {
                    if (Spec == RegisteredSpec) {
                        break :blk @as(Key, @enumFromInt(i));
                    }
                }
                @compileError("Shader " ++ @typeName(Spec) ++ " not found in registry");
            };

            const index = @intFromEnum(key);
            if (self.entries[index].state == .ready) {
                return; // Already initialized
            }

            // Lazy create shader and pipeline
            self.entries[index].shader = sokol.gfx.makeShader(
                Spec.shaderDesc(sokol.gfx.queryBackend()),
            );

            var pipeline_desc = Spec.pipelineDesc(self.layout);
            pipeline_desc.shader = self.entries[index].shader;
            pipeline_desc.depth = self.depth_state;

            self.entries[index].pipeline = sokol.gfx.makePipeline(pipeline_desc);
            self.entries[index].state = .ready;
        }

        /// Get shader and pipeline for a key (must call ensureReady first)
        pub fn get(self: *const Self, key: Key) struct {
            shader: sokol.gfx.Shader,
            pipeline: sokol.gfx.Pipeline,
        } {
            const index = @intFromEnum(key);
            std.debug.assert(self.entries[index].state == .ready);
            return .{
                .shader = self.entries[index].shader,
                .pipeline = self.entries[index].pipeline,
            };
        }

        /// Cleanup all initialized shaders and pipelines
        pub fn cleanup(self: *Self) void {
            for (&self.entries) |*entry| {
                if (entry.state == .ready) {
                    sokol.gfx.destroyPipeline(entry.pipeline);
                    sokol.gfx.destroyShader(entry.shader);
                    entry.* = .{};
                }
            }
        }
    };
}

// Tests
test "ShaderKey generation" {
    const TestShader1 = struct {
        pub const name = "test1";
        pub const Params = struct {};
        pub fn defaultParams() Params {
            return .{};
        }
        pub fn shaderDesc(_: sokol.gfx.Backend) sokol.gfx.ShaderDesc {
            return .{};
        }
        pub fn pipelineDesc(_: sokol.gfx.VertexLayoutState) sokol.gfx.PipelineDesc {
            return .{};
        }
    };

    const TestShader2 = struct {
        pub const name = "test2";
        pub const Params = struct {};
        pub fn defaultParams() Params {
            return .{};
        }
        pub fn shaderDesc(_: sokol.gfx.Backend) sokol.gfx.ShaderDesc {
            return .{};
        }
        pub fn pipelineDesc(_: sokol.gfx.VertexLayoutState) sokol.gfx.PipelineDesc {
            return .{};
        }
    };

    const Key = ShaderKey(.{ TestShader1, TestShader2 });
    const key1: Key = .test1;
    const key2: Key = .test2;

    try std.testing.expectEqual(0, @intFromEnum(key1));
    try std.testing.expectEqual(1, @intFromEnum(key2));
}
