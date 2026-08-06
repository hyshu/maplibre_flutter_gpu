// MapLibre background-pattern vertex shader. The split pixel coordinate keeps
// repeating patterns stable at high zoom and across wrapped worlds.
#version 460 core

layout(location = 0) in vec2 a_pos;

layout(binding = 0) uniform BackgroundPatternDrawableUBO {
    mat4 matrix;
    vec2 pixel_coord_upper;
    vec2 pixel_coord_lower;
    float tile_units_to_pixels;
    float atlas_width;  // native pad1, populated by Dart
    float atlas_height; // native pad2, populated by Dart
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

out vec2 v_pos_a;
out vec2 v_pos_b;

vec2 get_pattern_pos(
    vec2 pixel_coord_upper,
    vec2 pixel_coord_lower,
    vec2 pattern_size,
    float tile_units_to_pixels,
    vec2 pos
) {
    // Reconstruct modulo 2^16 in two 8-bit steps, exactly as MapLibre does,
    // so float precision does not make the phase jump at high zoom.
    vec2 offset = mod(
        mod(mod(pixel_coord_upper, pattern_size) * 256.0, pattern_size) *
            256.0 + pixel_coord_lower,
        pattern_size
    );
    return (tile_units_to_pixels * pos + offset) / pattern_size;
}

void main() {
    gl_Position = drawable.matrix * vec4(a_pos, 0.0, 1.0);
    v_pos_a = get_pattern_pos(
        drawable.pixel_coord_upper,
        drawable.pixel_coord_lower,
        props.scale_a * props.pattern_size_a,
        drawable.tile_units_to_pixels,
        a_pos
    );
    v_pos_b = get_pattern_pos(
        drawable.pixel_coord_upper,
        drawable.pixel_coord_lower,
        props.scale_b * props.pattern_size_b,
        drawable.tile_units_to_pixels,
        a_pos
    );
}
