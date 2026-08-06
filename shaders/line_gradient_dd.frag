// MapLibre gradient-line fragment shader with DD blur and opacity.
#version 460 core

layout(location = 0) out vec4 frag_color;

layout(binding = 1) uniform LineEvaluatedPropsUBO {
    vec4 u_color;
    float u_blur;
    float u_opacity;
    float u_gapwidth;
    float u_offset;
    float u_width;
    float u_floorwidth;
    uint u_data_driven_mask;
    float props_pad1;
};

uniform sampler2D u_image;

layout(location = 0) in vec2 v_normal;
layout(location = 1) in vec2 v_width2;
layout(location = 2) in float v_lineprogress;
layout(location = 3) in vec2 v_gamma_dpr;
layout(location = 5) in vec2 v_blur_opacity;

void main() {
    float blur = (u_data_driven_mask & 2u) != 0u ? v_blur_opacity.x : u_blur;
    float opacity = (u_data_driven_mask & 4u) != 0u ? v_blur_opacity.y : u_opacity;
    float dist = length(v_normal) * v_width2.s;
    float blur2 = (blur + 1.0 / v_gamma_dpr.y) * v_gamma_dpr.x;
    float alpha = clamp(
        min(dist - (v_width2.t - blur2), v_width2.s - dist) / blur2,
        0.0,
        1.0
    );
    vec4 color = texture(
        u_image,
        vec2(clamp(v_lineprogress, 0.0, 1.0), 0.5)
    );
    frag_color = color * (alpha * opacity);
}
