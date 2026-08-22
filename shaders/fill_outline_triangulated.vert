// MapLibre triangulated fill outline. Flutter GPU has no configurable native
// line width, so the outline is expanded into triangles. The first 8 bytes are
// MapLibre's packed LineLayoutVertex and are decoded from two uint32 inputs in
// the shader, avoiding a 24-byte float-expanded CPU copy.
#version 460 core

#define scale 0.015873016

layout(location = 0) in uvec2 a_layout_packed;

layout(binding = 0) uniform FillOutlineTriangulatedDrawableUBO {
    mat4 u_matrix;
    float u_ratio;
    // pad1 in the C++ UBO, patched by Dart with the device pixel ratio.
    float u_device_pixel_ratio;
    float drawable_pad2;
    float drawable_pad3;
};

layout(binding = 2) uniform MapGlobalUBO {
    vec2 u_units_to_pixels;
    vec2 u_world_size;
};

out vec2 v_normal;
out float v_width;
out float v_gamma_scale;
out float v_dpr;

float unpack_s16(uint value) {
    uint raw = value & 0xffffu;
    return raw < 0x8000u ? float(raw) : float(int(raw) - 65536);
}

vec2 unpack_short2(uint packed) {
    return vec2(unpack_s16(packed), unpack_s16(packed >> 16));
}

vec4 unpack_u8x4(uint packed) {
    return vec4(
        float(packed & 0xffu),
        float((packed >> 8) & 0xffu),
        float((packed >> 16) & 0xffu),
        float((packed >> 24) & 0xffu)
    );
}

void main() {
    vec2 a_pos_normal = unpack_short2(a_layout_packed.x);
    vec4 a_data = unpack_u8x4(a_layout_packed.y);

    float dpr = max(u_device_pixel_ratio, 0.000001);
    float antialiasing = 0.5 / dpr;

    vec2 a_extrude = a_data.xy - 128.0;

    vec2 pos = floor(a_pos_normal * 0.5);
    vec2 normal = a_pos_normal - 2.0 * pos;
    normal.y = normal.y * 2.0 - 1.0;
    v_normal = normal;

    // Retain MapLibre's wider triangulated support geometry. Pixels outside
    // the OpenGL coverage radius become transparent in the fragment shader;
    // the extra support prevents clipping after perspective compression.
    float halfwidth = 0.5;
    float outset = halfwidth + antialiasing;
    vec2 dist = outset * a_extrude * scale;

    vec4 projected_extrude = u_matrix * vec4(dist / u_ratio, 0.0, 0.0);
    gl_Position = u_matrix * vec4(pos, 0.0, 1.0) + projected_extrude;

    float extrude_length_without_perspective = length(dist);
    float extrude_length_with_perspective =
        length(projected_extrude.xy / gl_Position.w * u_units_to_pixels);
    v_gamma_scale = extrude_length_without_perspective /
                    extrude_length_with_perspective;
    v_width = outset;
    v_dpr = dpr;
}
