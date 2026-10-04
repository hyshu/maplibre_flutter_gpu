#version 460 core

// Each position packs a tile-space center and a one-bit corner per axis.
layout(location = 0) in vec2 a_pos;

layout(binding = 0) uniform HeatmapDrawableUBO {
    mat4 matrix;
    float extrude_scale;
    float weight_t;
    float radius_t;
    float pad1;
} drawable;

layout(binding = 1) uniform HeatmapEvaluatedPropsUBO {
    float weight;
    float radius;
    float intensity;
    uint data_driven_mask;
} props;

layout(location = 0) out vec2 v_extrude;
layout(location = 1) out float v_weight;

const float ZERO = 1.0 / 255.0 / 16.0;
const float GAUSS_COEF = 0.3989422804014327;

void main() {
    vec2 unscaled_extrude = mod(a_pos, 2.0) * 2.0 - 1.0;
    float amplitude = max(props.weight, ZERO) * max(props.intensity, ZERO) * GAUSS_COEF;

    // Bound the quad where the Gaussian falls below the density threshold.
    // Clamping keeps zero weight and intensity finite.
    float extent = sqrt(max(-2.0 * log(ZERO / amplitude), 0.0)) / 3.0;
    v_extrude = extent * unscaled_extrude;
    v_weight = props.weight;

    vec2 center = floor(a_pos * 0.5);
    vec2 extrude = v_extrude * props.radius * drawable.extrude_scale;
    gl_Position = drawable.matrix * vec4(center + extrude, 0.0, 1.0);
}
