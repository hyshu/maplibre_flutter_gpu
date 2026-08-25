// Fill extrusion vertex shader - 3D buildings (layer-constant base/height).
// Dart expands short2(pos), ushort2(decimals_ed), and short2(normal2d) to
// numeric floats so every Impeller backend can bind them.
#version 460 core

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec4 a_decimals_ed_normal;

layout(binding = 0) uniform FillExtrusionDrawableUBO {
    mat4 matrix;
    vec2 pixel_coord_upper;
    vec2 pixel_coord_lower;
    float height_factor;
    float tile_ratio;
    float base_t;
    float height_t;
    float color_t;
    float pad1, pad2, pad3;
} drawable;

layout(binding = 1) uniform FillExtrusionPropsUBO {
    vec4 color;
    vec4 light_color;    // xyz used
    vec4 light_pos_base; // xyz=light_position, w=base
    float height;
    float light_intensity;
    float vertical_gradient;
    float opacity;
    float fade;
    float from_scale;
    float to_scale;
    float pad1;
} props;

out vec4 v_color;

vec2 unpack_float(const float packed_value) {
    int packed_int_value = int(packed_value);
    int v0 = packed_int_value / 256;
    return vec2(v0, packed_int_value - v0 * 256);
}

void main() {
    vec2 a_decimals_ed = a_decimals_ed_normal.xy;
    vec2 normal2d = a_decimals_ed_normal.zw / 16384.0;
    vec3 normal = vec3(
        normal2d,
        normal2d.x == 0.0 && normal2d.y == 0.0 ? 1.0 : 0.0
    );

    float base = max(0.0, props.light_pos_base.w);
    float height = max(0.0, props.height);
    vec4 color = props.color;

    float t = mod(a_decimals_ed.x, 2.0);
    vec2 decimals = unpack_float(floor(a_decimals_ed.x / 2.0)) / 128.0;

    gl_Position =
        drawable.matrix * vec4(a_pos + decimals, t > 0.0 ? height : base, 1.0);

    // Relative luminance of the surface color
    float colorvalue = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722;

    v_color = vec4(0.0, 0.0, 0.0, 1.0);

    // Slight ambient so no extrusion is totally black
    vec4 ambientlight = vec4(0.03, 0.03, 0.03, 1.0);
    color += ambientlight;

    // cos(theta) between surface normal and light ray
    float directional = clamp(dot(normal, props.light_pos_base.xyz), 0.0, 1.0);
    directional = mix((1.0 - props.light_intensity),
                      max((1.0 - colorvalue + props.light_intensity), 1.0),
                      directional);

    // Vertical gradient along side surfaces
    if (normal.z == 0.0) {
        directional *= (
            (1.0 - props.vertical_gradient) +
            (props.vertical_gradient *
             clamp((t + base) * pow(height / 150.0, 0.5),
                   mix(0.7, 0.98, 1.0 - props.light_intensity), 1.0)));
    }

    v_color.r += clamp(color.r * directional * props.light_color.r,
                       mix(0.0, 0.3, 1.0 - props.light_color.r), 1.0);
    v_color.g += clamp(color.g * directional * props.light_color.g,
                       mix(0.0, 0.3, 1.0 - props.light_color.g), 1.0);
    v_color.b += clamp(color.b * directional * props.light_color.b,
                       mix(0.0, 0.3, 1.0 - props.light_color.b), 1.0);
    v_color *= props.opacity;
}
