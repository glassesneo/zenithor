/// Unlit Shader - Simple vertex color rendering without lighting
///
/// This shader passes through vertex colors without any lighting calculations.
/// Ideal for UI elements, wireframes, debug visualization, and objects that
/// should maintain their exact colors without shading.
const sokol = @import("sokol");
const unlit_shader = @import("unlit_shader");

/// Shader identifier
pub const name = "unlit";

/// Unlit shader parameters (none - uses vertex colors only)
pub const Params = struct {
    // Unlit shader has no per-material parameters
    // Color comes from vertex data
};

/// Returns default parameters
pub fn defaultParams() Params {
    return .{};
}

/// Returns Sokol shader descriptor for the unlit shader
pub fn shaderDesc(backend: sokol.gfx.Backend) sokol.gfx.ShaderDesc {
    return unlit_shader.unlitShaderDesc(backend);
}

/// Returns Sokol pipeline descriptor for the unlit shader
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
