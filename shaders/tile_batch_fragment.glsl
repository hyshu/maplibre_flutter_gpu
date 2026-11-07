// Shared by tile-batched fragment shaders. The tile mask holds each tile's
// clip reference, so a fragment survives only inside its own tile's region.
layout(binding = 5) uniform TileBatchUBO {
    vec4 tile_batch_info;      // mask width, mask height, member count, unused
    vec4 tile_batch_starts0;
    vec4 tile_batch_starts1;
    vec4 tile_batch_ids0;
    vec4 tile_batch_ids1;
};

uniform sampler2D u_tile_mask;

layout(location = 14) flat in float v_tile_id;
layout(location = 15) flat in float v_tile_slot;

void tile_batch_clip() {
    float mask_id = texture(u_tile_mask, gl_FragCoord.xy / tile_batch_info.xy).r * 255.0;
    if (abs(mask_id - v_tile_id) > 0.5) discard;
}
