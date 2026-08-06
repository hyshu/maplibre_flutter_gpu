// Fill fragment shader for cross-tile merged commands.
// Same color math as fill.frag for already projected screen-space geometry.
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
    frag_color = props.color * props.opacity;
}
