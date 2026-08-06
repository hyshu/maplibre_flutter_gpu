// MapLibre LineSDF fragment shader (line-dasharray). The dash pattern is
// stored as a 1-channel SDF atlas (exported from C++, uploaded as R8);
// sample .r instead of the upstream .a.
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
    float props_pad1, props_pad2;
};

layout(binding = 2) uniform LineSDFTilePropsUBO {
    float u_sdfgamma;
    float u_mix;
    float tileprops_pad1, tileprops_pad2;
};

uniform sampler2D u_image;

in vec2 v_normal;
in vec2 v_width2;
in vec2 v_tex_a;
in vec2 v_tex_b;
in float v_gamma_scale;
in float v_dpr;

void main() {
    float dist = length(v_normal) * v_width2.s;

    float blur2 = (u_blur + 1.0 / v_dpr) * v_gamma_scale;
    float alpha = clamp(min(dist - (v_width2.t - blur2), v_width2.s - dist) / blur2, 0.0, 1.0);

    float floorwidth = max(u_floorwidth, 0.01);
    float sdfdist_a = texture(u_image, v_tex_a).r;
    float sdfdist_b = texture(u_image, v_tex_b).r;
    float sdfdist = mix(sdfdist_a, sdfdist_b, u_mix);
    alpha *= smoothstep(0.5 - u_sdfgamma / floorwidth, 0.5 + u_sdfgamma / floorwidth, sdfdist);

    frag_color = u_color * (alpha * u_opacity);
}
