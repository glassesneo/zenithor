/// PBR Shader - Physically-Based Rendering
///
/// Implements a physically-based rendering model using the Cook-Torrance BRDF
/// (Bidirectional Reflectance Distribution Function) with:
/// - GGX/Trowbridge-Reitz normal distribution function
/// - Schlick-GGX geometry function
/// - Fresnel-Schlick approximation
/// - Reinhard tone mapping
///
/// PBR provides more realistic and consistent lighting across different lighting
/// conditions compared to empirical models like Blinn-Phong. It uses physical
/// parameters (metallic, roughness) instead of artistic parameters (shininess, specular).
const sokol = @import("sokol");
const pbr_shader = @import("pbr_shader");

/// Shader identifier
pub const name = "pbr";

/// PBR shader parameters
pub const Params = struct {
    /// Metallic property (0 = dielectric/non-metal, 1 = metal)
    /// Controls how much the surface behaves like a metal
    /// - Metals reflect colored light (tinted by base color)
    /// - Non-metals reflect white light
    metallic: f32 = 0.0,

    /// Surface roughness (0 = smooth/mirror-like, 1 = rough/diffuse)
    /// Controls the size and sharpness of specular highlights
    /// - Smooth surfaces have sharp, small highlights
    /// - Rough surfaces have large, soft highlights
    roughness: f32 = 0.5,
};

/// Returns default parameters
pub fn defaultParams() Params {
    return .{};
}

/// Returns Sokol shader descriptor for the PBR shader
pub fn shaderDesc(backend: sokol.gfx.Backend) sokol.gfx.ShaderDesc {
    return pbr_shader.pbrShaderDesc(backend);
}

/// Returns Sokol pipeline descriptor for the PBR shader
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
