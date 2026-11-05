// Reconstruct signed positions and unsigned extrusion and distance bytes.
    highp uvec3 words = uvec3(a_packed);
    highp uint px = words.x & 65535u;
    highp uint py = (words.x >> 16u) | ((words.y & 255u) << 8u);
    highp vec2 a_pos_normal = vec2(
        int(px) - (px >= 32768u ? 65536 : 0),
        int(py) - (py >= 32768u ? 65536 : 0));
    highp vec4 a_data = vec4(uvec4(
        (words.y >> 8u) & 255u, words.y >> 16u,
        words.z & 255u, words.z >> 8u));
