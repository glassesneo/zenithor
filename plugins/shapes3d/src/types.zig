/// Shared types for Shapes3D shaders
///
/// This module defines types shared between shader specs and the main plugin,
/// avoiding circular dependencies.
const sokol = @import("sokol");

/// 4x4 matrix type (row-major)
pub const Mat4 = [4][4]f32;

/// Vertex shader uniform parameters
/// All shaders receive the same VS params; they use what they need.
pub const VsUniformParams = struct {
    mvp: Mat4,
    model: Mat4,
};

/// Fragment shader uniform parameters
/// All shaders receive the same FS params; they use what they need.
/// Custom shaders can reuse fields with different semantics (documented in shader spec).
pub const FsUniformParams = struct {
    // Lighting
    light_pos: [3]f32,
    view_pos: [3]f32,
    light_color: [3]f32,
    ambient_strength: f32,
    // Material params (usage varies by shader)
    // - blinn_phong: shininess, specular_strength
    // - pbr: metallic, roughness
    // - rim: rim_power (via shininess), rim_intensity (via specular_strength)
    shininess: f32,
    specular_strength: f32,
    metallic: f32,
    roughness: f32,
};

/// Shader apply function types (for ShaderEntry function pointers)
pub const ApplyVsUniformsFn = *const fn (params: VsUniformParams) void;
pub const ApplyFsUniformsFn = *const fn (params: FsUniformParams) void;

/// Helper to convert sokol.gfx types to ranges
pub fn asRange(ptr: anytype) sokol.gfx.Range {
    return sokol.gfx.asRange(ptr);
}
