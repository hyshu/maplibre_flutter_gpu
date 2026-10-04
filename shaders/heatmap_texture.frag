#version 460 core

layout(binding = 0) uniform HeatmapTexturePropsUBO {
    mat4 matrix;
    float opacity;
    float pad1;
    float pad2;
    float pad3;
} props;

uniform sampler2D u_image;
uniform sampler2D u_color_ramp;

layout(location = 0) in vec2 v_pos;
layout(location = 0) out vec4 frag_color;

void main() {
    float density = texture(u_image, v_pos).r;
    vec4 color = texture(u_color_ramp, vec2(density, 0.5));
    frag_color = color * props.opacity;
}
