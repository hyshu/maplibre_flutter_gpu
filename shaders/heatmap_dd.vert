#version 460 core

// Source values repeat both stops. Composite values retain their zoom stops.
layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_weight_range;
layout(location = 2) in vec2 a_radius_range;

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
    float weight = (props.data_driven_mask & 1u) != 0u
        ? mix(a_weight_range.x, a_weight_range.y, drawable.weight_t)
        : props.weight;
    float radius = (props.data_driven_mask & 2u) != 0u
        ? mix(a_radius_range.x, a_radius_range.y, drawable.radius_t)
        : props.radius;
    vec2 unscaled_extrude = mod(a_pos, 2.0) * 2.0 - 1.0;
    float amplitude = max(weight, ZERO) * max(props.intensity, ZERO) * GAUSS_COEF;

    // Bound the quad where the Gaussian falls below the density threshold.
    // Clamping keeps zero weight and intensity finite.
    float extent = sqrt(max(-2.0 * log(ZERO / amplitude), 0.0)) / 3.0;
    v_extrude = extent * unscaled_extrude;
    v_weight = weight;

    vec2 center = floor(a_pos * 0.5);
    vec2 extrude = v_extrude * radius * drawable.extrude_scale;
    gl_Position = drawable.matrix * vec4(center + extrude, 0.0, 1.0);
}
