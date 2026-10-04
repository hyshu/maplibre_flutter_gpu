#version 460 core

layout(location = 0) in vec2 a_pos;

layout(binding = 0) uniform HeatmapTexturePropsUBO {
    mat4 matrix;
    float opacity;
    float pad1;
    float pad2;
    float pad3;
} props;

layout(binding = 3) uniform MapGlobalUBO {
    vec2 u_units_to_pixels;
    vec2 u_world_size;
};

layout(location = 0) out vec2 v_pos;

void main() {
    gl_Position = props.matrix * vec4(a_pos * u_world_size, 0.0, 1.0);
    v_pos = a_pos;
}
