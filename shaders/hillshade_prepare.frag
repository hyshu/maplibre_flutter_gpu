#version 460 core

layout(binding = 2) uniform HillshadePrepareTilePropsUBO {
    vec4 unpack;
    vec2 dimension;
    float zoom;
    float maxzoom;
} tile_props;

uniform sampler2D u_image;

layout(location = 0) in vec2 v_pos;
layout(location = 0) out vec4 frag_color;

float elevation(vec2 pos) {
    vec4 data = texture(u_image, pos) * 255.0;
    data.a = -1.0;

    // The unpack vector converts Mapbox or Terrarium RGB into meters.
    return dot(data, tile_props.unpack);
}

void main() {
    vec2 epsilon = 1.0 / tile_props.dimension;
    float tile_size = tile_props.dimension.x - 2.0;

    // Sobel samples run left to right, from the row above to the row below.
    float a = elevation(v_pos + vec2(-epsilon.x, -epsilon.y));
    float b = elevation(v_pos + vec2(0.0, -epsilon.y));
    float c = elevation(v_pos + vec2(epsilon.x, -epsilon.y));
    float d = elevation(v_pos + vec2(-epsilon.x, 0.0));
    float f = elevation(v_pos + vec2(epsilon.x, 0.0));
    float g = elevation(v_pos + vec2(-epsilon.x, epsilon.y));
    float h = elevation(v_pos + vec2(0.0, epsilon.y));
    float i = elevation(v_pos + vec2(epsilon.x, epsilon.y));

    float exaggeration_factor = tile_props.zoom < 2.0
        ? 0.4
        : tile_props.zoom < 4.5 ? 0.35 : 0.3;
    float exaggeration = tile_props.zoom < 15.0
        ? (tile_props.zoom - 15.0) * exaggeration_factor
        : 0.0;
    vec2 deriv = vec2(
        (c + f + f + i) - (a + d + d + g),
        (g + h + h + i) - (a + b + b + c)
    ) * tile_size / pow(2.0, exaggeration + (28.2562 - tile_props.zoom));

    // Each stored channel maps world-space slopes from [-4, 4] to [0, 1].
    frag_color = clamp(vec4(deriv / 8.0 + 0.5, 1.0, 1.0), 0.0, 1.0);
}
