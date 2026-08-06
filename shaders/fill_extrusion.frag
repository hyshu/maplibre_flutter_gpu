// Fill extrusion fragment shader - 3D buildings
#version 460 core

layout(location = 0) out vec4 frag_color;

in vec4 v_color;

void main() {
    frag_color = v_color;
}
