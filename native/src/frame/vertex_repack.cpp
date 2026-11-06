// Optional C entry point for converting packed vertex layouts in native code.
#include "vertex_repack.hpp"

// This translation unit compiles without the bridge headers so the contract
// tests can link it alone. Match the export attributes of the other entry points.
#ifndef MAPLIBRE_API
#if defined(_WIN32)
#define MAPLIBRE_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define MAPLIBRE_API __attribute__((used, visibility("default")))
#else
#define MAPLIBRE_API
#endif
#endif

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
