@module unlit

@ctype mat4 [4][4]f32

@vs vs
layout(binding=0) uniform vs_params {
    mat4 mvp;
};

layout(location=0) in vec3 a_position;
layout(location=3) in vec4 a_color;

out vec4 v_color;

void main() {
    gl_Position = mvp * vec4(a_position, 1.0);
    v_color = a_color;
}
@end

@fs fs
in vec4 v_color;

out vec4 frag_color;

void main() {
    frag_color = v_color;
}
@end

@program unlit vs fs
