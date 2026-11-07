// Projected MapLibre tile quad written into the tile mask texture.
#version 460 core

layout(location = 0) in vec2 a_pos;

layout(binding = 0) uniform ClippingMaskDrawableUBO {
    mat4 matrix;
} drawable;

void main() {
    gl_Position = drawable.matrix * vec4(a_pos, 0.0, 1.0);
}
