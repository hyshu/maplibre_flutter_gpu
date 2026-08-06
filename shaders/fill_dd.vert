// MapLibre Fill vertex shader - independently data-driven color/opacity.
// Vertex: short2(pos) + float4(packed color range) + float2(opacity range)
// = 28 bytes, normalized by the C++ exporter. Source-function values are
// duplicated into both stops; composite-function values retain both stops.
#version 460 core

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec4 a_color_range;
layout(location = 2) in vec2 a_opacity_range;

layout(binding = 0) uniform FillDrawableUBO {
    mat4 matrix;
    float color_t;
    float opacity_t;
    uint data_driven_mask; // bit0=color, bit1=opacity
    float pad2;
} drawable;

layout(binding = 1) uniform FillEvaluatedPropsUBO {
    vec4 color;
    vec4 outline_color;
    float opacity;
    float fade;
    float from_scale;
    float to_scale;
} props;

out vec4 v_color;
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
    if ((drawable.data_driven_mask & 1u) != 0u) {
        vec4 min_color = decode_color(a_color_range.xy);
        vec4 max_color = decode_color(a_color_range.zw);
        v_color = mix(min_color, max_color, drawable.color_t);
    } else {
        v_color = props.color;
    }

    v_opacity = (drawable.data_driven_mask & 2u) != 0u
        ? mix(a_opacity_range.x, a_opacity_range.y, drawable.opacity_t)
        : props.opacity;

    gl_Position = drawable.matrix * vec4(a_pos, 0.0, 1.0);
}
