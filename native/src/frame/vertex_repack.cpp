// Optional C entry point for converting packed vertex layouts in native code.
#include "vertex_repack.hpp"

extern "C" {

MAPLIBRE_API int32_t maplibre_repack_vertices_v1(uint32_t layout,
                                                const void* source,
                                                size_t sourceBytes,
                                                uint32_t vertexCount,
                                                void* destination,
                                                size_t destinationCapacity) noexcept {
    return static_cast<int32_t>(maplibre_bridge::vertices::repackVertices(
        layout, source, sourceBytes, vertexCount, destination, destinationCapacity));
}

} // extern "C"
