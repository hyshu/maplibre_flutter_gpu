#version 460 core

layout(binding = 1) uniform HeatmapEvaluatedPropsUBO {
    float weight;
    float radius;
    float intensity;
    uint data_driven_mask;
} props;

layout(location = 0) in vec2 v_extrude;
layout(location = 1) in float v_weight;

layout(location = 0) out vec4 frag_color;

const float GAUSS_COEF = 0.3989422804014327;

void main() {
    float exponent = -4.5 * dot(v_extrude, v_extrude);
    float density = v_weight * props.intensity * GAUSS_COEF * exp(exponent);

    // The density target adds overlapping kernels in its red channel.
    frag_color = vec4(density, 1.0, 1.0, 1.0);
}
