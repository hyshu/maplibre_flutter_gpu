#version 460 core

layout(binding = 0) uniform ClearColor {
    vec4 value;
} color;

layout(location = 0) out vec4 frag_color;

void main() {
    frag_color = color.value;
}
