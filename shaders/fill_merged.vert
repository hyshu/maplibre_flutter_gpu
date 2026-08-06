// Fill vertex shader for cross-tile merged commands.
// Vertices are pre-transformed to clip space on the CPU and quantized as
// signed int16 (8192 steps per NDC unit); the matrix only rescales them.
// No v_pos varying: merged geometry is screen-space and, unlike per-tile
// commands, intentionally has no tile stencil reference.
#version 460 core

layout(location = 0) in vec2 a_pos;

layout(binding = 0) uniform FillDrawableUBO {
    mat4 matrix;
    float color_t;
    float opacity_t;
    float pad1;
    float pad2;
} drawable;

void main() {
    gl_Position = drawable.matrix * vec4(a_pos, 0.0, 1.0);
}
