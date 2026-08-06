// Flutter GPU has no color-write mask. Transparent premultiplied output under
// the normal alpha blend leaves color unchanged while stencil is replaced.
#version 460 core

layout(location = 0) out vec4 frag_color;

void main() {
    frag_color = vec4(0.0);
}
