@module pbr

@ctype mat4 [4][4]f32
@ctype vec4 [4]f32
@ctype vec3 [3]f32

// PBR shader with metallic-roughness workflow
// Vertex attributes match sokol.shape layout:
// location=0: position (vec3)
// location=1: normal (vec3)
// location=2: texcoord (vec2)
// location=3: color (vec4)

@vs vs
layout(binding=0) uniform vs_params {
    mat4 mvp;
    mat4 model;
};

layout(location=0) in vec3 a_position;
layout(location=1) in vec3 a_normal;
layout(location=2) in vec2 a_texcoord;
layout(location=3) in vec4 a_color;

out vec3 v_world_pos;
out vec3 v_normal;
out vec2 v_texcoord;
out vec4 v_color;

void main() {
    vec4 world_pos = model * vec4(a_position, 1.0);
    v_world_pos = world_pos.xyz;
    // NOTE: mat3(model) is only correct for uniform scale (equal X, Y, Z).
    // Non-uniform scaling causes incorrect lighting - would require inverse-transpose:
    // transpose(inverse(mat3(model))). Accept visual artifacts or use uniform scale.
    v_normal = mat3(model) * a_normal;
    v_texcoord = a_texcoord;
    v_color = a_color;
    gl_Position = mvp * vec4(a_position, 1.0);
}
@end

@fs fs
layout(binding=1) uniform fs_params {
    vec3 light_pos;
    float _pad0;
    vec3 view_pos;
    float metallic;
    vec3 light_color;
    float roughness;
    float ambient_strength;
    float _pad1;
    float _pad2;
    float _pad3;
};

in vec3 v_world_pos;
in vec3 v_normal;
in vec2 v_texcoord;
in vec4 v_color;

out vec4 frag_color;

const float PI = 3.14159265359;

// Normal Distribution Function (GGX/Trowbridge-Reitz)
float distributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    return a2 / (PI * denom * denom);
}

// Geometry function (Schlick-GGX)
float geometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float geometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    return geometrySchlickGGX(NdotV, roughness) * geometrySchlickGGX(NdotL, roughness);
}

// Fresnel-Schlick approximation
vec3 fresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

void main() {
    vec3 albedo = v_color.rgb;
    vec3 N = normalize(v_normal);
    vec3 V = normalize(view_pos - v_world_pos);
    vec3 L = normalize(light_pos - v_world_pos);
    vec3 H = normalize(V + L);

    // Calculate F0 (reflectance at normal incidence)
    vec3 F0 = vec3(0.04);
    F0 = mix(F0, albedo, metallic);

    // Cook-Torrance BRDF
    float NDF = distributionGGX(N, H, roughness);
    float G = geometrySmith(N, V, L, roughness);
    vec3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);

    vec3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specular = numerator / denominator;

    // Energy conservation
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - metallic;

    float NdotL = max(dot(N, L), 0.0);

    // Ambient
    vec3 ambient = ambient_strength * albedo;

    // Final color
    vec3 Lo = (kD * albedo / PI + specular) * light_color * NdotL;
    vec3 color = ambient + Lo;

    // Tone mapping (Reinhard)
    color = color / (color + vec3(1.0));

    frag_color = vec4(color, v_color.a);
}
@end

@program pbr vs fs
