// Queued Android renders and the lifetime of shallow frame leases.
#include "command_frame.hpp"

#include <cstdio>

#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
uint64_t publishFrameLease(uint64_t cameraRevision) {
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    g_asyncFrame.generation++;
    if (g_asyncFrame.generation == 0) g_asyncFrame.generation++;
    g_cameraPresentedRevision.store(
        cameraRevision,
        std::memory_order_release);
    g_asyncFrame.ready = true;
    return g_asyncFrame.generation;
}

static void prepareAsyncRenderOnOwner();
static void runAsyncRenderOnOwner(uint64_t preparedCameraRevision);

static void executeDeferredMutationsOnOwner(
    std::deque<std::function<void()>>& mutations) noexcept {
    for (auto& mutation : mutations) {
        try {
            mutation();
        } catch (const std::exception& error) {
            std::printf(
                "[MapLibre] Deferred mutation failed: %s\n",
                error.what());
            std::fflush(stdout);
        } catch (...) {
            std::printf(
                "[MapLibre] Deferred mutation failed: unknown exception\n");
            std::fflush(stdout);
        }
    }
}

static void scheduleRenderAfterDeferredMutationsOnOwner(
    std::deque<std::function<void()>> mutations) {
    executeDeferredMutationsOnOwner(mutations);
    {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        if (!g_sessionActive.load(std::memory_order_acquire)) {
            g_asyncFrame.renderTaskQueued = false;
            return;
        }
        g_asyncFrame.renderTaskQueued = true;
    }
    if (bridge_runOnOwnerAsync([] { prepareAsyncRenderOnOwner(); })) return;

    {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        g_asyncFrame.renderTaskQueued = false;
    }
    g_renderDirty.store(true, std::memory_order_release);
    notifyRenderRequested();
}

static bool enqueueAsyncRenderTask() {
    {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        // Check under the same lock as frame completion so a stale dirty read
        // cannot restore a deferred self-update after its budget has expired.
        if (!g_renderDirty.load(std::memory_order_acquire) &&
            (g_asyncFrame.ready || g_asyncFrame.acquired ||
             g_asyncFrame.renderTaskQueued || g_asyncFrame.rendering)) {
            return false;
        }
        if (g_asyncFrame.renderTaskQueued) return true;
        if (g_asyncFrame.syncFrameOpen) {
            g_asyncFrame.renderDeferred = true;
            return true;
        }
        if (g_asyncFrame.ready || g_asyncFrame.acquired ||
            g_asyncFrame.rendering) {
            g_asyncFrame.renderDeferred = true;
            return true;
        }
        g_asyncFrame.renderTaskQueued = true;
    }
    if (bridge_runOnOwnerAsync([] { prepareAsyncRenderOnOwner(); })) return true;

    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    g_asyncFrame.renderTaskQueued = false;
    return false;
}

static void prepareAsyncRenderOnOwner() {
    {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        if (!g_sessionActive.load(std::memory_order_acquire)) {
            g_asyncFrame.renderTaskQueued = false;
            return;
        }
        if (g_asyncFrame.syncFrameOpen || g_asyncFrame.ready ||
            g_asyncFrame.acquired || g_asyncFrame.rendering) {
            g_asyncFrame.renderTaskQueued = false;
            g_asyncFrame.renderDeferred = true;
            return;
        }
    }

    // Camera mutations that ran before this stage can enqueue MapLibre
    // UpdateParameters behind it. Put the actual frame bracket at the tail so
    // those updates execute first without recursively calling runOnce().
    const auto cameraRevision =
        g_cameraStateRevision.load(std::memory_order_acquire);
    if (bridge_runOnOwnerAsync([cameraRevision] {
            runAsyncRenderOnOwner(cameraRevision);
        })) return;

    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    g_asyncFrame.renderTaskQueued = false;
}

static void runAsyncRenderOnOwner(uint64_t preparedCameraRevision) {
    std::deque<std::function<void()>> mutationsBeforeRender;
    bool prepareAgain = false;
    {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        g_asyncFrame.renderTaskQueued = false;
        if (!g_sessionActive.load(std::memory_order_acquire)) return;
        if (g_asyncFrame.syncFrameOpen || g_asyncFrame.ready ||
            g_asyncFrame.acquired) {
            g_asyncFrame.renderDeferred = true;
            return;
        }
        if (!g_asyncFrame.deferredMutations.empty()) {
            mutationsBeforeRender.swap(g_asyncFrame.deferredMutations);
            g_asyncFrame.renderTaskQueued = true;
        } else if (preparedCameraRevision !=
                   g_cameraStateRevision.load(std::memory_order_acquire)) {
            // Camera changes after preparation may have queued their frontend
            // update behind this task. Drain it before publishing that camera.
            g_asyncFrame.renderTaskQueued = true;
            prepareAgain = true;
        } else {
            g_asyncFrame.rendering = true;
            g_asyncFrame.renderDeferred = false;
        }
    }
    if (!mutationsBeforeRender.empty()) {
        scheduleRenderAfterDeferredMutationsOnOwner(
            std::move(mutationsBeforeRender));
        return;
    }
    if (prepareAgain) {
        if (bridge_runOnOwnerAsync([] { prepareAsyncRenderOnOwner(); })) return;

        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        g_asyncFrame.renderTaskQueued = false;
        return;
    }

    bool published = false;
    uint64_t renderedCameraRevision = 0;
    try {
        if (!beginCommandFrameOnOwner(true)) {
            throw std::runtime_error("frame snapshot is currently acquired");
        }
        if (!g_map || !g_frontend || !g_run_loop) {
            throw std::runtime_error("native map is unavailable");
        }
        const auto renderedState = g_frontend->getTransformState();
        if (!renderedState) {
            throw std::runtime_error("renderer transform is unavailable");
        }
        renderedCameraRevision =
            g_cameraStateRevision.load(std::memory_order_acquire);
        // Updates processed above belong to this frame. A concurrent update
        // flips the flag back to true and is rendered after lease release.
        g_renderDirty.store(false, std::memory_order_release);
        g_frontend->renderFrame();
        bridge_finishRenderOnOwner();
        published = endCommandFrameOnOwner(&*renderedState);
    } catch (const std::exception& error) {
        std::printf("[MapLibre] Async RenderFrame error: %s\n", error.what());
        std::fflush(stdout);
    } catch (...) {
        std::printf("[MapLibre] Async RenderFrame error: unknown exception\n");
        std::fflush(stdout);
    }

    if (published) {
        std::deque<std::function<void()>> staleFrameMutations;
        bool frameWasSuperseded = false;
        {
            std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
            g_asyncFrame.rendering = false;
            if (!g_asyncFrame.deferredMutations.empty()) {
                staleFrameMutations.swap(g_asyncFrame.deferredMutations);
                g_asyncFrame.ready = false;
                g_asyncFrame.renderDeferred = false;
                g_asyncFrame.renderTaskQueued = true;
                frameWasSuperseded = true;
            } else {
                g_asyncFrame.generation++;
                if (g_asyncFrame.generation == 0) {
                    g_asyncFrame.generation++;
                }
                g_cameraPresentedRevision.store(
                    renderedCameraRevision,
                    std::memory_order_release);
                g_asyncFrame.ready = true;
            }
        }
        if (frameWasSuperseded) {
            g_snapshotWakePending.store(false, std::memory_order_release);
            scheduleRenderAfterDeferredMutationsOnOwner(
                std::move(staleFrameMutations));
            return;
        }
        g_snapshotWakePending.store(true, std::memory_order_release);
        // Completion and MapLibre invalidation share one isolate-safe wake.
        // render_frame_async rejects the feedback request while no new input
        // is dirty, so this cannot create a completion loop.
        notifyRenderRequested();
    } else {
        std::deque<std::function<void()>> failedFrameMutations;
        {
            std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
            g_asyncFrame.rendering = false;
            g_asyncFrame.ready = false;
            g_asyncFrame.renderDeferred = false;
            g_asyncFrame.renderTaskQueued = false;
            failedFrameMutations.swap(g_asyncFrame.deferredMutations);
        }
        executeDeferredMutationsOnOwner(failedFrameMutations);
        g_snapshotWakePending.store(false, std::memory_order_release);
        g_renderDirty.store(true, std::memory_order_release);
        notifyRenderRequested();
    }
}
#endif

extern "C" {
MAPLIBRE_API int maplibre_async_render_supported(void) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    return g_sessionActive.load(std::memory_order_acquire) &&
                   bridge_ownerThreadRunning()
               ? 1
               : 0;
#else
    return 0;
#endif
}

MAPLIBRE_API int maplibre_render_frame_async(void) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    if (!g_sessionActive.load(std::memory_order_acquire)) return 0;
    return enqueueAsyncRenderTask() ? 1 : 0;
#else
    return 0;
#endif
}

MAPLIBRE_API uint64_t maplibre_frame_acquire(void) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    if (!g_sessionActive.load(std::memory_order_acquire)) return 0;
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    if (!g_sessionActive.load(std::memory_order_acquire) ||
        !g_asyncFrame.ready || g_asyncFrame.acquired) {
        return 0;
    }
    g_asyncFrame.acquired = true;
    return g_asyncFrame.generation;
#else
    return 0;
#endif
}

MAPLIBRE_API void maplibre_frame_release(uint64_t generation) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    bool shouldRender = false;
    bool ownerActive = false;
    std::deque<std::function<void()>> deferredMutations;
    {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        if (!g_asyncFrame.acquired || generation == 0 ||
            generation != g_asyncFrame.generation) {
            return;
        }
        g_asyncFrame.acquired = false;
        g_asyncFrame.ready = false;
        ownerActive =
            g_sessionActive.load(std::memory_order_acquire);
        if (ownerActive) {
            deferredMutations.swap(g_asyncFrame.deferredMutations);
            shouldRender =
                g_asyncFrame.renderDeferred ||
                g_renderDirty.load(std::memory_order_acquire);
            g_asyncFrame.renderDeferred = false;
            if (shouldRender) g_asyncFrame.renderTaskQueued = true;
        }
    }
    // Release remains valid after an abnormal owner exit. The owner teardown
    // waits on this notification before destroying shallow command storage.
    g_asyncFrame.leaseReleased.notify_all();
    if (!ownerActive) return;

    bool posted = true;
    for (auto& mutation : deferredMutations) {
        if (!bridge_runOnOwnerAsync(std::move(mutation))) {
            posted = false;
            break;
        }
    }
    if (posted && shouldRender) {
        posted = bridge_runOnOwnerAsync([] { prepareAsyncRenderOnOwner(); });
    }
    if (!posted && shouldRender) {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        g_asyncFrame.renderTaskQueued = false;
    }
#else
    (void)generation;
#endif
}

} // extern "C"
