// MapLibre Circle fragment shader - selects seven independently data-driven
// paint values from zoom-mixed varyings or evaluated layer constants.
#version 460 core

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
    uint data_driven_mask;
} props;

layout(location = 0) in vec2 v_extrude;
layout(location = 1) in vec4 v_circle_data; // AA blur, radius, blur, opacity
layout(location = 2) in vec4 v_color;
layout(location = 3) in vec4 v_stroke_color;
layout(location = 4) in vec2 v_stroke_data; // width, opacity

out vec4 frag_color;

void main() {
    vec4 color = (props.data_driven_mask & 1u) != 0u ? v_color : props.color;
    float radius = (props.data_driven_mask & 2u) != 0u ? v_circle_data.y : props.radius;
    float blur = (props.data_driven_mask & 4u) != 0u ? v_circle_data.z : props.blur;
    float opacity = (props.data_driven_mask & 8u) != 0u ? v_circle_data.w : props.opacity;
    vec4 stroke_color = (props.data_driven_mask & 16u) != 0u ? v_stroke_color : props.stroke_color;
    float stroke_width = (props.data_driven_mask & 32u) != 0u ? v_stroke_data.x : props.stroke_width;
    float stroke_opacity = (props.data_driven_mask & 64u) != 0u ? v_stroke_data.y : props.stroke_opacity;

    float extrude_length = length(v_extrude);
    float antialiased_blur = -max(blur, v_circle_data.x);
    float opacity_t = smoothstep(0.0, antialiased_blur, extrude_length - 1.0);
    float color_t = stroke_width < 0.01
        ? 0.0
        : smoothstep(antialiased_blur, 0.0,
                     extrude_length - radius / (radius + stroke_width));

    frag_color = opacity_t * mix(color * opacity,
                                 stroke_color * stroke_opacity,
                                 color_t);
}
