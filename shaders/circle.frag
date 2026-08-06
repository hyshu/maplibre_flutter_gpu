// MapLibre Circle fragment shader: fill + stroke ring with faux-AA blur.
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
    float pad1;
} props;

in vec3 v_data;

out vec4 frag_color;

void main() {
    vec2 extrude = v_data.xy;
    float extrude_length = length(extrude);

    float antialiasblur = v_data.z;
    float antialiased_blur = -max(props.blur, antialiasblur);

    float opacity_t = smoothstep(0.0, antialiased_blur, extrude_length - 1.0);

    float color_t = props.stroke_width < 0.01
        ? 0.0
        : smoothstep(antialiased_blur, 0.0,
                     extrude_length - props.radius / (props.radius + props.stroke_width));

    frag_color = opacity_t * mix(props.color * props.opacity,
                                 props.stroke_color * props.stroke_opacity,
                                 color_t);
}
