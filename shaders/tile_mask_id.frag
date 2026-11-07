// Writes a tile's clip reference into the red channel of the tile mask.
#version 460 core

layout(binding = 1) uniform TileMaskIdUBO {
    vec4 id;
};

layout(location = 0) out vec4 frag_color;

void main() {
    frag_color = vec4(id.x / 255.0, 0.0, 0.0, 1.0);
}
