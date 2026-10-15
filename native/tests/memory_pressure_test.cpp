#include <atomic>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <type_traits>
#include <utility>

#define __ANDROID__ 1
#define MAPLIBRE_API

static bool onOwnerThread = false;
static struct {
    std::mutex mutex;
    bool acquired = false;
    bool ready = false;
    bool rendering = false;
    bool syncFrameOpen = false;
    bool renderDeferred = false;
    std::deque<std::function<void()>> deferredMutations;
} g_asyncFrame;
static std::atomic<bool> g_mapIdle{true};
static std::atomic<bool> g_renderDirty{false};
static std::atomic<uint64_t> g_pendingCameraMutations{0};
static bool g_map = true;

struct Renderer {
    uint32_t cap = UINT32_MAX;
    int reductions = 0;
    void setTileCacheSize(uint32_t value) {
        assert(onOwnerThread);
        assert(!g_asyncFrame.acquired && !g_asyncFrame.rendering && !g_asyncFrame.syncFrameOpen);
        cap = value;
    }
    void reduceMemoryUse() {
        assert(onOwnerThread);
        assert(!g_asyncFrame.acquired && !g_asyncFrame.rendering && !g_asyncFrame.syncFrameOpen);
        ++reductions;
    }
};
static Renderer renderer;
struct Frontend {
    Renderer* getRenderer() { return &renderer; }
};
static Frontend frontend;
static Frontend* g_frontend = &frontend;

static void discardUnacquiredFrameLocked() {
    if (!g_asyncFrame.acquired) g_asyncFrame.ready = false;
}

template <typename Operation>
auto bridge_runOnOwnerSync(Operation&& operation) {
    onOwnerThread = true;
    auto result = operation();
    onOwnerThread = false;
    return result;
}

#include "memory_mutation.inc"
#include "memory_pressure_exports.inc"

static void drainMutations() {
    onOwnerThread = true;
    while (!g_asyncFrame.deferredMutations.empty()) {
        auto mutation = std::move(g_asyncFrame.deferredMutations.front());
        g_asyncFrame.deferredMutations.pop_front();
        mutation();
    }
    onOwnerThread = false;
}

int main() {
    assert(maplibre_set_tile_cache_size(8) == 1);
    assert(renderer.cap == 8);
    assert(maplibre_reduce_memory_use() == 1);
    assert(renderer.reductions == 1);

    g_asyncFrame.acquired = true;
    assert(maplibre_set_tile_cache_size(0) == 1);
    assert(maplibre_reduce_memory_use() == 1);
    assert(renderer.cap == 8 && renderer.reductions == 1);
    assert(g_asyncFrame.deferredMutations.size() == 2);
    assert(g_pendingCameraMutations == 0);
    g_asyncFrame.acquired = false;
    drainMutations();
    assert(renderer.cap == 0 && renderer.reductions == 2);

    g_asyncFrame.rendering = true;
    assert(maplibre_reduce_memory_use() == 1);
    assert(renderer.reductions == 2);
    g_asyncFrame.rendering = false;
    drainMutations();
    assert(renderer.reductions == 3);

    g_asyncFrame.syncFrameOpen = true;
    assert(maplibre_set_tile_cache_size(UINT32_MAX) == 1);
    assert(renderer.cap == 0);
    g_asyncFrame.syncFrameOpen = false;
    drainMutations();
    assert(renderer.cap == UINT32_MAX);

    g_asyncFrame.ready = true;
    assert(maplibre_reduce_memory_use() == 1);
    assert(!g_asyncFrame.ready && renderer.reductions == 4);
    g_map = false;
    assert(maplibre_reduce_memory_use() == 0);
    assert(maplibre_set_tile_cache_size(2) == 0);
    assert(renderer.reductions == 4 && renderer.cap == UINT32_MAX);
    std::puts("Memory pressure respects Android frame leases and owner dispatch");
}
