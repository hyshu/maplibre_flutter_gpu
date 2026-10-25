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

// Pausing waits behind in-flight owner work and prevents queued render tasks
// from starting. Existing leases remain valid and must still be released.
// Resuming opens the gate without waiting for other maps on the shared owner.
MAPLIBRE_API int maplibre_set_rendering_paused(int paused) {
    if (!g_sessionActive.load(std::memory_order_acquire)) return 0;
    const bool shouldPause = paused != 0;
    if (!shouldPause && !bridge_ownerThreadRunning()) return 0;
    bool wasPaused;
    uint64_t requestGeneration;
    {
        std::lock_guard<std::mutex> lock(g_renderPauseMutex);
        requestGeneration = ++g_renderPauseRequestGeneration;
        wasPaused =
            g_renderingPaused.exchange(shouldPause, std::memory_order_acq_rel);
        if (wasPaused != shouldPause) {
            g_renderTaskEpoch.fetch_add(1, std::memory_order_acq_rel);
        }
    }
    const auto restoreGate = [wasPaused, shouldPause, requestGeneration] {
        std::lock_guard<std::mutex> lock(g_renderPauseMutex);
        if (requestGeneration != g_renderPauseRequestGeneration) return;
        if (wasPaused == shouldPause) return;
        bool expected = shouldPause;
        if (g_renderingPaused.compare_exchange_strong(
                expected, wasPaused, std::memory_order_acq_rel)) {
            g_renderTaskEpoch.fetch_add(1, std::memory_order_acq_rel);
        }
    };
    try {
        if (!shouldPause) {
            // The caller schedules the next frame after reopening its display
            // gate. No owner-thread state needs to change before that frame.
            g_renderDirty.store(true, std::memory_order_release);
            return 1;
        }
        const auto result = bridge_runOnOwnerSync([requestGeneration] {
            if (!g_sessionActive.load(std::memory_order_acquire)) return 0;
            {
                std::lock_guard<std::mutex> lock(g_renderPauseMutex);
                if (requestGeneration != g_renderPauseRequestGeneration) return 0;
            }
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
            std::deque<std::function<void()>> mutations;
            {
                std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
                discardUnacquiredFrameLocked();
                g_asyncFrame.renderDeferred = false;
                g_asyncFrame.renderTaskQueued = false;
                g_asyncFrame.syncFrameOpen = false;
                if (!g_asyncFrame.acquired) {
                    mutations.swap(g_asyncFrame.deferredMutations);
                }
            }
            for (auto& mutation : mutations) mutation();
#endif
            g_renderDirty.store(true, std::memory_order_release);
            return 1;
        });
        if (result == 0) restoreGate();
        return result;
    } catch (const std::exception& error) {
        restoreGate();
        std::printf("[MapLibre] Rendering pause failed: %s\n", error.what());
        std::fflush(stdout);
        return 0;
    } catch (...) {
        restoreGate();
        std::printf("[MapLibre] Rendering pause failed: unknown exception\n");
        std::fflush(stdout);
        return 0;
    }
}

// Pausing closes the gate before this returns. Completion runs exactly once, after
// the shared owner reaches the barrier or rejects the request. Resume opens
// the gate at its barrier so callers do not render into known owner backlog.
MAPLIBRE_API void maplibre_set_rendering_paused_async(
    int paused, void (*callback)(int)) {
    if (!callback) return;
    struct Completion {
        explicit Completion(void (*callback_)(int)) : callback(callback_) {}
        ~Completion() { finish(0); }
        void finish(int result) {
            if (!completed.exchange(true)) callback(result);
        }
        void (*callback)(int);
        std::atomic<bool> completed{false};
    };
    auto completion = std::make_shared<Completion>(callback);
    if (!g_sessionActive.load(std::memory_order_acquire)) return;

    const bool shouldPause = paused != 0;
    bool wasPaused;
    std::optional<uint64_t> previousCancellation;
    uint64_t requestGeneration;
    {
        std::lock_guard<std::mutex> lock(g_renderPauseMutex);
        requestGeneration = ++g_renderPauseRequestGeneration;
        wasPaused = g_renderingPaused.load(std::memory_order_acquire);
        previousCancellation = g_renderPauseCameraCancellation;
        if (shouldPause) {
            g_renderPauseCameraCancellation =
                g_cameraCommandGeneration.load(std::memory_order_acquire);
        }
        if (shouldPause && !wasPaused) {
            g_renderingPaused.store(true, std::memory_order_release);
            g_renderTaskEpoch.fetch_add(1, std::memory_order_acq_rel);
        }
    }
    const auto restoreGate = [wasPaused, requestGeneration, previousCancellation] {
        std::lock_guard<std::mutex> lock(g_renderPauseMutex);
        if (requestGeneration != g_renderPauseRequestGeneration) return;
        g_renderPauseCameraCancellation = previousCancellation;
        if (g_renderingPaused.exchange(wasPaused) != wasPaused) {
            g_renderTaskEpoch.fetch_add(1, std::memory_order_acq_rel);
        }
    };
    const auto isCurrent = [requestGeneration] {
        std::lock_guard<std::mutex> lock(g_renderPauseMutex);
        return requestGeneration == g_renderPauseRequestGeneration &&
               g_sessionActive.load(std::memory_order_acquire);
    };
    const auto finishOnOwner = [completion, isCurrent, restoreGate,
                               requestGeneration, shouldPause] {
        if (!isCurrent()) {
            completion->finish(0);
            return;
        }
        try {
            std::optional<uint64_t> cancellation;
            {
                std::lock_guard<std::mutex> lock(g_renderPauseMutex);
                if (requestGeneration == g_renderPauseRequestGeneration) {
                    cancellation.swap(g_renderPauseCameraCancellation);
                }
            }
            // A resume inherits an earlier pause's cancellation. A later
            // camera command replaces that obligation before it can run.
            if (cancellation &&
                *cancellation == g_cameraCommandGeneration.load(std::memory_order_acquire) &&
                g_map) {
                g_map->cancelTransitions();
                g_map->setGestureInProgress(false);
                g_cameraMoving.store(false, std::memory_order_relaxed);
            }
            bool applied = false;
            {
                std::lock_guard<std::mutex> lock(g_renderPauseMutex);
                if (requestGeneration == g_renderPauseRequestGeneration) {
                    g_renderDirty.store(true, std::memory_order_release);
                    if (g_renderingPaused.exchange(shouldPause) != shouldPause) {
                        g_renderTaskEpoch.fetch_add(1, std::memory_order_acq_rel);
                    }
                    applied = true;
                }
            }
            completion->finish(applied ? 1 : 0);
        } catch (...) {
            restoreGate();
            completion->finish(0);
        }
    };
    try {
        const bool posted = bridge_runOnOwnerAsync(
            [completion, isCurrent, finishOnOwner, restoreGate] {
                if (!isCurrent()) {
                    completion->finish(0);
                    return;
                }
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
                std::deque<std::function<void()>> mutations;
                {
                    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
                    discardUnacquiredFrameLocked();
                    g_asyncFrame.renderDeferred = false;
                    g_asyncFrame.renderTaskQueued = false;
                    g_asyncFrame.syncFrameOpen = false;
                    if (g_asyncFrame.acquired) {
                        // Camera mutations retain the same lease protection as
                        // normal updates. Releasing the lease completes pause.
                        g_asyncFrame.deferredMutations.push_back(finishOnOwner);
                        return;
                    }
                    mutations.swap(g_asyncFrame.deferredMutations);
                }
                try {
                    for (auto& mutation : mutations) mutation();
                } catch (...) {
                    restoreGate();
                    completion->finish(0);
                    return;
                }
#endif
                finishOnOwner();
            });
        if (!posted) restoreGate();
    } catch (...) {
        restoreGate();
    }
}

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
        if (g_renderingPaused.load(std::memory_order_acquire)) return 0;
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
            if (g_renderingPaused.load(std::memory_order_acquire)) return -3;
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
#if MLN_RENDER_BACKEND_COMMAND_EXPORT
            // Frontend updates can advance after rendering and before export.
            const auto renderedState = g_frontend->getTransformState();
            g_renderedFrameTransform.reset();
#endif
            // Updates ordered before this task are represented by this render.
            // Any update
            // arriving during render sets the flag again and triggers another wake.
            g_renderDirty.store(false, std::memory_order_release);
            g_frontend->renderFrame();
#if MLN_RENDER_BACKEND_COMMAND_EXPORT
            g_renderedFrameTransform = renderedState;
#endif
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
        if (g_renderingPaused.load(std::memory_order_acquire)) return;
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
            if (g_renderingPaused.load(std::memory_order_acquire)) return false;
            const bool result = endCommandFrameOnOwner(
                g_renderedFrameTransform ? &*g_renderedFrameTransform : nullptr);
            g_renderedFrameTransform.reset();
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
