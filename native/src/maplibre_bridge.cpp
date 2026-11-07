// Map sessions and owner-thread lifecycle.
#include "bridge_session.hpp"

#include <cstdio>
#include <algorithm>
#include <cmath>
#include <limits>
#include <unordered_set>

#include <mln/map/map_options.hpp>
#include <mln/renderer/renderer.hpp>
#include <mln/storage/resource_options.hpp>
#include <mln/style/style.hpp>
#include <mln/style/layer.hpp>
#include <mln/style/light.hpp>
#include <mln/util/client_options.hpp>
#include <mln/util/constants.hpp>
#include <mln/util/run_loop.hpp>

#if defined(__ANDROID__) && defined(MAPLIBRE_ANDROID_TILE_DIAGNOSTICS) && MAPLIBRE_ANDROID_TILE_DIAGNOSTICS
#include <android/log.h>
#include <cinttypes>
#include <ctime>
#include <mln/tile/tile_id.hpp>

namespace {
const char* tileTraceOperation(mln::TileOperation operation) {
    switch (operation) {
        case mln::TileOperation::RequestedFromCache: return "RequestedFromCache";
        case mln::TileOperation::RequestedFromNetwork: return "RequestedFromNetwork";
        case mln::TileOperation::LoadFromNetwork: return "LoadFromNetwork";
        case mln::TileOperation::LoadFromCache: return "LoadFromCache";
        case mln::TileOperation::StartParse: return "StartParse";
        case mln::TileOperation::EndParse: return "EndParse";
        case mln::TileOperation::Error: return "Error";
        case mln::TileOperation::Cancelled: return "Cancelled";
        case mln::TileOperation::NullOp: return "NullOp";
    }
    return "Unknown";
}

void traceTileAction(uint64_t session,
                     uint64_t event,
                     mln::TileOperation operation,
                     const mln::OverscaledTileID& id,
                     const std::string& source) {
    timespec now{};
    const bool clockOk = clock_gettime(CLOCK_MONOTONIC, &now) == 0;
    const uint64_t timestamp = clockOk
        ? static_cast<uint64_t>(now.tv_sec) * 1000000000ULL + static_cast<uint64_t>(now.tv_nsec)
        : 0;

    // Hex keeps arbitrary source bytes on one bounded log line. Truncation must
    // be rejected by consumers that need a complete source identity.
    constexpr size_t sourceLimit = 512;
    constexpr char hex[] = "0123456789abcdef";
    const size_t sourceSize = std::min(source.size(), sourceLimit);
    char sourceHex[sourceLimit * 2 + 1];
    for (size_t i = 0; i < sourceSize; ++i) {
        const auto byte = static_cast<unsigned char>(source[i]);
        sourceHex[i * 2] = hex[byte >> 4];
        sourceHex[i * 2 + 1] = hex[byte & 15];
    }
    sourceHex[sourceSize * 2] = '\0';
    __android_log_print(
        ANDROID_LOG_INFO, "MapTileTrace",
        "{\"schema\":1,\"session\":%" PRIu64 ",\"event\":%" PRIu64
        ",\"time_ns\":%" PRIu64 ",\"clock_ok\":%s,\"operation\":\"%s\",\"op\":%u"
        ",\"z\":%u,\"x\":%" PRIu32 ",\"y\":%" PRIu32 ",\"overscaled_z\":%u,\"wrap\":%d"
        ",\"source_hex\":\"%s\",\"source_bytes\":%zu,\"source_truncated\":%s}",
        session, event, timestamp, clockOk ? "true" : "false", tileTraceOperation(operation),
        static_cast<unsigned>(operation), static_cast<unsigned>(id.canonical.z),
        id.canonical.x, id.canonical.y, static_cast<unsigned>(id.overscaledZ),
        static_cast<int>(id.wrap), sourceHex, source.size(), sourceSize == source.size() ? "false" : "true");
}
} // namespace
#endif

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
    if (g_renderingPaused.load(std::memory_order_acquire)) return;
    const auto callback = g_renderRequestCallback.load(std::memory_order_acquire);
    if (callback) callback();
}

static void markCameraStateChanged() noexcept {
    g_cameraStateRevision.fetch_add(1, std::memory_order_release);
}

void SimpleObserver::onCameraWillChange(CameraChangeMode mode) {
    BridgeSessionActivation activation(owner);
    g_stationaryRepaintBudget.reset();
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
    g_stationaryRepaintBudget.reset();
    g_styleLoaded.store(false, std::memory_order_relaxed);
}
void SimpleObserver::onDidFinishLoadingStyle() {
    BridgeSessionActivation activation(owner);
    bridge_refreshRepaintBudget();
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

void bridge_resetRepaintBudget() {
    g_stationaryRepaintBudget.reset();
}

void bridge_refreshRepaintBudget() {
    using Milliseconds = StationaryRepaintBudget::Milliseconds;
    const double defaultDuration = Milliseconds(mln::util::DEFAULT_TRANSITION_DURATION).count();
    double longest = defaultDuration;
    if (g_map) {
        const auto& style = g_map->getStyle();
        const auto options = style.getTransitionOptions();
        const double duration = options.duration ? Milliseconds(*options.duration).count() : defaultDuration;
        const double delay = options.delay ? Milliseconds(*options.delay).count() : 0;
        longest = std::max(longest, duration + delay);
        const auto number = [](const mln::Value& value) {
            double result = std::numeric_limits<double>::infinity();
            if (const auto* v = value.getDouble()) result = *v;
            else if (const auto* v = value.getInt()) result = static_cast<double>(*v);
            else if (const auto* v = value.getUint()) result = static_cast<double>(*v);
            return std::isfinite(result) && result >= 0
                ? result : std::numeric_limits<double>::infinity();
        };
        for (const auto* layer : style.getLayers()) {
            const auto serialized = layer->serialize();
            const auto* object = serialized.getObject();
            if (!object) {
                longest = std::numeric_limits<double>::infinity();
                break;
            }
            const auto paintEntry = object->find("paint");
            if (paintEntry == object->end()) continue;
            const auto* paint = paintEntry->second.getObject();
            if (!paint) {
                longest = std::numeric_limits<double>::infinity();
                break;
            }
            for (const auto& [name, value] : *paint) {
                if (name == "raster-fade-duration") {
                    longest = std::max(longest, number(value));
                } else if (name.ends_with("-transition")) {
                    const auto* transition = value.getObject();
                    if (!transition) {
                        longest = std::numeric_limits<double>::infinity();
                        break;
                    }
                    const auto durationEntry = transition->find("duration");
                    const auto delayEntry = transition->find("delay");
                    const double propertyDuration = durationEntry == transition->end()
                        ? duration : number(durationEntry->second);
                    const double propertyDelay = delayEntry == transition->end()
                        ? delay : number(delayEntry->second);
                    longest = std::max(longest, propertyDuration + propertyDelay);
                }
            }
        }
        if (const auto* light = style.getLight()) {
            for (const auto& transition : {
                     light->getAnchorTransition(), light->getColorTransition(),
                     light->getIntensityTransition(), light->getPositionTransition()}) {
                const double lightDuration = transition.duration
                    ? Milliseconds(*transition.duration).count() : duration;
                const double lightDelay = transition.delay
                    ? Milliseconds(*transition.delay).count() : delay;
                longest = std::max(longest, lightDuration + lightDelay);
            }
        }
    }
    g_stationaryRepaintBudget.setMinimumDuration(Milliseconds(longest));
}

void SimpleObserver::onSourceChanged(mln::style::Source&) {
    BridgeSessionActivation activation(owner);
    bridge_resetRepaintBudget();
}

void SimpleObserver::onTileAction(
    mln::TileOperation operation,
    [[maybe_unused]] const mln::OverscaledTileID& id,
    [[maybe_unused]] const std::string& source) {
#if defined(__ANDROID__) && defined(MAPLIBRE_ANDROID_TILE_DIAGNOSTICS) && MAPLIBRE_ANDROID_TILE_DIAGNOSTICS
    traceTileAction(tileTraceSerial, tileTraceEvent.fetch_add(1, std::memory_order_relaxed) + 1,
                    operation, id, source);
#endif
    if (operation != mln::TileOperation::EndParse) return;
    BridgeSessionActivation activation(owner);
    bridge_resetRepaintBudget();
}

void SimpleObserver::onGlyphsLoaded(const mln::FontStack&, const mln::GlyphRange&) {
    BridgeSessionActivation activation(owner);
    bridge_resetRepaintBudget();
}

void SimpleObserver::onSpriteLoaded(const std::optional<mln::style::Sprite>&) {
    BridgeSessionActivation activation(owner);
    bridge_resetRepaintBudget();
}

void BridgeFrontend::update(
    std::shared_ptr<mln::UpdateParameters> parameters) {
    BridgeSessionActivation activation(owner);
    mln::HeadlessFrontend::update(std::move(parameters));
    g_frontendCameraRevision =
        g_cameraStateRevision.load(std::memory_order_acquire);
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
    g_snapshotPayload.clear();
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
    g_snapshotCamera.reset();
    g_mapTransformMetadata.valid = 0u;
    g_snapshotTransform.reset();
    g_snapshotVisibleRegion.reset();
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
    g_cameraConstrainMode.reset();
    g_cameraStateRevision.store(0, std::memory_order_relaxed);
    g_frontendCameraRevision = 0;
    g_cameraCommandGeneration.store(0, std::memory_order_relaxed);
    g_cameraPresentedRevision.store(0, std::memory_order_relaxed);
    g_frameNeedsRepaint.store(false, std::memory_order_relaxed);
    g_frameModeFull.store(false, std::memory_order_relaxed);
    g_renderDirty.store(false, std::memory_order_relaxed);
    {
        std::lock_guard<std::mutex> lock(g_renderPauseMutex);
        ++g_renderPauseRequestGeneration;
        g_renderPauseCameraCancellation.reset();
        g_renderingPaused.store(false, std::memory_order_relaxed);
        g_renderTaskEpoch.fetch_add(1, std::memory_order_release);
    }
    g_stationaryRepaintBudget.reset();
    g_snapshotWakePending.store(false, std::memory_order_relaxed);
    g_sessionActive.store(false, std::memory_order_release);
}

void bridge_handleOwnerThreadExit() noexcept {
    // Called before the owner RunLoop (and therefore Scheduler TLS) is
    // destroyed. resetBridgeSession is intentionally idempotent because the
    // normal destroy path has already performed the same teardown.
    g_sessionActive.store(false, std::memory_order_release);
#if MLN_RENDER_BACKEND_COMMAND_EXPORT
    {
        // DrawCommands are shallow views over renderer-owned buffers. A fatal
        // RunLoop exit must still honor an already acquired generation. The
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
    {
        // The style API first atomically discards an unacquired generation.
        // Keep queued camera/resize mutations and the pending render task:
        // a style reload must not silently lose accepted input.
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        if (!g_asyncFrame.acquired) g_asyncFrame.ready = false;
    }
    g_snapshotWakePending.store(false, std::memory_order_release);
    g_snapshot.clear();
    g_snapshotPayload.clear();
    mln::command_export::getFrameData().clear();
    bridge_resetMergeStorage();
    bridge_resetLabels();
    g_snapshotCamera.reset();
    g_mapTransformMetadata.valid = 0u;
    g_snapshotTransform.reset();
    g_snapshotVisibleRegion.reset();
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
            // in-memory SQLite cache. Networking remains backed by the Android
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
