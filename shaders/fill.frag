// MapLibre Fill fragment shader - ported from Metal to GLSL 460
#version 460 core

layout(location = 0) out vec4 frag_color;

layout(binding = 1) uniform FillEvaluatedPropsUBO {
    vec4 color;
    vec4 outline_color;
    float opacity;
    float fade;
    float from_scale;
    float to_scale;
} props;

void main() {
    // MapLibre colors and render targets use premultiplied alpha.
    frag_color = props.color * props.opacity;
}
