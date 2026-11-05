#include "frame/vertex_repack.hpp"

extern "C" __attribute__((used, visibility("default")))
std::int32_t maplibre_repack_vertices_v1(std::uint32_t layout,
                                      const void* source,
                                      std::size_t sourceBytes,
                                      std::uint32_t vertexCount,
                                      void* destination,
                                      std::size_t destinationCapacity) noexcept {
    return static_cast<std::int32_t>(maplibre_bridge::vertices::repackVertices(
        layout, source, sourceBytes, vertexCount, destination, destinationCapacity));
}
