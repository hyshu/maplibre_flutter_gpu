#version 460 core

layout(binding = 1) uniform HillshadeEvaluatedPropsUBO {
    vec4 accent;
    vec4 altitudes;
    vec4 azimuths;
    vec4 shadows[4];
    vec4 highlights[4];
} props;

layout(binding = 2) uniform HillshadeTilePropsUBO {
    vec2 latrange;
    float exaggeration;
    int method;
    int num_lights;
    float pad0;
    float pad1;
    float pad2;
} tile_props;

uniform sampler2D u_image;

layout(location = 0) in vec2 v_pos;
layout(location = 0) out vec4 frag_color;

const float PI = 3.141592653589793;
const int COMBINED = 1;
const int IGOR = 2;
const int MULTIDIRECTIONAL = 3;
const int BASIC = 4;

float aspect(vec2 deriv) {
    return deriv.x != 0.0
        ? atan(deriv.y, -deriv.x)
        : PI / 2.0 * (deriv.y > 0.0 ? 1.0 : -1.0);
}

float light_cosine(vec2 deriv, float altitude, float azimuth) {
    return (sin(altitude) - (deriv.y * cos(azimuth) * cos(altitude)
        - deriv.x * sin(azimuth) * cos(altitude)))
        / sqrt(1.0 + dot(deriv, deriv));
}

vec4 directional_color(float shade, vec4 shadow, vec4 highlight) {
    return shade > 0.5
        ? highlight * (2.0 * shade - 1.0)
        : shadow * (1.0 - 2.0 * shade);
}

vec4 standard_hillshade(vec2 deriv) {
    float azimuth = props.azimuths.x + PI;
    float slope = atan(0.625 * length(deriv));
    float intensity = tile_props.exaggeration;
    float base = 1.875 - intensity * 1.75;
    float max_slope = 0.5 * PI;
    float scaled_slope = abs(intensity - 0.5) > 1e-6
        ? ((pow(base, slope) - 1.0) / (pow(base, max_slope) - 1.0)) * max_slope
        : slope;
    float strength = clamp(intensity * 2.0, 0.0, 1.0);
    vec4 accent_color = (1.0 - cos(scaled_slope)) * props.accent * strength;
    float shade = abs(mod((aspect(deriv) + azimuth) / PI + 0.5, 2.0) - 1.0);
    vec4 shade_color = mix(props.shadows[0], props.highlights[0], shade)
        * sin(scaled_slope) * strength;

    return accent_color * (1.0 - shade_color.a) + shade_color;
}

vec4 basic_hillshade(vec2 deriv) {
    deriv *= tile_props.exaggeration * 2.0;
    float shade = clamp(
        light_cosine(deriv, props.altitudes.x, props.azimuths.x + PI),
        0.0, 1.0);

    return directional_color(shade, props.shadows[0], props.highlights[0]);
}

vec4 multidirectional_hillshade(vec2 deriv) {
    deriv *= tile_props.exaggeration * 2.0;
    vec4 color = vec4(0.0);
    int count = min(tile_props.num_lights, 4);
    for (int i = 0; i < count; i++) {
        float shade = clamp(
            light_cosine(deriv, props.altitudes[i], props.azimuths[i] + PI),
            0.0, 1.0);
        color += directional_color(shade, props.shadows[i], props.highlights[i])
            / float(count);
    }

    return color;
}

vec4 combined_hillshade(vec2 deriv) {
    deriv *= tile_props.exaggeration * 2.0;
    float cosine = light_cosine(deriv, props.altitudes.x, props.azimuths.x + PI);
    // Rounding must not move the cosine outside acos's domain.
    float angle = clamp(acos(clamp(cosine, -1.0, 1.0)), 0.0, PI / 2.0);
    float strength = atan(length(deriv)) * 4.0 / PI / PI;

    return props.shadows[0] * angle * strength
        + props.highlights[0] * (PI / 2.0 - angle) * strength;
}

vec4 igor_hillshade(vec2 deriv) {
    deriv *= tile_props.exaggeration * 2.0;
    float azimuth = props.azimuths.x + PI;
    float slope_strength = atan(length(deriv)) * 2.0 / PI;
    float aspect_strength = 1.0
        - abs(mod((aspect(deriv) + azimuth) / PI + 0.5, 2.0) - 1.0);

    return props.shadows[0] * slope_strength * aspect_strength
        + props.highlights[0] * slope_strength * (1.0 - aspect_strength);
}

void main() {
    vec4 pixel = texture(u_image, v_pos);
    float latitude = (tile_props.latrange.x - tile_props.latrange.y) * v_pos.y
        + tile_props.latrange.y;
    vec2 deriv = (pixel.rg * 8.0 - 4.0) / cos(radians(latitude));

    if (tile_props.method == BASIC) {
        frag_color = basic_hillshade(deriv);
    } else if (tile_props.method == COMBINED) {
        frag_color = combined_hillshade(deriv);
    } else if (tile_props.method == IGOR) {
        frag_color = igor_hillshade(deriv);
    } else if (tile_props.method == MULTIDIRECTIONAL) {
        frag_color = multidirectional_hillshade(deriv);
    } else {
        frag_color = standard_hillshade(deriv);
    }
}
