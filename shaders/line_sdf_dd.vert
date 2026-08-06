// MapLibre dashed-line (SDF) vertex shader for the normalized 120-byte DD
// line layout. Geometry-affecting values are selected before projection.
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

layout(binding = 0) uniform LineSDFDrawableUBO {
    mat4 u_matrix;
    vec2 u_patternscale_a;
    vec2 u_patternscale_b;
    float u_tex_y_a;
    float u_tex_y_b;
    float u_ratio;
    float u_color_t;
    float u_blur_t;
    float u_opacity_t;
    float u_gapwidth_t;
    float u_offset_t;
    float u_width_t;
    float u_floorwidth_t;
    float u_device_pixel_ratio;
    float drawable_pad2;
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

layout(binding = 3) uniform MapGlobalUBO {
    vec2 u_units_to_pixels;
    vec2 u_world_size;
};

layout(location = 0) out vec2 v_normal;
layout(location = 1) out vec2 v_width2;
layout(location = 2) out vec2 v_tex_a;
layout(location = 3) out vec2 v_tex_b;
layout(location = 4) out vec2 v_gamma_dpr;
layout(location = 6) out vec4 v_color;
layout(location = 7) out vec4 v_paint; // blur, opacity, floor-width, pad
layout(location = 8) flat out vec4 v_unused_pattern_from;
layout(location = 9) flat out vec4 v_unused_pattern_to;

vec2 unpack_float(const float packed_value) {
    int packed_int_value = int(packed_value);
    int v0 = packed_int_value / 256;
    return vec2(v0, packed_int_value - v0 * 256);
}

vec4 decode_color(const vec2 encoded_color) {
    return vec4(
        unpack_float(encoded_color.x) / 255.0,
        unpack_float(encoded_color.y) / 255.0
    );
}

vec4 mix_color_range(vec4 range, float t) {
    return mix(decode_color(range.xy), decode_color(range.zw), t);
}

void main() {
    float dpr = max(u_device_pixel_ratio, 0.000001);
    float antialiasing = 1.0 / dpr / 2.0;

    vec4 attribute_color = mix_color_range(a_color_range, u_color_t);
    float attribute_blur = mix(a_blur_range.x, a_blur_range.y, u_blur_t);
    float attribute_opacity = mix(a_opacity_range.x, a_opacity_range.y, u_opacity_t);
    float attribute_gapwidth = mix(a_gapwidth_range.x, a_gapwidth_range.y, u_gapwidth_t);
    float attribute_offset = mix(a_offset_range.x, a_offset_range.y, u_offset_t);
    float attribute_width = mix(a_width_range.x, a_width_range.y, u_width_t);
    float attribute_floorwidth = mix(
        a_floorwidth_range.x, a_floorwidth_range.y, u_floorwidth_t);

    float gapwidth = ((u_data_driven_mask & 8u) != 0u
        ? attribute_gapwidth : u_gapwidth) / 2.0;
    float offset = -((u_data_driven_mask & 16u) != 0u
        ? attribute_offset : u_offset);
    float width = (u_data_driven_mask & 32u) != 0u
        ? attribute_width : u_width;
    float floorwidth = max((u_data_driven_mask & 64u) != 0u
        ? attribute_floorwidth : u_floorwidth, 0.01);

    vec2 a_extrude = a_data.xy - 128.0;
    float a_direction = mod(a_data.z, 4.0) - 1.0;
    float a_linesofar =
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
    v_tex_a = vec2(
        a_linesofar * u_patternscale_a.x / floorwidth,
        normal.y * u_patternscale_a.y + u_tex_y_a
    );
    v_tex_b = vec2(
        a_linesofar * u_patternscale_b.x / floorwidth,
        normal.y * u_patternscale_b.y + u_tex_y_b
    );
    v_width2 = vec2(outset, inset);
    v_color = attribute_color;
    v_paint = vec4(attribute_blur, attribute_opacity, attribute_floorwidth, 0.0);
    v_unused_pattern_from = a_pattern_from;
    v_unused_pattern_to = a_pattern_to;

}
