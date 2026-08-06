// MapLibre Line fragment shader — full port: antialiased edges with
// line-blur and casing support via v_width2 (outset/inset from gap-width).
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

in vec2 v_normal;
in vec2 v_width2;
in float v_gamma_scale;
in float v_dpr;

void main() {
    // Distance of this pixel from the line center, in pixels
    float dist = length(v_normal) * v_width2.s;

    // Antialias fade: fades in at the inset (casing gap) and out at the outset
    float blur2 = (u_blur + 1.0 / v_dpr) * v_gamma_scale;
    float alpha = clamp(min(dist - (v_width2.t - blur2), v_width2.s - dist) / blur2, 0.0, 1.0);

    frag_color = u_color * (alpha * u_opacity);
}
