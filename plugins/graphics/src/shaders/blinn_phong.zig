/// Blinn-Phong Shader - Classic diffuse + specular lighting
///
/// Implements the Blinn-Phong lighting model with ambient, diffuse, and specular components.
/// This is a standard shading model used in real-time graphics, providing a good balance
/// between visual quality and performance.
///
/// Lighting components:
/// - Ambient: Base lighting independent of light direction
/// - Diffuse: Light scattered equally in all directions (Lambertian)
/// - Specular: Mirror-like reflections (Blinn half-vector optimization)

const sokol = @import("sokol");
const blinn_phong_shader = @import("blinn_phong_shader");

/// Shader identifier
pub const name = "blinn_phong";

/// Blinn-Phong shader parameters
pub const Params = struct {
    /// Specular exponent controlling highlight size (higher = smaller, sharper)
    /// Typical range: 2-256 (32 is a good default for plastics)
    shininess: f32 = 32.0,

    /// Specular reflection strength (0 = no specular, 1 = full specular)
    /// Controls how much mirror-like reflection the surface has
    specular_strength: f32 = 0.5,
};

/// Returns default parameters
pub fn defaultParams() Params {
    return .{};
}

/// Returns Sokol shader descriptor for the Blinn-Phong shader
pub fn shaderDesc(backend: sokol.gfx.Backend) sokol.gfx.ShaderDesc {
    return blinn_phong_shader.blinnPhongShaderDesc(backend);
}

/// Returns Sokol pipeline descriptor for the Blinn-Phong shader
pub fn pipelineDesc(layout: sokol.gfx.VertexLayoutState) sokol.gfx.PipelineDesc {
    return .{
        .layout = layout,
        .index_type = .UINT16,
        .cull_mode = .BACK,
        .depth = .{
            .write_enabled = true,
            .compare = .LESS_EQUAL,
        },
    };
}
