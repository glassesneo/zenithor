/// Rim Shader - Fresnel/edge lighting effect
///
/// Creates a glowing rim effect on edges of objects, commonly used for
/// sci-fi effects, selection highlighting, or stylized rendering.
/// The effect is strongest when viewing surfaces at grazing angles.
///
/// Parameters (via Material component):
/// - shininess -> rim_power: Controls how sharp the rim falloff is (higher = thinner rim)
/// - specular_strength -> rim_intensity: Controls how bright the rim is
const sokol = @import("sokol");
const rim_shader = @import("rim_shader");
const Shapes3DPlugin = @import("shapes3d_plugin");

/// Shader identifier - must match what's used in Material.shader
pub const name = "rim";

/// Returns Sokol shader descriptor for the rim shader
pub fn shaderDesc(backend: sokol.gfx.Backend) sokol.gfx.ShaderDesc {
    return rim_shader.rimShaderDesc(backend);
}

/// Returns Sokol pipeline descriptor for the rim shader
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

/// Apply vertex shader uniforms
pub fn applyVsUniforms(params: Shapes3DPlugin.VsUniformParams) void {
    sokol.gfx.applyUniforms(0, sokol.gfx.asRange(&rim_shader.VsParams{
        .mvp = params.mvp,
        .model = params.model,
    }));
}

/// Apply fragment shader uniforms
pub fn applyFsUniforms(params: Shapes3DPlugin.FsUniformParams) void {
    sokol.gfx.applyUniforms(1, sokol.gfx.asRange(&rim_shader.FsParams{
        .light_pos = params.light_pos,
        ._pad0 = 0,
        .view_pos = params.view_pos,
        .rim_power = params.shininess, // Reuse shininess as rim_power
        .light_color = params.light_color,
        .ambient_strength = params.ambient_strength,
        .rim_intensity = params.specular_strength, // Reuse specular_strength as rim_intensity
        ._pad1 = 0,
        ._pad2 = 0,
        ._pad3 = 0,
    }));
}
