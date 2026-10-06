#version 460 core

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_texture_pos;

layout(binding = 0) uniform HillshadeDrawableUBO {
    mat4 matrix;
} drawable;

layout(location = 0) out vec2 v_pos;

void main() {
    gl_Position = drawable.matrix * vec4(a_pos, 0.0, 1.0);

    // The preparation projection reverses the tile's vertical texture axis.
    v_pos = a_texture_pos / 8192.0;
    v_pos.y = 1.0 - v_pos.y;
}
