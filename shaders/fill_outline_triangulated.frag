// MapLibre triangulated fill-outline fragment shader.
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

in vec2 v_normal;
in float v_width;
in float v_gamma_scale;
in float v_dpr;

void main() {
    float dist_line = length(v_normal) * v_width;
    float dist_px =
        dist_line * v_dpr / max(v_gamma_scale, 0.000001);
    // Match FillOutlineShader's OpenGL physical-pixel coverage curve. Unlike
    // the generic triangulated-line equation, this has no opaque plateau.
    float alpha = 1.0 - smoothstep(0.0, 1.0, dist_px);
    frag_color = props.outline_color * (alpha * props.opacity);
}
