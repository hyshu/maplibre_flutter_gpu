// MapLibre LineGradient fragment shader — samples the color ramp texture
// (256x1 RGBA, premultiplied) by line progress.
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

uniform sampler2D u_image;

in vec2 v_normal;
in vec2 v_width2;
in float v_lineprogress;
in float v_gamma_scale;
in float v_dpr;

void main() {
    float dist = length(v_normal) * v_width2.s;

    float blur2 = (u_blur + 1.0 / v_dpr) * v_gamma_scale;
    float alpha = clamp(min(dist - (v_width2.t - blur2), v_width2.s - dist) / blur2, 0.0, 1.0);

    // Color ramp is premultiplied RGBA, matching MapLibre's render target.
    vec4 c = texture(u_image, vec2(clamp(v_lineprogress, 0.0, 1.0), 0.5));
    frag_color = c * (alpha * u_opacity);
}
