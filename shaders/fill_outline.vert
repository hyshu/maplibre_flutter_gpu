// MapLibre Fill vertex shader - packed short2 as single uint
#version 460 core

layout(location = 0) in vec2 a_pos;

layout(binding = 0) uniform FillDrawableUBO {
    mat4 matrix;
    float color_t;
    float opacity_t;
    float pad1;
    float pad2;
} drawable;

layout(binding = 1) uniform FillEvaluatedPropsUBO {
    vec4 color;
    vec4 outline_color;
    float opacity;
    float fade;
    float from_scale;
    float to_scale;
} props;

void main() {
    gl_Position = drawable.matrix * vec4(a_pos, 0.0, 1.0);
}
