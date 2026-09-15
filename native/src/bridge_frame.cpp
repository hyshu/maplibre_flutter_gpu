// Frame scheduling, command publication, and shallow snapshot leases.
#include "bridge_session.hpp"

#include <algorithm>
#include <cstdio>

#include <mln/renderer/renderer.hpp>
#include <mln/util/mat4.hpp>
#include <mln/util/projection.hpp>

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

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
static void captureMapTransform(const mln::TransformState& state) {
    g_mapTransformMetadata.valid = 0u;
    const auto size = state.getSize();
    if (size.isEmpty()) return;

    mln::mat4 matrix;
    // Match MapLibre's near-clipped projection for fill extrusion depth.
    const auto nearZ =
        static_cast<uint16_t>(0.1 * state.getCameraToCenterDistance());
    state.getProjMatrix(matrix, nearZ);

    const double worldSize = mln::Projection::worldSize(state.getScale());
    const double originX = 0.5 * worldSize - state.getX();
    const double originY = 0.5 * worldSize - state.getY();
    mln::matrix::translate(matrix, matrix, originX, originY, 0.0);
    for (std::size_t index = 0; index < matrix.size(); ++index) {
        g_mapTransformMetadata.viewProjectionMatrix[index] =
            static_cast<float>(matrix[index]);
    }
    g_mapTransformMetadata.worldSize = worldSize;
    g_mapTransformMetadata.originX = originX;
    g_mapTransformMetadata.originY = originY;
    g_mapTransformMetadata.zoom = state.getZoom();
    g_mapTransformMetadata.valid = 1u;
}

#ifdef __ANDROID__
static mln::LatLngBounds visibleRegionForTransform(
    const mln::TransformState& state) {
    const auto size = state.getSize();
    const auto unproject = [&](double apiX, double apiY) {
        return state.screenCoordinateToLatLng({
            apiX,
            static_cast<double>(size.height) - apiY});
    };
    auto northWest = unproject(0.0, 0.0);
    auto southEast = unproject(
        static_cast<double>(size.width),
        static_cast<double>(size.height));
    auto northEast =
        unproject(static_cast<double>(size.width), 0.0);
    auto southWest =
        unproject(0.0, static_cast<double>(size.height));
    const auto center = unproject(
        static_cast<double>(size.width) / 2.0,
        static_cast<double>(size.height) / 2.0);
    northWest.unwrapForShortestPath(center);
    southEast.unwrapForShortestPath(center);
    northEast.unwrapForShortestPath(center);
    southWest.unwrapForShortestPath(center);
    auto bounds = mln::LatLngBounds::hull(northWest, southEast);
    bounds.extend(northEast);
    bounds.extend(southWest);
    bounds.extend(center);
    return bounds;
}
#endif

static bool beginCommandFrameOnOwner(bool asynchronous = false) {
#ifdef __ANDROID__
    {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        if (g_asyncFrame.acquired ||
            (!asynchronous &&
             (g_asyncFrame.renderTaskQueued || g_asyncFrame.rendering ||
              g_asyncFrame.syncFrameOpen))) {
            return false;
        }
        // Synchronous startup rendering may supersede an unconsumed snapshot.
        // It runs on Dart's calling isolate, so an acquired lease cannot exist
        // concurrently with this legacy bracket.
        if (!g_asyncFrame.acquired) g_asyncFrame.ready = false;
        if (!asynchronous) g_asyncFrame.syncFrameOpen = true;
    }
#endif
    mln::command_export::getFrameData().clear();
    if (!g_labelCollectionEnabled) {
        auto* renderer = g_frontend ? g_frontend->getRenderer() : nullptr;
        if (renderer) {
            renderer->collectPlacedSymbolData(true);
            g_labelCollectionEnabled = true;
        }
    }
    return true;
}

static bool endCommandFrameOnOwner(
    const mln::TransformState* renderedState = nullptr) {
    auto& fd = mln::command_export::getFrameData();
    if (!g_map || !g_frontend) {
        fd.clear();
        g_snapshot.clear();
        g_snapshotClearColor.reset();
        bridge_resetMergeStorage();
        g_mapTransformMetadata.valid = 0u;
#ifdef __ANDROID__
        g_snapshotTransform.reset();
        g_snapshotCamera.reset();
        g_snapshotVisibleRegion.reset();
#endif
        return false;
    }

    bridge_mergeCommands(fd);
    g_snapshot.swap(fd.commands);
    g_snapshotClearColor = fd.clearColor;
    // Paint expressions, feature state, transforms, and layer order can change
    // without triggering placement. The exporter publishes only when bytes differ.
    bridge_extractLabels(renderedState);
#ifdef __ANDROID__
    if (renderedState) {
        g_snapshotTransform = *renderedState;
        g_snapshotCamera =
            renderedState->getCameraOptions(std::nullopt);
        g_snapshotVisibleRegion =
            visibleRegionForTransform(*renderedState);
    } else {
        g_snapshotTransform.reset();
        g_snapshotCamera.reset();
        g_snapshotVisibleRegion.reset();
    }
#endif
    if (renderedState) {
        captureMapTransform(*renderedState);
    } else {
        captureMapTransform(g_map->getTransfromState());
    }
    return true;
}

#ifdef __ANDROID__
static uint64_t publishFrameLease(uint64_t cameraRevision) {
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
static void runAsyncRenderOnOwner();

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
    if (bridge_runOnOwnerAsync([] { runAsyncRenderOnOwner(); })) return;

    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    g_asyncFrame.renderTaskQueued = false;
}

static void runAsyncRenderOnOwner() {
    std::deque<std::function<void()>> mutationsBeforeRender;
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
#endif // __ANDROID__
#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT

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

// Non-blocking render: processes pending camera changes, renders with current tiles
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

// ── Command Export backend: DrawCommand-based FFI ────────────────────
// These functions read FrameData populated by command_export::Drawable::draw().

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

MAPLIBRE_API void maplibre_request_label_extraction(void) {
    // Frame publication performs label extraction, so this request has no effect.
}

MAPLIBRE_API int maplibre_frame_get_command_count(void) {
    return static_cast<int>(g_snapshot.size());
}

MAPLIBRE_API const void* maplibre_frame_get_commands(void) {
    if (g_snapshot.empty()) return nullptr;
    return g_snapshot.data();
}

MAPLIBRE_API int maplibre_frame_get_command_stride(void) {
    return static_cast<int>(sizeof(mln::command_export::DrawCommand));
}

MAPLIBRE_API const float* maplibre_frame_get_clear_color(void) {
    return g_snapshotClearColor ? g_snapshotClearColor->data() : nullptr;
}

MAPLIBRE_API const FrameMetadata* maplibre_frame_get_metadata(void) {
    g_frameMetadata.commands = g_snapshot.empty() ? nullptr : g_snapshot.data();
    g_frameMetadata.commandCount = static_cast<int32_t>(g_snapshot.size());
    g_frameMetadata.commandStride =
        static_cast<int32_t>(sizeof(mln::command_export::DrawCommand));
    g_frameMetadata.hasClearColor = g_snapshotClearColor ? 1u : 0u;
    if (g_snapshotClearColor) {
        std::copy(
            g_snapshotClearColor->begin(),
            g_snapshotClearColor->end(),
            g_frameMetadata.clearColor);
    } else {
        std::fill(
            std::begin(g_frameMetadata.clearColor),
            std::end(g_frameMetadata.clearColor),
            0.0f);
    }
    return &g_frameMetadata;
}

MAPLIBRE_API const MapTransformMetadata* maplibre_frame_get_map_transform(void) {
#ifndef __ANDROID__
    try {
        bridge_runOnOwnerSync([] {
            if (g_map) captureMapTransform(g_map->getTransfromState());
        });
    } catch (...) {
        g_mapTransformMetadata.valid = 0u;
    }
#endif
    return &g_mapTransformMetadata;
}

#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT


} // extern "C"
