// MapLibre dashed-line SDF fragment shader with DD color/blur/opacity/floor.
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

layout(binding = 2) uniform LineSDFTilePropsUBO {
    float u_sdfgamma;
    float u_mix;
    float tileprops_pad1;
    float tileprops_pad2;
};

uniform sampler2D u_image;

layout(location = 0) in vec2 v_normal;
layout(location = 1) in vec2 v_width2;
layout(location = 2) in vec2 v_tex_a;
layout(location = 3) in vec2 v_tex_b;
layout(location = 4) in vec2 v_gamma_dpr;
layout(location = 6) in vec4 v_color;
layout(location = 7) in vec4 v_paint;

void main() {
    vec4 color = (u_data_driven_mask & 1u) != 0u ? v_color : u_color;
    float blur = (u_data_driven_mask & 2u) != 0u ? v_paint.x : u_blur;
    float opacity = (u_data_driven_mask & 4u) != 0u ? v_paint.y : u_opacity;
    float floorwidth = max((u_data_driven_mask & 64u) != 0u
        ? v_paint.z : u_floorwidth, 0.01);

    float dist = length(v_normal) * v_width2.s;
    float blur2 = (blur + 1.0 / v_gamma_dpr.y) * v_gamma_dpr.x;
    float alpha = clamp(
        min(dist - (v_width2.t - blur2), v_width2.s - dist) / blur2,
        0.0,
        1.0
    );

    float sdfdist_a = texture(u_image, v_tex_a).r;
    float sdfdist_b = texture(u_image, v_tex_b).r;
    float sdfdist = mix(sdfdist_a, sdfdist_b, u_mix);
    alpha *= smoothstep(
        0.5 - u_sdfgamma / floorwidth,
        0.5 + u_sdfgamma / floorwidth,
        sdfdist
    );
    frag_color = color * (alpha * opacity);
}
