@module rim

@ctype mat4 [4][4]f32
@ctype vec4 [4]f32
@ctype vec3 [3]f32

@vs vs
layout(binding=0) uniform vs_params {
    mat4 mvp;
    mat4 model;
};

layout(location=0) in vec3 a_position;
layout(location=1) in vec3 a_normal;
layout(location=3) in vec4 a_color;

out vec3 v_world_pos;
out vec3 v_normal;
out vec4 v_color;

void main() {
    vec4 world_pos = model * vec4(a_position, 1.0);
    v_world_pos = world_pos.xyz;
    v_normal = mat3(model) * a_normal;
    v_color = a_color;
    gl_Position = mvp * vec4(a_position, 1.0);
}
@end

@fs fs
layout(binding=1) uniform fs_params {
    vec3 light_pos;
    float _pad0;
    vec3 view_pos;
    float rim_power;        // Fresnel exponent (uses Material.shininess)
    vec3 light_color;
    float ambient_strength;
    float rim_intensity;    // Rim strength (uses Material.specular_strength)
    float _pad1;
    float _pad2;
    float _pad3;
};

in vec3 v_world_pos;
in vec3 v_normal;
in vec4 v_color;

out vec4 frag_color;

void main() {
    vec3 N = normalize(v_normal);
    vec3 V = normalize(view_pos - v_world_pos);
    vec3 L = normalize(light_pos - v_world_pos);

    // Basic diffuse lighting
    float diff = max(dot(N, L), 0.0);
    vec3 diffuse = diff * light_color;

    // Ambient
    vec3 ambient = ambient_strength * light_color;

    // Fresnel rim lighting
    // The rim effect is strongest when viewing at grazing angles (edges)
    float fresnel = 1.0 - max(dot(N, V), 0.0);
    float rim = pow(fresnel, rim_power) * rim_intensity;
    vec3 rim_contribution = rim * light_color;

    // Combine: base color with diffuse + ambient, plus rim highlight
    vec3 result = (ambient + diffuse) * v_color.rgb + rim_contribution;
    frag_color = vec4(result, v_color.a);
}
@end

@program rim vs fs
