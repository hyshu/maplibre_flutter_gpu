// Shared vertex stage for application fill-extrusion materials.
//
// Variants define MATERIAL_DATA_DRIVEN for per-vertex base, height, and color
// ranges, and MATERIAL_CUSTOM for two application vec4 attributes from a
// second vertex buffer. The application's fragment shader consumes the
// outputs listed in FillExtrusionMaterial's documentation.
//
// Dart builds the vertex stream from MapLibre's export. a_position holds the
// tile position including its sub-unit fraction, the top flag, and the ring
// distance. a_normal holds the outward wall normal and the sign that converts
// it back to MapLibre's lighting normal.

layout(location = 0) in vec4 a_position;
layout(location = 1) in vec4 a_normal;
#ifdef MATERIAL_DATA_DRIVEN
layout(location = 2) in vec2 a_base_range;
layout(location = 3) in vec2 a_height_range;
layout(location = 4) in vec4 a_color_range;
#endif
#ifdef MATERIAL_CUSTOM
// Impeller reflection requires contiguous input locations.
#ifdef MATERIAL_DATA_DRIVEN
layout(location = 5) in vec4 a_custom0;
layout(location = 6) in vec4 a_custom1;
#else
layout(location = 2) in vec4 a_custom0;
layout(location = 3) in vec4 a_custom1;
#endif
#endif

layout(binding = 0) uniform FillExtrusionDrawableUBO {
    mat4 matrix;
    vec2 pixel_coord_upper;
    vec2 pixel_coord_lower;
    float height_factor;
    float tile_ratio;
    float base_t;
    float height_t;
    float color_t;
    float meters_per_unit; // renderer value in native padding
    float pad2;
    uint data_driven_mask; // bit0=color, zero for constant layouts
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

layout(location = 0) out vec4 v_color;
layout(location = 1) out vec3 v_position;
layout(location = 2) out vec4 v_surface;
layout(location = 3) out vec4 v_extrusion;
#ifdef MATERIAL_CUSTOM
layout(location = 4) out vec4 v_custom0;
layout(location = 5) out vec4 v_custom1;
#endif

#ifdef MATERIAL_DATA_DRIVEN
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
#endif

void main() {
    bool roof = a_normal.x == 0.0 && a_normal.y == 0.0;
    // MapLibre's lighting uses the exported normal direction.
    vec3 normal = vec3(a_normal.xy * a_normal.z, roof ? 1.0 : 0.0);

#ifdef MATERIAL_DATA_DRIVEN
    float base = max(0.0, mix(a_base_range.x, a_base_range.y, drawable.base_t));
    float height = max(0.0, mix(a_height_range.x, a_height_range.y, drawable.height_t));
    vec4 color;
    if ((drawable.data_driven_mask & 1u) != 0u) {
        color = mix(decode_color(a_color_range.xy), decode_color(a_color_range.zw), drawable.color_t);
    } else {
        color = props.color;
    }
#else
    float base = max(0.0, props.light_pos_base.w);
    float height = max(0.0, props.height);
    vec4 color = props.color;
#endif

    float t = a_position.z;
    vec3 position = vec3(a_position.xy, t > 0.5 ? height : base);
    gl_Position = drawable.matrix * vec4(position, 1.0);

    // MapLibre's fill-extrusion lighting.
    float colorvalue = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722;
    v_color = vec4(0.0, 0.0, 0.0, 1.0);
    color += vec4(0.03, 0.03, 0.03, 1.0);
    float directional = clamp(dot(normal, props.light_pos_base.xyz), 0.0, 1.0);
    directional = mix((1.0 - props.light_intensity),
                      max((1.0 - colorvalue + props.light_intensity), 1.0),
                      directional);
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

    v_position = position;
    v_surface = vec4(a_normal.xy, roof ? 1.0 : 0.0, t);
    v_extrusion = vec4(a_position.w, drawable.meters_per_unit, base, height);
#ifdef MATERIAL_CUSTOM
    v_custom0 = a_custom0;
    v_custom1 = a_custom1;
#endif
}
