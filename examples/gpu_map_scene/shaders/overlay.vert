#version 460 core

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;

layout(location = 0) out vec4 vertex_color;

layout(binding = 0) uniform OverlayUniforms {
    // Transforms center-relative Mercator world pixels and altitude meters.
    mat4 view_projection;
    // xy = center-relative world pixels, z = pixels per meter,
    // w = heading counterclockwise from east.
    vec4 anchor;
    // x = normalized model size in meters.
    vec4 model;
    vec4 material_color;
} overlay;

void main() {
    float cosine = cos(overlay.anchor.w);
    float sine = sin(overlay.anchor.w);
    vec3 model_meters = position * overlay.model.x;

    // Kenney: +Z forward, +X right, +Y up. Map: +X east, +Y south, +Z up.
    float east = model_meters.z * cosine + model_meters.x * sine;
    float north = model_meters.z * sine - model_meters.x * cosine;
    vec3 map_position = vec3(
        overlay.anchor.x + east * overlay.anchor.z,
        overlay.anchor.y - north * overlay.anchor.z,
        model_meters.y
    );

    gl_Position = overlay.view_projection * vec4(map_position, 1.0);

    vec3 world_normal = normalize(vec3(
        normal.z * cosine + normal.x * sine,
        -(normal.z * sine - normal.x * cosine),
        normal.y
    ));
    vec3 light_direction = normalize(vec3(-0.4, -0.35, 0.85));
    float shade = 0.52 + 0.48 * max(
        dot(world_normal, light_direction),
        0.0
    );
    vertex_color = vec4(overlay.material_color.rgb * shade, 1.0);
}
