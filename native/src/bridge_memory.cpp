#include "camera/camera_dispatch.hpp"
#include "memory/system_memory.hpp"

#include <mln/renderer/renderer.hpp>

extern "C" {

// Memory measurements do not require a map session. Zero means unavailable.
MAPLIBRE_API uint64_t maplibre_get_physical_memory(void) {
    return maplibre_bridge::memory::physicalMemoryBytes();
}

MAPLIBRE_API uint64_t maplibre_get_available_memory(void) {
    return maplibre_bridge::memory::availableMemoryBytes();
}

MAPLIBRE_API uint64_t maplibre_get_memory_usage(void) {
    return maplibre_bridge::memory::memoryUsageBytes();
}

// Caps offscreen tiles per source. UINT32_MAX restores automatic sizing.
// One means applied or deferred until the selected session's frame is released.
MAPLIBRE_API int maplibre_set_tile_cache_size(uint32_t max_tiles) {
    return maplibre_bridge::camera::runCameraMutation("set tile cache size", [=] {
        auto* renderer = g_frontend ? g_frontend->getRenderer() : nullptr;
        if (!renderer) return false;
        renderer->setTileCacheSize(max_tiles);
        return true;
    }, false);
}

// Releases unused renderer resources without discarding visible tile data.
// One means applied or deferred until the selected session's frame is released.
MAPLIBRE_API int maplibre_reduce_memory_use(void) {
    return maplibre_bridge::camera::runCameraMutation("reduce memory use", [] {
        auto* renderer = g_frontend ? g_frontend->getRenderer() : nullptr;
        if (!renderer) return false;
        renderer->reduceMemoryUse();
        return true;
    }, false);
}

} // extern "C"
