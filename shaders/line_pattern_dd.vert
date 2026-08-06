// MapLibre sprite-pattern line vertex shader for the normalized 120-byte DD
// line layout. Pattern endpoints are raw ushort4 TLBR coordinates, not stops.
#version 460 core

#define scale 0.015873016
#define LINE_DISTANCE_SCALE 2.0

layout(location = 0) in vec2 a_pos_normal;
layout(location = 1) in vec4 a_data;
layout(location = 2) in vec4 a_color_range;
layout(location = 3) in vec2 a_blur_range;
layout(location = 4) in vec2 a_opacity_range;
layout(location = 5) in vec2 a_gapwidth_range;
layout(location = 6) in vec2 a_offset_range;
layout(location = 7) in vec2 a_width_range;
layout(location = 8) in vec2 a_floorwidth_range;
layout(location = 9) in vec4 a_pattern_from;
layout(location = 10) in vec4 a_pattern_to;

layout(binding = 0) uniform LinePatternDrawableUBO {
    mat4 u_matrix;
    float u_ratio;
    float u_blur_t;
    float u_opacity_t;
    float u_gapwidth_t;
    float u_offset_t;
    float u_width_t;
    float u_pattern_from_t;
    float u_pattern_to_t;
};

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

layout(binding = 3) uniform MapGlobalUBO {
    vec2 u_units_to_pixels;
    vec2 u_world_size;
};

layout(location = 0) out vec2 v_normal;
layout(location = 1) out vec2 v_width2;
layout(location = 2) out float v_linesofar;
layout(location = 3) out vec2 v_gamma_dpr;
layout(location = 5) out vec2 v_blur_opacity;
layout(location = 6) out vec4 v_pattern_from;
layout(location = 7) out vec4 v_pattern_to;
layout(location = 8) out vec4 v_unused_color;
layout(location = 9) out vec2 v_unused_floorwidth;

void main() {
    float dpr = max(u_scale.x, 0.000001);
    float antialiasing = 1.0 / dpr / 2.0;

    float attribute_blur = mix(a_blur_range.x, a_blur_range.y, u_blur_t);
    float attribute_opacity = mix(a_opacity_range.x, a_opacity_range.y, u_opacity_t);
    float attribute_gapwidth = mix(a_gapwidth_range.x, a_gapwidth_range.y, u_gapwidth_t);
    float attribute_offset = mix(a_offset_range.x, a_offset_range.y, u_offset_t);
    float attribute_width = mix(a_width_range.x, a_width_range.y, u_width_t);

    float gapwidth = ((u_data_driven_mask & 8u) != 0u
        ? attribute_gapwidth : u_gapwidth) / 2.0;
    float offset = -((u_data_driven_mask & 16u) != 0u
        ? attribute_offset : u_offset);
    float width = (u_data_driven_mask & 32u) != 0u
        ? attribute_width : u_width;

    vec2 a_extrude = a_data.xy - 128.0;
    float a_direction = mod(a_data.z, 4.0) - 1.0;
    v_linesofar =
        (floor(a_data.z / 4.0) + a_data.w * 64.0) * LINE_DISTANCE_SCALE;
    vec2 pos = floor(a_pos_normal * 0.5);
    vec2 normal = a_pos_normal - 2.0 * pos;
    normal.y = normal.y * 2.0 - 1.0;
    v_normal = normal;

    float halfwidth = width / 2.0;
    float inset = gapwidth + (gapwidth > 0.0 ? antialiasing : 0.0);
    float outset = gapwidth + halfwidth * (gapwidth > 0.0 ? 2.0 : 1.0) +
                   (halfwidth == 0.0 ? 0.0 : antialiasing);
    vec2 dist = outset * a_extrude * scale;

    float u = 0.5 * a_direction;
    float t = 1.0 - abs(u);
    vec2 offset2 = offset * a_extrude * scale * normal.y * mat2(t, -u, u, t);

    vec4 projected_extrude = u_matrix * vec4(dist / u_ratio, 0.0, 0.0);
    gl_Position = u_matrix * vec4(pos + offset2 / u_ratio, 0.0, 1.0) + projected_extrude;

    float extrude_length_without_perspective = length(dist);
    float extrude_length_with_perspective =
        length(projected_extrude.xy / gl_Position.w * u_units_to_pixels);
    v_gamma_dpr = vec2(
        extrude_length_without_perspective / extrude_length_with_perspective,
        dpr
    );
    v_width2 = vec2(outset, inset);
    v_blur_opacity = vec2(attribute_blur, attribute_opacity);
    // Upstream passes data-driven pattern TLBR values directly. The drawable
    // pattern interpolation factors are intentionally not applied here.
    v_pattern_from = a_pattern_from;
    v_pattern_to = a_pattern_to;
    v_unused_color = a_color_range;
    v_unused_floorwidth = a_floorwidth_range;

}
