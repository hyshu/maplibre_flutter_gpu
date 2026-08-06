// MapLibre Circle vertex shader - independently data-driven paint values.
// Vertex: short2(pos) + color float4 + five scalar float2 ranges +
// stroke-color float4 = 76 bytes, normalized by the C++ exporter. Source
// values are duplicated into both stops; composite values retain both stops.
#version 460 core

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec4 a_color_range;
layout(location = 2) in vec2 a_radius_range;
layout(location = 3) in vec2 a_blur_range;
layout(location = 4) in vec2 a_opacity_range;
layout(location = 5) in vec4 a_stroke_color_range;
layout(location = 6) in vec2 a_stroke_width_range;
layout(location = 7) in vec2 a_stroke_opacity_range;

layout(binding = 0) uniform CircleDrawableUBO {
    mat4 matrix;
    vec2 extrude_scale;
    float color_t;
    float radius_t;
    float blur_t;
    float opacity_t;
    float stroke_color_t;
    float stroke_width_t;
    float stroke_opacity_t;
    float camera_to_center_distance;
    float device_pixel_ratio;
    float pad3;
} drawable;

layout(binding = 1) uniform CircleEvaluatedPropsUBO {
    vec4 color;
    vec4 stroke_color;
    float radius;
    float blur;
    float opacity;
    float stroke_width;
    float stroke_opacity;
    int scale_with_map;
    int pitch_with_map;
    uint data_driven_mask; // native pad1, patched by Dart at byte 60
} props;

layout(location = 0) out vec2 v_extrude;
layout(location = 1) out vec4 v_circle_data; // AA blur, radius, blur, opacity
layout(location = 2) out vec4 v_color;
layout(location = 3) out vec4 v_stroke_color;
layout(location = 4) out vec2 v_stroke_data; // width, opacity

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
    vec4 color = mix_color_range(a_color_range, drawable.color_t);
    float attribute_radius = mix(a_radius_range.x, a_radius_range.y, drawable.radius_t);
    float blur = mix(a_blur_range.x, a_blur_range.y, drawable.blur_t);
    float opacity = mix(a_opacity_range.x, a_opacity_range.y, drawable.opacity_t);
    vec4 stroke_color = mix_color_range(a_stroke_color_range, drawable.stroke_color_t);
    float attribute_stroke_width = mix(
        a_stroke_width_range.x, a_stroke_width_range.y, drawable.stroke_width_t);
    float stroke_opacity = mix(
        a_stroke_opacity_range.x, a_stroke_opacity_range.y, drawable.stroke_opacity_t);

    // Radius and stroke width affect geometry, so select their layer constants
    // here when those properties are not data-driven. The fragment selects all
    // seven values the same way, matching MapLibre's shader specialization.
    float radius = (props.data_driven_mask & 2u) != 0u ? attribute_radius : props.radius;
    float stroke_width = (props.data_driven_mask & 32u) != 0u
        ? attribute_stroke_width
        : props.stroke_width;

    vec2 extrude = mod(a_pos, 2.0) * 2.0 - 1.0;
    vec2 circle_center = floor(a_pos * 0.5);

    if (props.pitch_with_map != 0) {
        vec2 corner_position = circle_center;
        if (props.scale_with_map != 0) {
            corner_position += extrude * (radius + stroke_width) * drawable.extrude_scale;
        } else {
            vec4 projected_center = drawable.matrix * vec4(circle_center, 0.0, 1.0);
            corner_position += extrude * (radius + stroke_width) * drawable.extrude_scale *
                               (projected_center.w / drawable.camera_to_center_distance);
        }
        gl_Position = drawable.matrix * vec4(corner_position, 0.0, 1.0);
    } else {
        gl_Position = drawable.matrix * vec4(circle_center, 0.0, 1.0);
        if (props.scale_with_map != 0) {
            gl_Position.xy += extrude * (radius + stroke_width) * drawable.extrude_scale *
                              drawable.camera_to_center_distance;
        } else {
            gl_Position.xy += extrude * (radius + stroke_width) * drawable.extrude_scale * gl_Position.w;
        }
    }

    float antialiasblur = 1.0 / drawable.device_pixel_ratio / (radius + stroke_width);
    v_extrude = extrude;
    v_circle_data = vec4(antialiasblur, attribute_radius, blur, opacity);
    v_color = color;
    v_stroke_color = stroke_color;
    v_stroke_data = vec2(attribute_stroke_width, stroke_opacity);
}
