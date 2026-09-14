// Map sessions and owner-thread lifecycle.
#include "bridge_session.hpp"

#include <cstdio>
#include <unordered_set>

#include <mln/map/map_options.hpp>
#include <mln/renderer/renderer.hpp>
#include <mln/storage/resource_options.hpp>
#include <mln/style/style.hpp>
#include <mln/util/client_options.hpp>
#include <mln/util/constants.hpp>
#include <mln/util/run_loop.hpp>

static BridgeSession& legacySession() {
    static BridgeSession session;
    return session;
}
static std::unique_ptr<mln::util::RunLoop> g_runtimeRunLoop;
static std::mutex g_sessionRegistryMutex;
static std::unordered_set<BridgeSession*> g_sessionRegistry;
static thread_local BridgeSession* g_selectedSession = nullptr;

void* bridge_currentSession() {
    return g_selectedSession ? g_selectedSession : &legacySession();
}
void bridge_selectSession(void* session) {
    if (!session || session == &legacySession()) {
        g_selectedSession = &legacySession();
        return;
    }
    auto* candidate = static_cast<BridgeSession*>(session);
    std::lock_guard<std::mutex> lock(g_sessionRegistryMutex);
    g_selectedSession =
        g_sessionRegistry.contains(candidate) ? candidate : &legacySession();
}
std::unique_ptr<mln::HeadlessFrontend>& bridge_frontendStorage() {
    return static_cast<BridgeSession*>(bridge_currentSession())->frontend;
}
std::unique_ptr<mln::Map>& bridge_mapStorage() {
    return static_cast<BridgeSession*>(bridge_currentSession())->map;
}
std::unique_ptr<mln::util::RunLoop>& bridge_runLoopStorage() {
    return g_runtimeRunLoop;
}
#if MLN_RENDER_BACKEND_COMMAND_EXPORT
std::vector<mln::command_export::DrawCommand>& bridge_snapshotStorage() {
    return static_cast<BridgeSession*>(bridge_currentSession())->snapshot;
}
bool& bridge_labelCollectionEnabledStorage() {
    return static_cast<BridgeSession*>(bridge_currentSession())->labelCollectionEnabled;
}
#endif

void notifyRenderRequested() noexcept {
    std::lock_guard<std::mutex> lock(g_renderRequestCallbackMutex);
    const auto callback = g_renderRequestCallback.load(std::memory_order_acquire);
    if (callback) callback();
}

static void markCameraStateChanged() noexcept {
#ifdef __ANDROID__
    g_cameraStateRevision.fetch_add(1, std::memory_order_release);
#endif
}

void SimpleObserver::onCameraWillChange(CameraChangeMode mode) {
    BridgeSessionActivation activation(owner);
    g_mapIdle.store(false, std::memory_order_relaxed);
    g_cameraMoving.store(mode == CameraChangeMode::Animated, std::memory_order_relaxed);
    markCameraStateChanged();
}
void SimpleObserver::onCameraIsChanging() {
    BridgeSessionActivation activation(owner);
    g_mapIdle.store(false, std::memory_order_relaxed);
    markCameraStateChanged();
}
void SimpleObserver::onCameraDidChange(CameraChangeMode) {
    BridgeSessionActivation activation(owner);
    markCameraStateChanged();
    g_cameraMoving.store(false, std::memory_order_relaxed);
}
void SimpleObserver::onWillStartLoadingMap() {
    BridgeSessionActivation activation(owner);
    g_styleLoaded.store(false, std::memory_order_relaxed);
}
void SimpleObserver::onDidFinishLoadingStyle() {
    BridgeSessionActivation activation(owner);
    g_styleLoaded.store(true, std::memory_order_relaxed);
    printf("[MapLibre] Style loaded\n");
    fflush(stdout);
}
void SimpleObserver::onDidFailLoadingMap(
    mln::MapLoadError,
    const std::string& message) {
    BridgeSessionActivation activation(owner);
    g_styleLoaded.store(false, std::memory_order_relaxed);
    printf("[MapLibre] Style load failed: %s\n", message.c_str());
    fflush(stdout);
}
void SimpleObserver::onDidFinishRenderingFrame(const RenderFrameStatus& status) {
    BridgeSessionActivation activation(owner);
    const bool modeFull =
        status.mode == mln::MapObserver::RenderMode::Full;
    g_frameModeFull.store(modeFull, std::memory_order_relaxed);
    g_mapIdle = modeFull && !status.needsRepaint;
    g_frameNeedsRepaint.store(status.needsRepaint, std::memory_order_relaxed);
}

void BridgeFrontend::update(
    std::shared_ptr<mln::UpdateParameters> parameters) {
    BridgeSessionActivation activation(owner);
    mln::HeadlessFrontend::update(std::move(parameters));
    const bool wasDirty =
        g_renderDirty.exchange(true, std::memory_order_acq_rel);
    if (!wasDirty) notifyRenderRequested();
}

static void resetBridgeSession() {
#if MLN_RENDER_BACKEND_COMMAND_EXPORT
    resetAsyncFrameState();
    // DrawCommand contains pointers into renderer-owned and merged storage.
    // Make every exported view empty before destroying either owner.
    g_snapshot.clear();
    mln::command_export::getFrameData().clear();
#endif

    // Keep the shared runtime RunLoop alive until every session has released
    // its Map and Frontend.
    g_map.reset();
    g_frontend.reset();

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
    bridge_resetMergeStorage();
    bridge_resetLabels();
    g_snapshotClearColor.reset();
#ifdef __ANDROID__
    g_snapshotTransform.reset();
    g_snapshotCamera.reset();
    g_snapshotVisibleRegion.reset();
#endif
    g_labelCollectionEnabled = false;
    mln::command_export::setCurrentLayerIndex(0);
    bridge_releaseMergeSession(bridge_currentSession());
    bridge_releaseLabelSession(bridge_currentSession());
#endif
    bridge_releaseStyleSession(bridge_currentSession());

    g_drawables.clear();
    g_drawable_summary[0] = '\0';

    // Map destruction can emit a final observer callback, so reset this last.
    g_mapIdle.store(false, std::memory_order_relaxed);
    g_styleLoaded.store(false, std::memory_order_relaxed);
    g_cameraMoving.store(false, std::memory_order_relaxed);
    g_pendingCameraMutations.store(0, std::memory_order_relaxed);
    g_cameraStateRevision.store(0, std::memory_order_relaxed);
    g_cameraPresentedRevision.store(0, std::memory_order_relaxed);
    g_frameNeedsRepaint.store(false, std::memory_order_relaxed);
    g_frameModeFull.store(false, std::memory_order_relaxed);
    g_renderDirty.store(false, std::memory_order_relaxed);
    g_stationaryRepaintFrames = 0;
    g_snapshotWakePending.store(false, std::memory_order_relaxed);
    g_sessionActive.store(false, std::memory_order_release);
}

void bridge_handleOwnerThreadExit() noexcept {
    // Called before the owner RunLoop (and therefore Scheduler TLS) is
    // destroyed. resetBridgeSession is intentionally idempotent because the
    // normal destroy path has already performed the same teardown.
    g_sessionActive.store(false, std::memory_order_release);
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    {
        // DrawCommands are shallow views over renderer-owned buffers. A fatal
        // RunLoop exit must still honor an already acquired generation; the
        // painter releases it after its GPU submission or during dispose.
        std::unique_lock<std::mutex> lock(g_asyncFrame.mutex);
        g_asyncFrame.leaseReleased.wait(
            lock,
            [] { return !g_asyncFrame.acquired; });
    }
#endif
    try {
        resetBridgeSession();
    } catch (const std::exception& error) {
        std::fprintf(
            stderr,
            "[MapLibre] Owner teardown failed: %s\n",
            error.what());
        std::fflush(stderr);
    } catch (...) {
        std::fprintf(
            stderr,
            "[MapLibre] Owner teardown failed: unknown exception\n");
        std::fflush(stderr);
    }
}

void bridge_markStyleLoading() {
    g_mapIdle.store(false, std::memory_order_relaxed);
    g_styleLoaded.store(false, std::memory_order_relaxed);
#if MLN_RENDER_BACKEND_COMMAND_EXPORT
#ifdef __ANDROID__
    {
        // The style API first atomically discards an unacquired generation.
        // Keep queued camera/resize mutations and the pending render task:
        // a style reload must not silently lose accepted input.
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        if (!g_asyncFrame.acquired) g_asyncFrame.ready = false;
    }
    g_snapshotWakePending.store(false, std::memory_order_release);
#else
    resetAsyncFrameState();
#endif
    g_snapshot.clear();
    mln::command_export::getFrameData().clear();
    bridge_resetMergeStorage();
    bridge_resetLabels();
#ifdef __ANDROID__
    g_snapshotTransform.reset();
    g_snapshotCamera.reset();
    g_snapshotVisibleRegion.reset();
#endif
#endif
}

bool bridge_isStyleLoaded() {
    return g_styleLoaded.load(std::memory_order_relaxed);
}

extern "C" {

MAPLIBRE_API void* maplibre_session_create(void) {
    try {
        auto* session = new BridgeSession();
        {
            std::lock_guard<std::mutex> lock(g_sessionRegistryMutex);
            g_sessionRegistry.insert(session);
        }
        return session;
    } catch (...) {
        return nullptr;
    }
}

MAPLIBRE_API void maplibre_session_select(void* session) {
    bridge_selectSession(session);
}

MAPLIBRE_API void maplibre_session_release(void* session) {
    if (!session || session == &legacySession()) return;
    auto* owned = static_cast<BridgeSession*>(session);
    {
        std::lock_guard<std::mutex> lock(g_sessionRegistryMutex);
        if (!g_sessionRegistry.contains(owned) ||
            owned->state != BridgeSessionState::Idle) {
            return;
        }
        g_sessionRegistry.erase(owned);
    }
    if (bridge_currentSession() == session) {
        bridge_selectSession(nullptr);
    }
    delete owned;
}

MAPLIBRE_API int maplibre_init(int width, int height, float pixel_ratio, const char* style_url) {
    std::lock_guard<std::mutex> lifecycleLock(g_sessionLifecycleMutex);
    if (g_sessionState != BridgeSessionState::Idle) {
        printf("[MapLibre] Init rejected: native map session is already active\n");
        fflush(stdout);
        return -2;
    }

    g_sessionState = BridgeSessionState::Initializing;
    if (width <= 0 || height <= 0 || !std::isfinite(pixel_ratio) || pixel_ratio <= 0.0f ||
        !style_url || style_url[0] == '\0') {
        printf("[MapLibre] Init error: invalid map dimensions, pixel ratio, or style URL\n");
        fflush(stdout);
        g_sessionState = BridgeSessionState::Idle;
        return -1;
    }
    printf("[MapLibre] Initializing %dx%d ratio=%.1f style=%s\n", width, height, pixel_ratio, style_url);
    fflush(stdout);

    if (!bridge_startOwnerThread()) {
        printf("[MapLibre] Init error: failed to start shared runtime\n");
        fflush(stdout);
        bridge_stopOwnerThread();
        g_sessionState = BridgeSessionState::Idle;
        return -1;
    }

    try {
        bridge_runOnOwnerSync([&] {
            if (!g_run_loop) {
                throw std::runtime_error("shared runtime RunLoop is unavailable");
            }

            // Dart brackets each requested frame with frame_begin/frame_end, so
            // rendering must be synchronous and exactly once. Async invalidation
            // would render once in runOnce() and once again below.
            g_frontend = std::make_unique<BridgeFrontend>(
                static_cast<BridgeSession*>(bridge_currentSession()),
                mln::Size{static_cast<uint32_t>(width), static_cast<uint32_t>(height)},
                pixel_ratio,
                mln::gfx::HeadlessBackend::SwapBehaviour::NoFlush,
                mln::gfx::ContextMode::Unique,
                std::nullopt,
                false
            );

            mln::ResourceOptions resourceOptions;
#ifdef __APPLE__
            resourceOptions.withCachePath(std::string(getenv("HOME") ? getenv("HOME") : "/tmp") + "/Library/Caches/mbgl-cache.db");
#elif defined(__ANDROID__)
            // Android applications cannot write to /tmp. Keep ResourceOptions'
            // in-memory SQLite cache; networking remains backed by the Android
            // HTTP bridge.
#elif defined(_WIN32)
            // Keep the cache in memory because a portable Windows bundle has
            // no stable writable directory shared by every host application.
#else
            resourceOptions.withCachePath("/tmp/mbgl-cache.db");
#endif

            mln::ClientOptions clientOptions;

            mln::MapOptions mapOptions;
            mapOptions.withSize(mln::Size{
                static_cast<uint32_t>(width),
                static_cast<uint32_t>(height)
            });
            mapOptions.withPixelRatio(pixel_ratio);
            mapOptions.withMapMode(mln::MapMode::Continuous);

            g_map = std::make_unique<mln::Map>(
                *g_frontend,
                g_observer,
                mapOptions,
                resourceOptions,
                clientOptions
            );

            const std::string styleInput(style_url);
            const auto firstContent = styleInput.find_first_not_of(" \t\r\n");
            if (firstContent != std::string::npos && styleInput[firstContent] == '{') {
                g_map->getStyle().loadJSON(styleInput);
            } else {
                g_map->getStyle().loadURL(styleInput);
            }
            // Publish from the owner task so an abnormal RunLoop exit always
            // performs the later, winning transition back to inactive.
            g_sessionActive.store(true, std::memory_order_release);
        });

        if (!bridge_ownerThreadRunning()) {
            throw std::runtime_error(
                "shared runtime stopped during initialization");
        }
        printf("[MapLibre] Initialized successfully\n");
        fflush(stdout);
        g_sessionState = BridgeSessionState::Active;
        return 0;
    } catch (const std::exception& e) {
        printf("[MapLibre] Init error: %s\n", e.what());
        fflush(stdout);
        try {
            bridge_runOnOwnerSync([] { resetBridgeSession(); });
        } catch (...) {
        }
        bridge_stopOwnerThread();
        g_sessionState = BridgeSessionState::Idle;
        return -1;
    } catch (...) {
        printf("[MapLibre] Init error: unknown exception\n");
        fflush(stdout);
        try {
            bridge_runOnOwnerSync([] { resetBridgeSession(); });
        } catch (...) {
        }
        bridge_stopOwnerThread();
        g_sessionState = BridgeSessionState::Idle;
        return -1;
    }
}

MAPLIBRE_API void maplibre_destroy(void) {
    std::lock_guard<std::mutex> lifecycleLock(g_sessionLifecycleMutex);
    if (g_sessionState != BridgeSessionState::Active) return;
    g_sessionState = BridgeSessionState::Destroying;
    g_sessionActive.store(false, std::memory_order_release);
    {
        std::lock_guard<std::mutex> lock(g_renderRequestCallbackMutex);
        g_renderRequestCallback.store(nullptr, std::memory_order_release);
    }
    try {
        bridge_runOnOwnerSync([] {
            resetBridgeSession();
        });
    } catch (...) {
    }
    bridge_stopOwnerThread();
    g_sessionState = BridgeSessionState::Idle;
    printf("[MapLibre] Destroyed\n");
    fflush(stdout);
}

MAPLIBRE_API void maplibre_shutdown_all(void) {
    bridge_shutdownOwnerRuntime();
}


} // extern "C"
