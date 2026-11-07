// Shared by tile-batched vertex shaders. One draw covers up to eight tiles
// whose drawable UBOs form consecutive uniform slots. The member a vertex
// belongs to is found from its index and the member table. Every value is a
// float in a scalar member because the OpenGL ES uniform path uploads neither
// arrays nor integers.
layout(binding = 5) uniform TileBatchUBO {
    vec4 tile_batch_info;      // mask width, mask height, member count, unused
    vec4 tile_batch_starts0;   // vertex starts of members 0 to 3
    vec4 tile_batch_starts1;   // vertex starts of members 4 to 7
    vec4 tile_batch_ids0;      // clip references of members 0 to 3
    vec4 tile_batch_ids1;      // clip references of members 4 to 7
};

layout(location = 14) flat out float v_tile_id;
layout(location = 15) flat out float v_tile_slot;

uint tile_batch_slot() {
    uint count = uint(tile_batch_info.z);
    float vertex = float(gl_VertexIndex);
    uint slot = 0u;
    if (count > 1u && vertex >= tile_batch_starts0.y) slot = 1u;
    if (count > 2u && vertex >= tile_batch_starts0.z) slot = 2u;
    if (count > 3u && vertex >= tile_batch_starts0.w) slot = 3u;
    if (count > 4u && vertex >= tile_batch_starts1.x) slot = 4u;
    if (count > 5u && vertex >= tile_batch_starts1.y) slot = 5u;
    if (count > 6u && vertex >= tile_batch_starts1.z) slot = 6u;
    if (count > 7u && vertex >= tile_batch_starts1.w) slot = 7u;
    return slot;
}

float tile_batch_id(uint slot) {
    switch (slot) {
        case 0u: return tile_batch_ids0.x;
        case 1u: return tile_batch_ids0.y;
        case 2u: return tile_batch_ids0.z;
        case 3u: return tile_batch_ids0.w;
        case 4u: return tile_batch_ids1.x;
        case 5u: return tile_batch_ids1.y;
        case 6u: return tile_batch_ids1.z;
        default: return tile_batch_ids1.w;
    }
}
