// MapLibre sprite-pattern line fragment shader with DD blur, opacity, and TLBR.
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

layout(binding = 2) uniform LinePatternTilePropsUBO {
    vec4 u_pattern_from;
    vec4 u_pattern_to;
    vec4 u_scale;
    vec2 u_texsize;
    float u_fade;
    float tileprops_pad1;
};

uniform sampler2D u_image;

layout(location = 0) in vec2 v_normal;
layout(location = 1) in vec2 v_width2;
layout(location = 2) in float v_linesofar;
layout(location = 3) in vec2 v_gamma_dpr;
layout(location = 5) in vec2 v_blur_opacity;
layout(location = 6) in vec4 v_pattern_from;
layout(location = 7) in vec4 v_pattern_to;

void main() {
    float blur = (u_data_driven_mask & 2u) != 0u ? v_blur_opacity.x : u_blur;
    float opacity = (u_data_driven_mask & 4u) != 0u ? v_blur_opacity.y : u_opacity;
    vec4 pattern_from = (u_data_driven_mask & 128u) != 0u
        ? v_pattern_from : u_pattern_from;
    vec4 pattern_to = (u_data_driven_mask & 128u) != 0u
        ? v_pattern_to : u_pattern_to;

    vec2 pattern_tl_a = pattern_from.xy;
    vec2 pattern_br_a = pattern_from.zw;
    vec2 pattern_tl_b = pattern_to.xy;
    vec2 pattern_br_b = pattern_to.zw;

    float pixel_ratio = u_scale.x;
    float tile_zoom_ratio = u_scale.y;
    float from_scale = u_scale.z;
    float to_scale = u_scale.w;
    vec2 display_size_a = (pattern_br_a - pattern_tl_a) / pixel_ratio;
    vec2 display_size_b = (pattern_br_b - pattern_tl_b) / pixel_ratio;
    vec2 pattern_size_a = vec2(
        display_size_a.x * from_scale / tile_zoom_ratio,
        display_size_a.y
    );
    vec2 pattern_size_b = vec2(
        display_size_b.x * to_scale / tile_zoom_ratio,
        display_size_b.y
    );

    float dist = length(v_normal) * v_width2.s;
    float blur2 = (blur + 1.0 / v_gamma_dpr.y) * v_gamma_dpr.x;
    float alpha = clamp(
        min(dist - (v_width2.t - blur2), v_width2.s - dist) / blur2,
        0.0,
        1.0
    );

    float x_a = mod(v_linesofar / max(pattern_size_a.x, 0.01), 1.0);
    float x_b = mod(v_linesofar / max(pattern_size_b.x, 0.01), 1.0);
    float y_a = 0.5 + (
        v_normal.y * clamp(v_width2.s, 0.0, (pattern_size_a.y + 2.0) / 2.0) /
        pattern_size_a.y
    );
    float y_b = 0.5 + (
        v_normal.y * clamp(v_width2.s, 0.0, (pattern_size_b.y + 2.0) / 2.0) /
        pattern_size_b.y
    );
    vec2 texel_size = 1.0 / u_texsize;
    vec2 pos_a = mix(
        pattern_tl_a * texel_size,
        pattern_br_a * texel_size,
        vec2(x_a, y_a)
    );
    vec2 pos_b = mix(
        pattern_tl_b * texel_size,
        pattern_br_b * texel_size,
        vec2(x_b, y_b)
    );
    vec4 color = mix(texture(u_image, pos_a), texture(u_image, pos_b), u_fade);
    frag_color = color * (alpha * opacity);
}
