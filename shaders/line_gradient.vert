// MapLibre LineGradient vertex shader (line-gradient) — port of the
// upstream line_gradient shader. Samples a 256x1 color ramp texture.
#version 460 core

#define scale 0.015873016
#define MAX_LINE_DISTANCE 32767.0

layout(location = 0) in vec2 a_pos_normal;
layout(location = 1) in vec4 a_data;

layout(binding = 0) uniform LineGradientDrawableUBO {
    mat4 u_matrix;
    float u_ratio;
    // Interpolation factors (unused)
    float u_blur_t;
    float u_opacity_t;
    float u_gapwidth_t;
    float u_offset_t;
    float u_width_t;
    float drawable_pad1;
    // pad2 — patched by the Dart renderer with the device pixel ratio
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

layout(binding = 3) uniform MapGlobalUBO {
    vec2 u_units_to_pixels;
    vec2 u_world_size;
};

out vec2 v_normal;
out vec2 v_width2;
out float v_lineprogress;
out float v_gamma_scale;
out float v_dpr;
void main() {
    float dpr = max(u_device_pixel_ratio, 0.000001);
    float ANTIALIASING = 1.0 / dpr / 2.0;

    vec2 a_extrude = a_data.xy - 128.0;
    float a_direction = mod(a_data.z, 4.0) - 1.0;
    // Line progress normalized to [0, 1] (upstream uses *2.0/MAX_LINE_DISTANCE
    // with LINE_DISTANCE_SCALE folded in)
    v_lineprogress = (floor(a_data.z / 4.0) + a_data.w * 64.0) * 2.0 / MAX_LINE_DISTANCE;

    vec2 pos = floor(a_pos_normal * 0.5);
    vec2 normal = a_pos_normal - 2.0 * pos;
    normal.y = normal.y * 2.0 - 1.0;
    v_normal = normal;

    float gapwidth = u_gapwidth / 2.0;
    float halfwidth = u_width / 2.0;
    float offset = -1.0 * u_offset;

    float inset = gapwidth + (gapwidth > 0.0 ? ANTIALIASING : 0.0);
    float outset = gapwidth + halfwidth * (gapwidth > 0.0 ? 2.0 : 1.0) +
                   (halfwidth == 0.0 ? 0.0 : ANTIALIASING);

    vec2 dist = outset * a_extrude * scale;

    float u = 0.5 * a_direction;
    float t = 1.0 - abs(u);
    vec2 offset2 = offset * a_extrude * scale * normal.y * mat2(t, -u, u, t);

    vec4 projected_extrude = u_matrix * vec4(dist / u_ratio, 0.0, 0.0);
    gl_Position = u_matrix * vec4(pos + offset2 / u_ratio, 0.0, 1.0) + projected_extrude;

    float extrude_length_without_perspective = length(dist);
    float extrude_length_with_perspective =
        length(projected_extrude.xy / gl_Position.w * u_units_to_pixels);
    v_gamma_scale = extrude_length_without_perspective /
                    extrude_length_with_perspective;
    v_dpr = dpr;

    v_width2 = vec2(outset, inset);
}
