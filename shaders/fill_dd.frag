// MapLibre Fill fragment shader - data-driven color/opacity variant.
#version 460 core

layout(location = 0) out vec4 frag_color;

in vec4 v_color;
in float v_opacity;

void main() {
    // v_color is already premultiplied; apply fill-opacity exactly once.
    frag_color = v_color * v_opacity;
}
