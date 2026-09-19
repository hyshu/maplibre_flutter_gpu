// Synchronous frame rendering and render-request scheduling.
#include "frame/command_frame.hpp"

#include <cstdio>

void bridge_finishRenderOnOwner() {
    const bool cameraMoving = g_cameraMoving.load(std::memory_order_relaxed);
    const bool needsRepaint = g_frameNeedsRepaint.load(std::memory_order_relaxed);
    const bool stationaryTransitionExpired =
        g_stationaryRepaintBudget.expired(cameraMoving, needsRepaint);
    const bool shouldContinue =
        (cameraMoving || needsRepaint) && !stationaryTransitionExpired;

    // Rendering can synchronously publish its own follow-up update. Resource
    // arrivals run on this same owner queue and wake a later frame separately.
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
#endif
    g_renderDirty.store(shouldContinue, std::memory_order_release);
    if (stationaryTransitionExpired) {
        g_frameNeedsRepaint.store(false, std::memory_order_relaxed);
    }
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    // An in-flight self-update can already have requested the next frame.
    // Camera mutations keep their deferred work and are applied before rendering.
    if (!shouldContinue && g_asyncFrame.deferredMutations.empty()) {
        g_asyncFrame.renderDeferred = false;
    }
#endif
}

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
void resetAsyncFrameState() {
#ifdef __ANDROID__
    {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        g_asyncFrame.ready = false;
        g_asyncFrame.acquired = false;
        g_asyncFrame.renderTaskQueued = false;
        g_asyncFrame.rendering = false;
        g_asyncFrame.renderDeferred = false;
        g_asyncFrame.syncFrameOpen = false;
        g_asyncFrame.deferredMutations.clear();
    }
    g_asyncFrame.leaseReleased.notify_all();
#endif
}
#endif

void discardUnacquiredFrameLocked() {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    if (g_asyncFrame.ready && !g_asyncFrame.acquired) {
        g_asyncFrame.ready = false;
        g_snapshotWakePending.store(false, std::memory_order_release);
    }
#endif
}

bool bridge_prepareSynchronousMutation() {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    discardUnacquiredFrameLocked();
    if (g_asyncFrame.acquired || g_asyncFrame.rendering ||
        g_asyncFrame.syncFrameOpen) {
        return false;
    }
#endif
    return true;
}

extern "C" {

// True when the map is fully rendered and settled (no pending tiles or
// transitions). Dart keeps a repaint loop running until this turns 1.
MAPLIBRE_API int maplibre_is_idle(void) {
    return g_mapIdle ? 1 : 0;
}

MAPLIBRE_API int maplibre_is_style_loaded(void) {
    return g_styleLoaded ? 1 : 0;
}

// Register an isolate-safe wake callback. The callback can be invoked from any
// thread. Dart must marshal the actual render back to the map's owning isolate.
MAPLIBRE_API void maplibre_set_render_request_callback(RenderRequestCallback callback) {
    {
        // Null registration waits for an in-flight native callback to finish,
        // so Dart may close its NativeCallable immediately after this returns.
        std::lock_guard<std::mutex> lock(g_renderRequestCallbackMutex);
        g_renderRequestCallback.store(callback, std::memory_order_release);
    }
    if (callback && g_renderDirty.load(std::memory_order_acquire)) {
        notifyRenderRequested();
    }
}

// Pump MapLibre's owner run loop without producing a GPU frame. Returns true
// only when MapLibre published new renderer parameters.
MAPLIBRE_API int maplibre_process_events(void) {
    try {
        // The shared RunLoop runs continuously. HTTP responses, timers, actor
        // messages, and session work are already drained on its owner thread.
        const bool dirty = g_renderDirty.load(std::memory_order_acquire);
        const bool snapshotReady =
            g_snapshotWakePending.exchange(false, std::memory_order_acq_rel);
        return (dirty || snapshotReady) ? 1 : 0;
    } catch (const std::exception& e) {
        printf("[MapLibre] ProcessEvents error: %s\n", e.what());
        fflush(stdout);
        return 0;
    }
}

MAPLIBRE_API int maplibre_frame_needs_repaint(void) {
    return g_frameNeedsRepaint.load(std::memory_order_relaxed) ? 1 : 0;
}

// Renders current tiles after earlier camera mutations reach the owner thread.
MAPLIBRE_API int maplibre_render_frame(void) {
    try {
        return bridge_runOnOwnerSync([] {
#ifdef __ANDROID__
            const auto closeSyncFrame = [] {
                std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
                g_asyncFrame.syncFrameOpen = false;
            };
            if (!g_map || !g_frontend || !g_run_loop) {
                closeSyncFrame();
                return -1;
            }
            {
                std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
                if (!g_asyncFrame.syncFrameOpen) return -2;
            }
            if (!beginCommandFrameOnOwner(true)) {
                closeSyncFrame();
                return -2;
            }
            const auto renderedState = g_frontend->getTransformState();
            if (!renderedState) {
                closeSyncFrame();
                return -1;
            }
            const auto renderedCameraRevision =
                g_cameraStateRevision.load(std::memory_order_acquire);
            g_renderDirty.store(false, std::memory_order_release);
            g_frontend->renderFrame();
            bridge_finishRenderOnOwner();
            const bool published =
                endCommandFrameOnOwner(&*renderedState);
            closeSyncFrame();
            if (published) publishFrameLease(renderedCameraRevision);
            return published ? 0 : -1;
#else
            if (!g_map || !g_frontend || !g_run_loop) return -1;
            // Updates ordered before this task are represented by this render.
            // Any update
            // arriving during render sets the flag again and triggers another wake.
            g_renderDirty.store(false, std::memory_order_release);
            g_frontend->renderFrame();
            return 0;
#endif
        });
    } catch (const std::exception& e) {
#ifdef __ANDROID__
        {
            std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
            g_asyncFrame.syncFrameOpen = false;
        }
#endif
        printf("[MapLibre] RenderFrame error: %s\n", e.what());
        fflush(stdout);
        return -1;
    }
}

// Frame brackets are serialized with publication on the owner thread.

#if MLN_RENDER_BACKEND_COMMAND_EXPORT

MAPLIBRE_API void maplibre_frame_begin(void) {
    try {
#ifdef __ANDROID__
        bool accepted = false;
        {
            std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
            if (!g_asyncFrame.acquired && !g_asyncFrame.renderTaskQueued &&
                !g_asyncFrame.rendering && !g_asyncFrame.syncFrameOpen) {
                g_asyncFrame.ready = false;
                g_asyncFrame.syncFrameOpen = true;
                accepted = true;
            }
        }
        if (accepted) {
            g_snapshotWakePending.store(false, std::memory_order_release);
        }
#else
        const bool accepted =
            bridge_runOnOwnerSync([] { return beginCommandFrameOnOwner(); });
#endif
        if (!accepted) {
            std::printf(
                "[MapLibre] FrameBegin rejected: snapshot/render in progress\n");
            std::fflush(stdout);
        }
    } catch (const std::exception& error) {
        std::printf("[MapLibre] FrameBegin error: %s\n", error.what());
        std::fflush(stdout);
    }
}

MAPLIBRE_API void maplibre_frame_end(void) {
    try {
#ifdef __ANDROID__
        // Android performs begin/render/export/capture/publish atomically in
        // maplibre_render_frame. This compatibility terminator only closes a
        // bracket whose render failed or was skipped.
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        g_asyncFrame.syncFrameOpen = false;
#else
        const bool published = bridge_runOnOwnerSync([] {
            const bool result = endCommandFrameOnOwner();
            return result;
        });
        (void)published;
#endif
    } catch (const std::exception& error) {
#ifdef __ANDROID__
        {
            std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
            g_asyncFrame.syncFrameOpen = false;
        }
#endif
        std::printf("[MapLibre] FrameEnd error: %s\n", error.what());
        std::fflush(stdout);
    } catch (...) {
#ifdef __ANDROID__
        {
            std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
            g_asyncFrame.syncFrameOpen = false;
        }
#endif
        std::printf("[MapLibre] FrameEnd error: unknown exception\n");
        std::fflush(stdout);
    }
}

#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT

} // extern "C"
