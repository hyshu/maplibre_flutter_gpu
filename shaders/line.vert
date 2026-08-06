// MapLibre Line vertex shader — full port of the upstream line shader:
// honors line-width, line-gap-width and line-offset from the evaluated
// props UBO (the old version only supported a constant width override).
// Packed vertex data as uvec2: short2 pos_normal + uchar4 data (zero-copy).
#version 460 core

#define scale 0.015873016

layout(location = 0) in vec2 a_pos_normal;
layout(location = 1) in vec4 a_data;

layout(binding = 0) uniform LineDrawableUBO {
    mat4 u_matrix;
    float u_ratio;
    // Interpolation factors (unused: per-feature paint attributes are not
    // exported by the Command Export backend)
    float u_color_t;
    float u_blur_t;
    float u_opacity_t;
    float u_gapwidth_t;
    float u_offset_t;
    float u_width_t;
    // pad1 in LineDrawableUBO — patched by the Dart renderer with the
    // actual device pixel ratio (antialiasing width depends on it)
    float u_device_pixel_ratio;
};

layout(binding = 1) uniform LineEvaluatedPropsUBO {
    vec4 u_color;
    float u_blur;
    float u_opacity;
    float u_gapwidth;
    float u_offset;
    float u_width;
    float u_floorwidth;
    float props_pad1, props_pad2;
};

// MapLibre's GlobalPaintParamsUBO values needed for perspective-correct
// antialiasing. Dart derives these from the physical target size and DPR.
layout(binding = 3) uniform MapGlobalUBO {
    vec2 u_units_to_pixels;
    vec2 u_world_size;
};

out vec2 v_normal;
out vec2 v_width2;
out float v_gamma_scale;
out float v_dpr;
void main() {
    float dpr = max(u_device_pixel_ratio, 0.000001);
    float ANTIALIASING = 1.0 / dpr / 2.0;

    vec2 a_extrude = a_data.xy - 128.0;
    float a_direction = mod(a_data.z, 4.0) - 1.0;

    vec2 pos = floor(a_pos_normal * 0.5);

    // x is 1 for round caps, y is 1 if the normal points up (LSB-encoded)
    vec2 normal = a_pos_normal - 2.0 * pos;
    normal.y = normal.y * 2.0 - 1.0;
    v_normal = normal;

    float gapwidth = u_gapwidth / 2.0;
    float halfwidth = u_width / 2.0;
    float offset = -1.0 * u_offset;

    float inset = gapwidth + (gapwidth > 0.0 ? ANTIALIASING : 0.0);
    float outset = gapwidth + halfwidth * (gapwidth > 0.0 ? 2.0 : 1.0) +
                   (halfwidth == 0.0 ? 0.0 : ANTIALIASING);

    // Scale the extrusion vector to the line width of this vertex
    vec2 dist = outset * a_extrude * scale;

    // Sideways offset (line-offset); rotate for round end caps
    float u = 0.5 * a_direction;
    float t = 1.0 - abs(u);
    vec2 offset2 = offset * a_extrude * scale * normal.y * mat2(t, -u, u, t);

    vec4 projected_extrude = u_matrix * vec4(dist / u_ratio, 0.0, 0.0);
    gl_Position = u_matrix * vec4(pos + offset2 / u_ratio, 0.0, 1.0) + projected_extrude;

    // Match MapLibre's perspective correction: pitched lines need a wider or
    // narrower antialiasing ramp when projection squashes their extrusion.
    float extrude_length_without_perspective = length(dist);
    float extrude_length_with_perspective =
        length(projected_extrude.xy / gl_Position.w * u_units_to_pixels);
    v_gamma_scale = extrude_length_without_perspective /
                    extrude_length_with_perspective;
    v_dpr = dpr;

    v_width2 = vec2(outset, inset);
}
