// MapLibre triangulated fill-outline fragment shader with vertex-evaluated
// outline paint values.
#version 460 core

layout(location = 0) out vec4 frag_color;

in vec2 v_normal;
in float v_width;
in float v_gamma_scale;
in float v_dpr;
in vec4 v_outline_color;
in float v_opacity;

void main() {
    float dist_line = length(v_normal) * v_width;
    float dist_px =
        dist_line * v_dpr / max(v_gamma_scale, 0.000001);
    float alpha = 1.0 - smoothstep(0.0, 1.0, dist_px);
    frag_color = v_outline_color * (alpha * v_opacity);
}
