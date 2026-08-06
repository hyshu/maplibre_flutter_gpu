// MapLibre background-pattern fragment shader. Atlas pixels and the render
// target are premultiplied, so crossfade and opacity remain premultiplied.
#version 460 core

layout(location = 0) out vec4 frag_color;

layout(binding = 0) uniform BackgroundPatternDrawableUBO {
    mat4 matrix;
    vec2 pixel_coord_upper;
    vec2 pixel_coord_lower;
    float tile_units_to_pixels;
    float atlas_width;
    float atlas_height;
    float pad3;
} drawable;

layout(binding = 1) uniform BackgroundPatternPropsUBO {
    vec2 pattern_tl_a;
    vec2 pattern_br_a;
    vec2 pattern_tl_b;
    vec2 pattern_br_b;
    vec2 pattern_size_a;
    vec2 pattern_size_b;
    float scale_a;
    float scale_b;
    float mix_value;
    float opacity;
} props;

uniform sampler2D u_image;

in vec2 v_pos_a;
in vec2 v_pos_b;

void main() {
    vec2 atlas_size = vec2(drawable.atlas_width, drawable.atlas_height);
    if (atlas_size.x < 1.0 || atlas_size.y < 1.0) {
        discard;
    }

    vec2 imagecoord_a = mod(v_pos_a, 1.0);
    vec2 uv_a = mix(
        props.pattern_tl_a / atlas_size,
        props.pattern_br_a / atlas_size,
        imagecoord_a
    );
    vec4 color_a = texture(u_image, uv_a);

    vec2 imagecoord_b = mod(v_pos_b, 1.0);
    vec2 uv_b = mix(
        props.pattern_tl_b / atlas_size,
        props.pattern_br_b / atlas_size,
        imagecoord_b
    );
    vec4 color_b = texture(u_image, uv_b);

    frag_color = mix(color_a, color_b, props.mix_value) * props.opacity;
}
