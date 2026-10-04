#version 460 core

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_texture_pos;

layout(binding = 0) uniform HillshadePrepareDrawableUBO {
    mat4 matrix;
} drawable;

layout(binding = 2) uniform HillshadePrepareTilePropsUBO {
    vec4 unpack;
    vec2 dimension;
    float zoom;
    float maxzoom;
} tile_props;

layout(location = 0) out vec2 v_pos;

void main() {
    gl_Position = drawable.matrix * vec4(a_pos, 0.0, 1.0);

    // DEM textures include a one-pixel border for neighboring elevations.
    vec2 epsilon = 1.0 / tile_props.dimension;
    float scale = (tile_props.dimension.x - 2.0) / tile_props.dimension.x;
    v_pos = (a_texture_pos / 8192.0) * scale + epsilon;
}
