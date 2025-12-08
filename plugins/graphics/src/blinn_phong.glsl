@module blinn_phong

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
    float shininess;
    vec3 light_color;
    float ambient_strength;
    float specular_strength;
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
    vec3 L = normalize(light_pos - v_world_pos);
    vec3 V = normalize(view_pos - v_world_pos);
    vec3 H = normalize(L + V);

    // Ambient
    vec3 ambient = ambient_strength * light_color;

    // Diffuse
    float diff = max(dot(N, L), 0.0);
    vec3 diffuse = diff * light_color;

    // Specular (Blinn-Phong)
    float spec = pow(max(dot(N, H), 0.0), shininess);
    vec3 specular = specular_strength * spec * light_color;

    vec3 result = (ambient + diffuse + specular) * v_color.rgb;
    frag_color = vec4(result, v_color.a);
}
@end

@program blinn_phong vs fs
