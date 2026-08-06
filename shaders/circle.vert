// MapLibre Circle vertex shader.
// a_pos packs the circle center (*2) plus a 1-bit corner extrusion per axis.
#version 460 core

layout(location = 0) in vec2 a_pos;

layout(binding = 0) uniform CircleDrawableUBO {
    mat4 matrix;
    vec2 extrude_scale;
    // Interpolations (unused: props are layer-constant on this backend)
    float color_t;
    float radius_t;
    float blur_t;
    float opacity_t;
    float stroke_color_t;
    float stroke_width_t;
    float stroke_opacity_t;
    // C++ pads, patched by Dart before upload:
    float camera_to_center_distance; // pad1
    float device_pixel_ratio;        // pad2
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
    float pad1;
} props;

out vec3 v_data;

void main() {
    // unencode the extrusion vector snuck into the a_pos vector
    vec2 extrude = mod(a_pos, 2.0) * 2.0 - 1.0;
    vec2 circle_center = floor(a_pos * 0.5);

    float radius = props.radius;
    float stroke_width = props.stroke_width;

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
            gl_Position.xy += extrude * (radius + stroke_width) * drawable.extrude_scale *
                              gl_Position.w;
        }
    }

    // Faux antialiasing: ~1px blur relative to the circle size
    float antialiasblur = 1.0 / drawable.device_pixel_ratio / (radius + stroke_width);
    v_data = vec3(extrude.x, extrude.y, antialiasblur);
}
