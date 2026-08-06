// MapLibre Raster vertex shader.
// Vertex data is expanded to float2 tile pos + float2 texture pos.
#version 460 core

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_texture_pos;

layout(binding = 0) uniform RasterDrawableUBO {
    mat4 matrix;
} drawable;

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

out vec2 v_pos0;

void main() {
    gl_Position = drawable.matrix * vec4(a_pos, 0.0, 1.0);

    // Texture coordinates are stored scaled by 8192 (same as tile EXTENT)
    v_pos0 = (((a_texture_pos / 8192.0) - 0.5) / props.buffer_scale) + 0.5;
}
