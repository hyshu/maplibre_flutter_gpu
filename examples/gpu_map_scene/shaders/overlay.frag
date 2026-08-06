#version 460 core

layout(location = 0) in vec4 vertex_color;
layout(location = 0) out vec4 fragment_color;

void main() {
    fragment_color = vec4(
        vertex_color.rgb * vertex_color.a,
        vertex_color.a
    );
}
