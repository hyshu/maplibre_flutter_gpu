// MapLibre Fill vertex shader. Command Export stores position as packed short2;
// Flutter GPU exposes 32-bit integer vertex inputs, so decode that word in the
// shader instead of expanding every vertex to float2 on the CPU.
#version 460 core

layout(location = 0) in uint a_pos_packed;

layout(binding = 0) uniform FillDrawableUBO {
    mat4 matrix;
    float color_t;
    float opacity_t;
    float pad1;
    float pad2;
} drawable;

layout(binding = 1) uniform FillEvaluatedPropsUBO {
    vec4 color;
    vec4 outline_color;
    float opacity;
    float fade;
    float from_scale;
    float to_scale;
} props;

float unpack_s16(uint value) {
    uint raw = value & 0xffffu;
    return raw < 0x8000u ? float(raw) : float(int(raw) - 65536);
}

vec2 unpack_short2(uint packed) {
    return vec2(unpack_s16(packed), unpack_s16(packed >> 16));
}

void main() {
    vec2 a_pos = unpack_short2(a_pos_packed);
    gl_Position = drawable.matrix * vec4(a_pos, 0.0, 1.0);
}
