// MapLibre Raster fragment shader: raster-* paint properties (opacity,
// hue-rotate via spin weights, saturation, contrast, brightness).
// The drawable path binds the same texture to image0/image1, so the
// parent-tile crossfade branch is omitted (it would mix identical colors).
#version 460 core

layout(location = 0) out vec4 frag_color;

layout(binding = 1) uniform RasterEvaluatedPropsUBO {
    vec4 spin_weights;
    vec2 tl_parent;
    float scale_parent;
    float buffer_scale;
    float fade_t;
    float opacity;
    float brightness_low;
    float brightness_high;
    float saturation_factor;
    float contrast_factor;
    float pad1;
    float pad2;
} props;

uniform sampler2D u_image;

in vec2 v_pos0;

void main() {
    vec4 color = texture(u_image, v_pos0);
    if (color.a > 0.0) {
        color.rgb /= color.a; // unpremultiply
    }
    color.a *= props.opacity;
    vec3 rgb = color.rgb;

    // spin (hue rotate)
    rgb = vec3(
        dot(rgb, props.spin_weights.xyz),
        dot(rgb, props.spin_weights.zxy),
        dot(rgb, props.spin_weights.yzx));

    // saturation
    float average = (color.r + color.g + color.b) / 3.0;
    rgb += (average - rgb) * props.saturation_factor;

    // contrast
    rgb = (rgb - 0.5) * props.contrast_factor + 0.5;

    // brightness
    vec3 high_vec = vec3(props.brightness_low);
    vec3 low_vec = vec3(props.brightness_high);

    frag_color = vec4(mix(high_vec, low_vec, rgb) * color.a, color.a);
}
