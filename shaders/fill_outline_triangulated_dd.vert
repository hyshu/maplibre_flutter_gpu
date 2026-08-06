// MapLibre triangulated fill outline with independently data-driven
// outline-color and opacity. The first 8 bytes retain LineLayoutVertex;
// normalized source/composite paint ranges follow at offsets 8 and 24.
#version 460 core

#define scale 0.015873016

layout(location = 0) in vec2 a_pos_normal;
layout(location = 1) in vec4 a_data;
layout(location = 2) in vec4 a_outline_color_range;
layout(location = 3) in vec2 a_opacity_range;

layout(binding = 0) uniform FillOutlineTriangulatedDrawableUBO {
    mat4 u_matrix;
    float u_ratio;
    // Native pad1, patched by Dart with the device pixel ratio.
    float u_device_pixel_ratio;
    // Native pad2/pad3 carry MapLibre's per-frame interpolation factors.
    float u_outline_color_t;
    float u_opacity_t;
};

layout(binding = 1) uniform FillEvaluatedPropsUBO {
    vec4 color;
    vec4 outline_color;
    float opacity;
    // Native fade is unused by unpatterned outlines and carries the mask:
    // bit0=outline-color, bit1=opacity.
    uint data_driven_mask;
    float from_scale;
    float to_scale;
} props;

layout(binding = 2) uniform MapGlobalUBO {
    vec2 u_units_to_pixels;
    vec2 u_world_size;
};

out vec2 v_normal;
out float v_width;
out float v_gamma_scale;
out float v_dpr;
out vec4 v_outline_color;
out float v_opacity;

// Exact port of MapLibre's unpack_float/decode_color helpers. Paint binders
// encode premultiplied RG and BA byte pairs as exactly representable floats.
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

void main() {
    float dpr = max(u_device_pixel_ratio, 0.000001);
    float antialiasing = 0.5 / dpr;

    vec2 a_extrude = a_data.xy - 128.0;

    vec2 pos = floor(a_pos_normal * 0.5);
    vec2 normal = a_pos_normal - 2.0 * pos;
    normal.y = normal.y * 2.0 - 1.0;
    v_normal = normal;

    // Keep enough transparent support for perspective-compressed outlines.
    // The fragment shader determines visible coverage in physical pixels.
    float halfwidth = 0.5;
    float outset = halfwidth + antialiasing;
    vec2 dist = outset * a_extrude * scale;

    vec4 projected_extrude = u_matrix * vec4(dist / u_ratio, 0.0, 0.0);
    gl_Position = u_matrix * vec4(pos, 0.0, 1.0) + projected_extrude;

    float extrude_length_without_perspective = length(dist);
    float extrude_length_with_perspective =
        length(projected_extrude.xy / gl_Position.w * u_units_to_pixels);
    v_gamma_scale = extrude_length_without_perspective /
                    extrude_length_with_perspective;
    v_width = outset;
    v_dpr = dpr;
    if ((props.data_driven_mask & 1u) != 0u) {
        vec4 min_color = decode_color(a_outline_color_range.xy);
        vec4 max_color = decode_color(a_outline_color_range.zw);
        v_outline_color = mix(min_color, max_color, u_outline_color_t);
    } else {
        v_outline_color = props.outline_color;
    }

    v_opacity = (props.data_driven_mask & 2u) != 0u
        ? mix(a_opacity_range.x, a_opacity_range.y, u_opacity_t)
        : props.opacity;
}
