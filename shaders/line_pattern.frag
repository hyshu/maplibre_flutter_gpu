// MapLibre LinePattern fragment shader — tiles a sprite image along the
// line, crossfading between the zoom-from/to pattern variants.
#version 460 core

layout(location = 0) out vec4 frag_color;

layout(binding = 1) uniform LineEvaluatedPropsUBO {
    vec4 u_color;
    float u_blur;
    float u_opacity;
    float u_gapwidth;
    float u_offset;
    float u_width;
    float u_floorwidth;
    float props_pad1, props_pad2;
};

layout(binding = 2) uniform LinePatternTilePropsUBO {
    vec4 u_pattern_from; // atlas tlbr (px)
    vec4 u_pattern_to;
    vec4 u_scale;        // [pixelRatio, tileZoomRatio, fromScale, toScale]
    vec2 u_texsize;
    float u_fade;
    float tileprops_pad1;
};

uniform sampler2D u_image;

in vec2 v_normal;
in vec2 v_width2;
in float v_linesofar;
in float v_gamma_scale;
in float v_dpr;

void main() {
    vec2 pattern_tl_a = u_pattern_from.xy;
    vec2 pattern_br_a = u_pattern_from.zw;
    vec2 pattern_tl_b = u_pattern_to.xy;
    vec2 pattern_br_b = u_pattern_to.zw;

    float pixelRatio = u_scale.x;
    float tileZoomRatio = u_scale.y;
    float fromScale = u_scale.z;
    float toScale = u_scale.w;

    vec2 display_size_a = (pattern_br_a - pattern_tl_a) / pixelRatio;
    vec2 display_size_b = (pattern_br_b - pattern_tl_b) / pixelRatio;

    vec2 pattern_size_a = vec2(display_size_a.x * fromScale / tileZoomRatio, display_size_a.y);
    vec2 pattern_size_b = vec2(display_size_b.x * toScale / tileZoomRatio, display_size_b.y);

    float dist = length(v_normal) * v_width2.s;

    float blur2 = (u_blur + 1.0 / v_dpr) * v_gamma_scale;
    float alpha = clamp(min(dist - (v_width2.t - blur2), v_width2.s - dist) / blur2, 0.0, 1.0);

    float x_a = mod(v_linesofar / max(pattern_size_a.x, 0.01), 1.0);
    float x_b = mod(v_linesofar / max(pattern_size_b.x, 0.01), 1.0);

    // Clamp the vertical sample band to the pattern height (+padding) so we
    // don't sample neighboring sprites in the atlas
    float y_a = 0.5 + (v_normal.y * clamp(v_width2.s, 0.0, (pattern_size_a.y + 2.0) / 2.0) / pattern_size_a.y);
    float y_b = 0.5 + (v_normal.y * clamp(v_width2.s, 0.0, (pattern_size_b.y + 2.0) / 2.0) / pattern_size_b.y);
    vec2 texel_size = 1.0 / u_texsize;
    vec2 pos_a = mix(pattern_tl_a * texel_size, pattern_br_a * texel_size, vec2(x_a, y_a));
    vec2 pos_b = mix(pattern_tl_b * texel_size, pattern_br_b * texel_size, vec2(x_b, y_b));

    // Atlas is premultiplied RGBA, matching MapLibre's render target.
    vec4 c = mix(texture(u_image, pos_a), texture(u_image, pos_b), u_fade);
    frag_color = c * (alpha * u_opacity);
}
