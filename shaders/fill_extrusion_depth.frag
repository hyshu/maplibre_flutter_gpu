// Fill-extrusion depth prepass. Flutter GPU does not expose a color-write
// mask, so output transparent premultiplied black under the normal alpha blend
// equation: the color attachment stays unchanged while depth is written.
#version 460 core

layout(location = 0) out vec4 frag_color;

void main() {
    frag_color = vec4(0.0);
}
