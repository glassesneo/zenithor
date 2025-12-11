/// Material Components - Type-safe shader-specific materials
///
/// MaterialFor generates a component type for a specific shader, containing
/// the shader's parameters and a compile-time resolved handle to the shader.
///
/// This provides type safety - each material is tied to a specific shader's
/// parameter set, preventing parameter mismatches at compile time.
///
/// Example usage:
/// ```zig
/// const BlinnPhongMaterial = MaterialFor(BlinnPhongShader);
/// const PbrMaterial = MaterialFor(PbrShader);
///
/// _ = commands.createEntityWith(.{
///     Box3D{},
///     Transform{},
///     BlinnPhongMaterial{ .params = .{ .shininess = 64.0 } },
/// });
/// ```

const shader_spec = @import("shader_spec.zig");

/// Generate a material component type for a specific shader
///
/// The generated type contains:
/// - `params: Spec.Params` - Shader-specific parameters
/// - `shader_type: type` - The shader type (for registry lookup)
///
/// The handle is not stored in the component to avoid coupling the component
/// to a specific registry instance. Instead, the shader type is stored and
/// the registry lookup happens at system runtime.
pub fn MaterialFor(comptime Spec: type) type {
    // Validate shader at compile time
    shader_spec.validateShaderSpec(Spec);

    return struct {
        const Self = @This();

        /// Shader-specific parameters
        params: Spec.Params = Spec.defaultParams(),

        /// Shader type for registry lookup
        /// This is stored as a comptime value and used by systems to
        /// resolve the shader handle from the registry
        pub const shader_type = Spec;

        /// Create material with default parameters
        pub fn init() Self {
            return .{};
        }

        /// Create material with custom parameters
        pub fn withParams(params: Spec.Params) Self {
            return .{ .params = params };
        }
    };
}

/// Extract shader type from a material component
/// This helper is used by rendering systems to get the shader type
/// from a material instance at compile time
pub fn getShaderType(comptime Material: type) type {
    if (@hasDecl(Material, "shader_type")) {
        return Material.shader_type;
    }
    @compileError("Type " ++ @typeName(Material) ++ " is not a valid material (missing shader_type decl)");
}

/// Check if a type is a material component
pub fn isMaterial(comptime T: type) bool {
    return @hasDecl(T, "shader_type") and @hasField(T, "params");
}
