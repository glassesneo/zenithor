/// ShaderSpec Contract
///
/// All shaders (built-in and custom) must implement this interface to work with the
/// graphics plugin's shader registry system.
///
/// Required declarations:
/// - `pub const name: []const u8` - Unique shader identifier (e.g., "unlit", "pbr", "toon")
/// - `pub const Params: type` - Struct type defining per-material shader parameters
/// - `pub fn defaultParams() Params` - Returns default parameter values
/// - `pub fn shaderDesc(backend: sokol.gfx.Backend) sokol.gfx.ShaderDesc` - Sokol shader descriptor
/// - `pub fn pipelineDesc(layout: sokol.gfx.VertexLayoutState) sokol.gfx.PipelineDesc` - Sokol pipeline descriptor
///
/// Example implementation:
/// ```zig
/// pub const MyShader = struct {
///     pub const name = "my_shader";
///     pub const Params = struct {
///         intensity: f32 = 1.0,
///         color_tint: [3]f32 = .{ 1, 1, 1 },
///     };
///     pub fn defaultParams() Params {
///         return .{};
///     }
///     pub fn shaderDesc(backend: sokol.gfx.Backend) sokol.gfx.ShaderDesc {
///         return my_shader_module.myShaderDesc(backend);
///     }
///     pub fn pipelineDesc(layout: sokol.gfx.VertexLayoutState) sokol.gfx.PipelineDesc {
///         return .{
///             .layout = layout,
///             .index_type = .UINT16,
///             .cull_mode = .BACK,
///             .depth = .{
///                 .write_enabled = true,
///                 .compare = .LESS_EQUAL,
///             },
///         };
///     }
/// };
/// ```
const std = @import("std");

/// Validates that a type conforms to the ShaderSpec contract at compile time.
/// Generates a compile error with detailed information if the type is invalid.
pub fn validateShaderSpec(comptime Spec: type) void {
    const type_info = @typeInfo(Spec);
    if (type_info != .@"struct") {
        @compileError("ShaderSpec must be a struct, got " ++ @typeName(Spec));
    }

    // Validate required declarations
    if (!@hasDecl(Spec, "name")) {
        @compileError("ShaderSpec " ++ @typeName(Spec) ++ " must have `pub const name: []const u8`");
    }
    if (!@hasDecl(Spec, "Params")) {
        @compileError("ShaderSpec " ++ @typeName(Spec) ++ " must have `pub const Params: type`");
    }
    if (!@hasDecl(Spec, "defaultParams")) {
        @compileError("ShaderSpec " ++ @typeName(Spec) ++ " must have `pub fn defaultParams() Params`");
    }
    if (!@hasDecl(Spec, "shaderDesc")) {
        @compileError("ShaderSpec " ++ @typeName(Spec) ++ " must have `pub fn shaderDesc(backend) ShaderDesc`");
    }
    if (!@hasDecl(Spec, "pipelineDesc")) {
        @compileError("ShaderSpec " ++ @typeName(Spec) ++ " must have `pub fn pipelineDesc(layout) PipelineDesc`");
    }

    // Validate name type (accept both string literals and slices)
    const name_type = @TypeOf(Spec.name);
    const name_type_info = @typeInfo(name_type);
    if (name_type_info != .pointer) {
        @compileError("ShaderSpec " ++ @typeName(Spec) ++ ".name must be a string, got " ++ @typeName(name_type));
    }
    // Check for const u8 element type
    const child_type_info = @typeInfo(name_type_info.pointer.child);
    const is_valid_string = switch (child_type_info) {
        .int => |int_info| int_info.bits == 8 and int_info.signedness == .unsigned,
        .array => |arr_info| blk: {
            const elem_info = @typeInfo(arr_info.child);
            break :blk elem_info == .int and elem_info.int.bits == 8 and elem_info.int.signedness == .unsigned;
        },
        else => false,
    };
    if (!is_valid_string or !name_type_info.pointer.is_const) {
        @compileError("ShaderSpec " ++ @typeName(Spec) ++ ".name must be []const u8 or string literal, got " ++ @typeName(name_type));
    }

    // Validate Params is a type
    const params_type_info = @typeInfo(Spec.Params);
    if (params_type_info != .@"struct") {
        @compileError("ShaderSpec " ++ @typeName(Spec) ++ ".Params must be a struct, got " ++ @typeName(Spec.Params));
    }

    // Validate defaultParams returns Params
    const default_params_fn_info = @typeInfo(@TypeOf(Spec.defaultParams));
    if (default_params_fn_info != .@"fn") {
        @compileError("ShaderSpec " ++ @typeName(Spec) ++ ".defaultParams must be a function");
    }
    const default_params_return = default_params_fn_info.@"fn".return_type orelse {
        @compileError("ShaderSpec " ++ @typeName(Spec) ++ ".defaultParams must return Params");
    };
    if (default_params_return != Spec.Params) {
        @compileError("ShaderSpec " ++ @typeName(Spec) ++ ".defaultParams must return Params, got " ++ @typeName(default_params_return));
    }
}

/// Validates a tuple of ShaderSpecs at compile time.
/// Ensures all specs conform to the contract and have unique names.
pub fn validateShaderSpecs(comptime shaders: anytype) void {
    const shaders_type_info = @typeInfo(@TypeOf(shaders));
    if (shaders_type_info != .@"struct" or !shaders_type_info.@"struct".is_tuple) {
        @compileError("shaders must be a tuple, got " ++ @typeName(@TypeOf(shaders)));
    }

    // Validate each shader
    inline for (shaders) |Spec| {
        validateShaderSpec(Spec);
    }

    // Check for duplicate names
    inline for (shaders, 0..) |Spec1, i| {
        inline for (shaders, 0..) |Spec2, j| {
            if (i < j and std.mem.eql(u8, Spec1.name, Spec2.name)) {
                @compileError("Duplicate shader name '" ++ Spec1.name ++ "' in shader list at indices " ++
                    std.fmt.comptimePrint("{}", .{i}) ++ " and " ++ std.fmt.comptimePrint("{}", .{j}));
            }
        }
    }
}
