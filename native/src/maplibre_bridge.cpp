// MapLibre bridge: map lifecycle, camera, gestures, and the DrawCommand
// frame FFI. Cross-tile merging and label extraction live in
// bridge_merge.cpp / bridge_labels.cpp.
#include "bridge_state.hpp"
#include "repaint_budget.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_set>
#include <utility>
#include <vector>

#ifdef __APPLE__
#include <CoreFoundation/CoreFoundation.h>
#endif

#include <mbgl/renderer/renderer.hpp>
#include <mbgl/map/map_observer.hpp>
#include <mbgl/map/map_options.hpp>
#include <mbgl/map/transform_state.hpp>
#include <mbgl/storage/resource_options.hpp>
#include <mbgl/util/client_options.hpp>
#include <mbgl/util/constants.hpp>
#include <mbgl/util/run_loop.hpp>
#include <mbgl/style/style.hpp>
#include <mbgl/util/image.hpp>
#include <mbgl/util/mat4.hpp>
#include <mbgl/util/projection.hpp>

using RenderRequestCallback = void (*)();
struct BridgeSession;

class SimpleObserver : public mbgl::MapObserver {
public:
    explicit SimpleObserver(BridgeSession* owner_) : owner(owner_) {}
    void onCameraWillChange(CameraChangeMode mode) override;
    void onCameraIsChanging() override;
    void onCameraDidChange(CameraChangeMode) override;
    void onWillStartLoadingMap() override;
    void onDidFinishLoadingStyle() override;
    void onDidFailLoadingMap(mbgl::MapLoadError, const std::string& message) override;
    void onDidFinishRenderingFrame(const RenderFrameStatus& status) override;
    void onSourceChanged(mbgl::style::Source&) override;
    void onTileAction(mbgl::TileOperation, const mbgl::OverscaledTileID&,
                      const std::string&) override;
    void onGlyphsLoaded(const mbgl::FontStack&, const mbgl::GlyphRange&) override;
    void onSpriteLoaded(const std::optional<mbgl::style::Sprite>&) override;

private:
    BridgeSession* owner;
};

class BridgeFrontend final : public mbgl::HeadlessFrontend {
public:
    template <typename... Args>
    BridgeFrontend(BridgeSession* owner_, Args&&... args)
        : mbgl::HeadlessFrontend(std::forward<Args>(args)...), owner(owner_) {}
    void update(std::shared_ptr<mbgl::UpdateParameters> parameters) override;

private:
    BridgeSession* owner;
};

enum class BridgeSessionState : uint8_t {
    Idle,
    Initializing,
    Active,
    Destroying,
};

struct DrawableInfo {
    char name[64];
};

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
struct FrameMetadata {
    const void* commands;
    int32_t commandCount;
    int32_t commandStride;
    float clearColor[4];
    uint32_t hasClearColor;
};
struct MapTransformMetadata {
    float viewProjectionMatrix[16];
    double worldSize;
    double originX;
    double originY;
    double zoom;
    uint32_t valid;
};

#ifdef __ANDROID__
// A DrawCommand is a shallow view over renderer-owned buffers. Only one
// published frame may be visible to Dart, and the owner thread may not render
// again until Dart releases that generation.
struct AsyncFrameState {
    std::mutex mutex;
    std::condition_variable leaseReleased;
    uint64_t generation = 0;
    bool ready = false;
    bool acquired = false;
    bool renderTaskQueued = false;
    bool rendering = false;
    bool renderDeferred = false;
    bool syncFrameOpen = false;
    std::deque<std::function<void()>> deferredMutations;
};
#endif
#endif

struct BridgeSession {
    BridgeSession() : observer(this) { drawableSummary[0] = '\0'; }

    std::unique_ptr<mbgl::HeadlessFrontend> frontend;
    std::unique_ptr<mbgl::Map> map;
    SimpleObserver observer;
    std::mutex lifecycleMutex;
    BridgeSessionState state = BridgeSessionState::Idle;
    std::atomic<bool> active{false};
    std::atomic<bool> mapIdle{false};
    std::atomic<bool> styleLoaded{false};
    std::atomic<bool> cameraMoving{false};
    std::atomic<uint64_t> pendingCameraMutations{0};
    std::atomic<uint64_t> cameraStateRevision{0};
    std::atomic<uint64_t> cameraPresentedRevision{0};
    std::atomic<bool> frameNeedsRepaint{false};
    std::atomic<bool> frameModeFull{false};
    std::atomic<bool> renderDirty{false};
    StationaryRepaintBudget stationaryRepaintBudget;
    std::atomic<bool> snapshotWakePending{false};
    std::atomic<bool> framePlacementChanged{false};
    std::atomic<RenderRequestCallback> renderRequestCallback{nullptr};
    std::mutex renderRequestCallbackMutex;
    int drawableCount = 0;
    std::vector<DrawableInfo> drawables;
    char drawableSummary[16384]{};
#if MLN_RENDER_BACKEND_COMMAND_EXPORT
    bool labelCollectionEnabled = false;
    std::vector<mbgl::command_export::DrawCommand> snapshot;
    std::optional<std::array<float, 4>> snapshotClearColor;
    FrameMetadata frameMetadata{};
    MapTransformMetadata mapTransformMetadata{};
#ifdef __ANDROID__
    std::optional<mbgl::TransformState> snapshotTransform;
    std::optional<mbgl::CameraOptions> snapshotCamera;
    std::optional<mbgl::LatLngBounds> snapshotVisibleRegion;
    AsyncFrameState asyncFrame;
#endif
#endif
};

static BridgeSession& legacySession() {
    static BridgeSession session;
    return session;
}
static std::unique_ptr<mbgl::util::RunLoop> g_runtimeRunLoop;
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
std::unique_ptr<mbgl::HeadlessFrontend>& bridge_frontendStorage() {
    return static_cast<BridgeSession*>(bridge_currentSession())->frontend;
}
std::unique_ptr<mbgl::Map>& bridge_mapStorage() {
    return static_cast<BridgeSession*>(bridge_currentSession())->map;
}
std::unique_ptr<mbgl::util::RunLoop>& bridge_runLoopStorage() {
    return g_runtimeRunLoop;
}
#if MLN_RENDER_BACKEND_COMMAND_EXPORT
std::vector<mbgl::command_export::DrawCommand>& bridge_snapshotStorage() {
    return static_cast<BridgeSession*>(bridge_currentSession())->snapshot;
}
bool& bridge_labelCollectionEnabledStorage() {
    return static_cast<BridgeSession*>(bridge_currentSession())->labelCollectionEnabled;
}
#endif

#define SESSION (*static_cast<BridgeSession*>(bridge_currentSession()))
#define g_observer SESSION.observer
#define g_sessionLifecycleMutex SESSION.lifecycleMutex
#define g_sessionState SESSION.state
#define g_sessionActive SESSION.active
#define g_mapIdle SESSION.mapIdle
#define g_styleLoaded SESSION.styleLoaded
#define g_cameraMoving SESSION.cameraMoving
#define g_pendingCameraMutations SESSION.pendingCameraMutations
#define g_cameraStateRevision SESSION.cameraStateRevision
#define g_cameraPresentedRevision SESSION.cameraPresentedRevision
#define g_frameNeedsRepaint SESSION.frameNeedsRepaint
#define g_frameModeFull SESSION.frameModeFull
#define g_renderDirty SESSION.renderDirty
#define g_stationaryRepaintBudget SESSION.stationaryRepaintBudget
#define g_snapshotWakePending SESSION.snapshotWakePending
#define g_framePlacementChanged SESSION.framePlacementChanged
#define g_renderRequestCallback SESSION.renderRequestCallback
#define g_renderRequestCallbackMutex SESSION.renderRequestCallbackMutex
#define g_drawable_count SESSION.drawableCount
#define g_drawables SESSION.drawables
#define g_drawable_summary SESSION.drawableSummary
#if MLN_RENDER_BACKEND_COMMAND_EXPORT
#define g_snapshotClearColor SESSION.snapshotClearColor
#define g_frameMetadata SESSION.frameMetadata
#define g_mapTransformMetadata SESSION.mapTransformMetadata
#ifdef __ANDROID__
#define g_snapshotTransform SESSION.snapshotTransform
#define g_snapshotCamera SESSION.snapshotCamera
#define g_snapshotVisibleRegion SESSION.snapshotVisibleRegion
#define g_asyncFrame SESSION.asyncFrame
#endif
#endif

static void notifyRenderRequested() noexcept {
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
    g_styleLoaded.store(true, std::memory_order_relaxed);
    printf("[MapLibre] Style loaded\n");
    fflush(stdout);
}
void SimpleObserver::onDidFailLoadingMap(
    mbgl::MapLoadError,
    const std::string& message) {
    BridgeSessionActivation activation(owner);
    g_styleLoaded.store(false, std::memory_order_relaxed);
    printf("[MapLibre] Style load failed: %s\n", message.c_str());
    fflush(stdout);
}
void SimpleObserver::onDidFinishRenderingFrame(const RenderFrameStatus& status) {
    BridgeSessionActivation activation(owner);
    const bool modeFull =
        status.mode == mbgl::MapObserver::RenderMode::Full;
    g_frameModeFull.store(modeFull, std::memory_order_relaxed);
    g_mapIdle = modeFull && !status.needsRepaint;
    g_frameNeedsRepaint.store(status.needsRepaint, std::memory_order_relaxed);
    g_framePlacementChanged.store(status.placementChanged, std::memory_order_relaxed);
}

void bridge_resetRepaintBudget() {
    g_stationaryRepaintBudget.reset();
}

void SimpleObserver::onSourceChanged(mbgl::style::Source&) {
    BridgeSessionActivation activation(owner);
    bridge_resetRepaintBudget();
}

void SimpleObserver::onTileAction(
    mbgl::TileOperation operation, const mbgl::OverscaledTileID&, const std::string&) {
    if (operation != mbgl::TileOperation::EndParse) return;
    BridgeSessionActivation activation(owner);
    bridge_resetRepaintBudget();
}

void SimpleObserver::onGlyphsLoaded(const mbgl::FontStack&, const mbgl::GlyphRange&) {
    BridgeSessionActivation activation(owner);
    bridge_resetRepaintBudget();
}

void SimpleObserver::onSpriteLoaded(const std::optional<mbgl::style::Sprite>&) {
    BridgeSessionActivation activation(owner);
    bridge_resetRepaintBudget();
}

void BridgeFrontend::update(
    std::shared_ptr<mbgl::UpdateParameters> parameters) {
    BridgeSessionActivation activation(owner);
    mbgl::HeadlessFrontend::update(std::move(parameters));
    const bool wasDirty =
        g_renderDirty.exchange(true, std::memory_order_acq_rel);
    if (!wasDirty) notifyRenderRequested();
}

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
static void resetAsyncFrameState() {
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

static void resetBridgeSession() {
#if MLN_RENDER_BACKEND_COMMAND_EXPORT
    resetAsyncFrameState();
    // DrawCommand contains pointers into renderer-owned and merged storage.
    // Make every exported view empty before destroying either owner.
    g_snapshot.clear();
    mbgl::command_export::getFrameData().clear();
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
    mbgl::command_export::setCurrentLayerIndex(0);
    bridge_releaseMergeSession(bridge_currentSession());
    bridge_releaseLabelSession(bridge_currentSession());
#endif
    bridge_releaseStyleSession(bridge_currentSession());

    g_drawable_count = 0;
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
    g_stationaryRepaintBudget.reset();
    g_snapshotWakePending.store(false, std::memory_order_relaxed);
    g_framePlacementChanged.store(false, std::memory_order_relaxed);
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

static mbgl::AnimationOptions cameraAnimationOptions(int durationMs, int easing) {
    mbgl::AnimationOptions animation;
    animation.duration = std::chrono::milliseconds(std::max(0, durationMs));
    switch (easing) {
        case 0:
            animation.easing.emplace(0.0, 0.0, 1.0, 1.0);
            break;
        case 1:
            animation.easing.emplace(0.42, 0.0, 0.58, 1.0);
            break;
        case 2:
            animation.easing.emplace(0.0, 0.0, 0.58, 1.0);
            break;
        case 3:
            animation.easing.emplace(0.4, 0.0, 1.0, 1.0);
            break;
        default:
            break;
    }
    return animation;
}

void bridge_markStyleLoading() {
    g_mapIdle.store(false, std::memory_order_relaxed);
    g_styleLoaded.store(false, std::memory_order_relaxed);
    g_framePlacementChanged.store(false, std::memory_order_relaxed);
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
    mbgl::command_export::getFrameData().clear();
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

bool bridge_getPublishedCamera(mbgl::CameraOptions& camera) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    if ((!g_asyncFrame.ready && !g_asyncFrame.acquired) ||
        !g_snapshotCamera) {
        return false;
    }
    camera = *g_snapshotCamera;
    return true;
#else
    (void)camera;
    return false;
#endif
}

bool bridge_projectPublishedCoordinates(
    const double* latitudes,
    std::size_t latitudeStride,
    const double* longitudes,
    std::size_t longitudeStride,
    float* outX,
    float* outY,
    int count) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    if (!latitudes || !longitudes || !outX || !outY || count <= 0) {
        return false;
    }
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    if ((!g_asyncFrame.ready && !g_asyncFrame.acquired) ||
        !g_snapshotTransform) {
        return false;
    }
    const auto* latitudeBytes =
        reinterpret_cast<const uint8_t*>(latitudes);
    const auto* longitudeBytes =
        reinterpret_cast<const uint8_t*>(longitudes);
    for (int index = 0; index < count; ++index) {
        const auto latitude = *reinterpret_cast<const double*>(
            latitudeBytes + static_cast<std::size_t>(index) * latitudeStride);
        const auto longitude = *reinterpret_cast<const double*>(
            longitudeBytes + static_cast<std::size_t>(index) * longitudeStride);
        auto projectedLatLng =
            mbgl::LatLng{latitude, longitude}.wrapped();
        projectedLatLng.unwrapForShortestPath(
            g_snapshotTransform->getLatLng(mbgl::LatLng::Wrapped));
        const auto screen =
            g_snapshotTransform->latLngToScreenCoordinate(
                projectedLatLng);
        outX[index] = static_cast<float>(screen.x);
        outY[index] = static_cast<float>(
            g_snapshotTransform->getSize().height - screen.y);
    }
    return true;
#else
    (void)latitudes;
    (void)latitudeStride;
    (void)longitudes;
    (void)longitudeStride;
    (void)outX;
    (void)outY;
    (void)count;
    return false;
#endif
}

bool bridge_projectPublishedWrappedCoordinates(
    const double* latitudes,
    const double* longitudes,
    const int32_t* tileWraps,
    float* outX,
    float* outY,
    int count) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    if (!latitudes || !longitudes || !tileWraps || !outX || !outY ||
        count <= 0) {
        return false;
    }
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    if ((!g_asyncFrame.ready && !g_asyncFrame.acquired) ||
        !g_snapshotTransform) {
        return false;
    }
    for (int index = 0; index < count; ++index) {
        const mbgl::LatLng coordinate{
            latitudes[index],
            longitudes[index] +
                static_cast<double>(tileWraps[index]) *
                    mbgl::util::DEGREES_MAX};
        const auto screen =
            g_snapshotTransform->latLngToScreenCoordinate(coordinate);
        outX[index] = static_cast<float>(screen.x);
        outY[index] = static_cast<float>(
            g_snapshotTransform->getSize().height - screen.y);
    }
    return true;
#else
    (void)latitudes;
    (void)longitudes;
    (void)tileWraps;
    (void)outX;
    (void)outY;
    (void)count;
    return false;
#endif
}

bool bridge_unprojectPublishedCoordinate(
    double x,
    double y,
    double& latitude,
    double& longitude) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    if ((!g_asyncFrame.ready && !g_asyncFrame.acquired) ||
        !g_snapshotTransform) {
        return false;
    }
    const auto latLng = g_snapshotTransform->screenCoordinateToLatLng(
        mbgl::ScreenCoordinate{
            x,
            g_snapshotTransform->getSize().height - y},
        mbgl::LatLng::Wrapped);
    latitude = latLng.latitude();
    longitude = latLng.longitude();
    return true;
#else
    (void)x;
    (void)y;
    (void)latitude;
    (void)longitude;
    return false;
#endif
}

bool bridge_getPublishedVisibleRegion(
    double& south,
    double& west,
    double& north,
    double& east) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    if ((!g_asyncFrame.ready && !g_asyncFrame.acquired) ||
        !g_snapshotVisibleRegion || !g_snapshotVisibleRegion->valid()) {
        return false;
    }
    south = g_snapshotVisibleRegion->south();
    west = g_snapshotVisibleRegion->west();
    north = g_snapshotVisibleRegion->north();
    east = g_snapshotVisibleRegion->east();
    return true;
#else
    (void)south;
    (void)west;
    (void)north;
    (void)east;
    return false;
#endif
}

static void discardUnacquiredFrameLocked() {
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

template <typename Operation>
static int runCameraOperation(const char* name, Operation&& operation) noexcept {
    try {
        return bridge_runOnOwnerSync([&]() -> int {
            if (!g_map) return 0;
            return operation() ? 1 : 0;
        });
    } catch (const std::exception& error) {
        printf("[MapLibre] %s failed: %s\n", name, error.what());
    } catch (...) {
        printf("[MapLibre] %s failed: unknown exception\n", name);
    }
    fflush(stdout);
    return 0;
}

struct PendingCameraMutation {
    ~PendingCameraMutation() { complete(); }

    void complete() noexcept {
        if (!active.exchange(false, std::memory_order_acq_rel)) return;
        auto pending =
            g_pendingCameraMutations.load(std::memory_order_acquire);
        while (pending != 0 &&
               !g_pendingCameraMutations.compare_exchange_weak(
                   pending,
                   pending - 1,
                   std::memory_order_acq_rel,
                   std::memory_order_acquire)) {
        }
    }

    std::atomic<bool> active{true};
};

using PendingCameraMutationToken =
    std::shared_ptr<PendingCameraMutation>;

static PendingCameraMutationToken beginPendingCameraMutation(
    bool tracked) {
    if (!tracked) return {};
    auto token = std::make_shared<PendingCameraMutation>();
    g_pendingCameraMutations.fetch_add(1, std::memory_order_acq_rel);
    return token;
}

static void completePendingCameraMutation(
    const PendingCameraMutationToken& token) noexcept {
    if (token) token->complete();
}

template <typename Operation>
static int runCameraMutation(
    const char* name,
    Operation&& operation,
    bool tracksCameraFrame = true) noexcept {
#ifdef __ANDROID__
    using StoredOperation = std::decay_t<Operation>;
    auto storedOperation = std::make_shared<StoredOperation>(
        std::forward<Operation>(operation));
    const auto operationName = std::string(name);
    const auto pendingToken =
        beginPendingCameraMutation(tracksCameraFrame);
    const auto performOperation =
        [storedOperation, operationName, pendingToken]() -> bool {
            bool result = false;
            try {
                if (g_map) result = (*storedOperation)();
            } catch (const std::exception& error) {
                std::printf(
                    "[MapLibre] %s failed: %s\n",
                    operationName.c_str(),
                    error.what());
                std::fflush(stdout);
            } catch (...) {
                std::printf(
                    "[MapLibre] %s failed: unknown exception\n",
                    operationName.c_str());
                std::fflush(stdout);
            }
            completePendingCameraMutation(pendingToken);
            return result;
        };
    std::function<void()> deferredTask = [performOperation] {
        (void)performOperation();
    };

    const auto deferIfBlocked =
        [&](const std::function<void()>& task, bool includeQueuedRender) {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        discardUnacquiredFrameLocked();
        if (!g_asyncFrame.acquired &&
            (!includeQueuedRender || !g_asyncFrame.renderTaskQueued) &&
            !g_asyncFrame.rendering && !g_asyncFrame.syncFrameOpen) {
            return false;
        }
        g_mapIdle.store(false, std::memory_order_relaxed);
        g_renderDirty.store(true, std::memory_order_release);
        g_asyncFrame.renderDeferred = true;
        g_asyncFrame.deferredMutations.push_back(task);
        return true;
    };

    if (deferIfBlocked(deferredTask, true)) return 1;
    try {
        const int result = bridge_runOnOwnerSync([&]() -> int {
            // Close the caller-check → owner-execution race. A render may
            // publish while this task is waiting in the owner queue.
            if (deferIfBlocked(deferredTask, false)) return 2;
            return performOperation() ? 1 : 0;
        });
        return result != 0 ? 1 : 0;
    } catch (const std::exception& error) {
        std::printf("[MapLibre] %s failed: %s\n", name, error.what());
    } catch (...) {
        std::printf("[MapLibre] %s failed: unknown exception\n", name);
    }
    completePendingCameraMutation(pendingToken);
    std::fflush(stdout);
    return 0;
#else
    (void)tracksCameraFrame;
    return runCameraOperation(name, std::forward<Operation>(operation));
#endif
}

template <typename Operation>
static void postGestureOperation(const char* name, Operation&& operation) noexcept {
#ifdef __ANDROID__
    g_mapIdle.store(false, std::memory_order_relaxed);
    g_renderDirty.store(true, std::memory_order_release);
    const auto pendingToken = beginPendingCameraMutation(true);
    std::function<void()> task =
        [operation = std::forward<Operation>(operation),
         operationName = std::string(name),
         pendingToken]() mutable {
            try {
                if (g_map) operation();
            } catch (const std::exception& error) {
                std::printf(
                    "[MapLibre] %s failed: %s\n",
                    operationName.c_str(),
                    error.what());
                std::fflush(stdout);
            } catch (...) {
                std::printf(
                    "[MapLibre] %s failed: unknown exception\n",
                    operationName.c_str());
                std::fflush(stdout);
            }
            completePendingCameraMutation(pendingToken);
        };

    {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        discardUnacquiredFrameLocked();
        if (g_asyncFrame.acquired || g_asyncFrame.renderTaskQueued ||
            g_asyncFrame.rendering ||
            g_asyncFrame.syncFrameOpen) {
            g_asyncFrame.deferredMutations.push_back(std::move(task));
            g_asyncFrame.renderDeferred = true;
            return;
        }
    }

    const bool posted = bridge_runOnOwnerAsync(
        [task = std::move(task)]() mutable {
            {
                std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
                discardUnacquiredFrameLocked();
                if (g_asyncFrame.acquired ||
                    g_asyncFrame.rendering || g_asyncFrame.syncFrameOpen) {
                    g_asyncFrame.deferredMutations.push_back(std::move(task));
                    g_asyncFrame.renderDeferred = true;
                    return;
                }
            }
            task();
        });
    if (!posted) {
        completePendingCameraMutation(pendingToken);
        std::printf("[MapLibre] %s rejected: owner thread unavailable\n", name);
        std::fflush(stdout);
    }
#else
    try {
        bridge_runOnOwnerSync(
            [operation = std::forward<Operation>(operation)]() mutable {
                if (g_map) operation();
            });
    } catch (...) {
    }
#endif
}

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
static void captureMapTransform(const mbgl::TransformState& state) {
    g_mapTransformMetadata.valid = 0u;
    const auto size = state.getSize();
    if (size.isEmpty()) return;

    mbgl::mat4 matrix;
    // Match MapLibre's near-clipped projection for fill extrusion depth.
    const auto nearZ =
        static_cast<uint16_t>(0.1 * state.getCameraToCenterDistance());
    state.getProjMatrix(matrix, nearZ);

    const double worldSize = mbgl::Projection::worldSize(state.getScale());
    const double originX = 0.5 * worldSize - state.getX();
    const double originY = 0.5 * worldSize - state.getY();
    mbgl::matrix::translate(matrix, matrix, originX, originY, 0.0);
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
static mbgl::LatLngBounds visibleRegionForTransform(
    const mbgl::TransformState& state) {
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
    auto bounds = mbgl::LatLngBounds::hull(northWest, southEast);
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
    mbgl::command_export::getFrameData().clear();
    g_framePlacementChanged.store(false, std::memory_order_relaxed);
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
    const mbgl::TransformState* renderedState = nullptr) {
    auto& fd = mbgl::command_export::getFrameData();
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
    g_framePlacementChanged.exchange(false, std::memory_order_relaxed);
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
        published = endCommandFrameOnOwner(&*renderedState);
        if (g_frameNeedsRepaint.load(std::memory_order_relaxed)) {
            g_renderDirty.store(true, std::memory_order_release);
        }
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

// ── Map lifecycle ────────────────────────────────────────────────────

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
                mbgl::Size{static_cast<uint32_t>(width), static_cast<uint32_t>(height)},
                pixel_ratio,
                mbgl::gfx::HeadlessBackend::SwapBehaviour::NoFlush,
                mbgl::gfx::ContextMode::Unique,
                std::nullopt,
                false
            );

            mbgl::ResourceOptions resourceOptions;
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

            mbgl::ClientOptions clientOptions;

            mbgl::MapOptions mapOptions;
            mapOptions.withSize(mbgl::Size{
                static_cast<uint32_t>(width),
                static_cast<uint32_t>(height)
            });
            mapOptions.withPixelRatio(pixel_ratio);
            mapOptions.withMapMode(mbgl::MapMode::Continuous);

            g_map = std::make_unique<mbgl::Map>(
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

// True when the map is fully rendered and settled (no pending tiles or
// transitions). Dart keeps a repaint loop running until this turns 1.
MAPLIBRE_API int maplibre_is_idle(void) {
    return g_mapIdle ? 1 : 0;
}

MAPLIBRE_API int maplibre_is_style_loaded(void) {
    return g_styleLoaded ? 1 : 0;
}

// Register an isolate-safe wake callback. The callback can be invoked from any
// thread; Dart must marshal the actual render back to the map's owning isolate.
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
        // The shared RunLoop runs continuously; HTTP responses, timers, actor
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
            // Continuous Map mode can enqueue its own follow-up update while
            // rendering. Once the observer reports no animation/repaint work,
            // that update contains no new presentable content. This includes
            // Partial frames waiting on tiles: each arriving tile posts a new
            // owner update and wake. Drop the self-update so Dart does not
            // recompose the identical Flutter GPU texture forever.
            const bool cameraMoving =
                g_cameraMoving.load(std::memory_order_relaxed);
            const bool partialWaitingForData =
                !g_frameModeFull.load(std::memory_order_relaxed) &&
                !cameraMoving;
            const bool needsRepaint =
                g_frameNeedsRepaint.load(std::memory_order_relaxed);
            // Self-updates share one budget. Camera, style, and resource changes
            // reset it so a later transition receives its own rendering window.
            const bool stationaryTransitionExpired =
                g_stationaryRepaintBudget.expired(cameraMoving, needsRepaint);
            if ((!needsRepaint && !cameraMoving) ||
                partialWaitingForData ||
                stationaryTransitionExpired) {
                g_renderDirty.store(false, std::memory_order_release);
                if (partialWaitingForData || stationaryTransitionExpired) {
                    // Missing tile/actor data and camera changes wake/reset
                    // this path. Do not let stale placement/fade state spin
                    // Flutter forever.
                    g_frameNeedsRepaint.store(false, std::memory_order_relaxed);
                }
            }
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
    if (!g_renderDirty.load(std::memory_order_acquire)) {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        // A completion callback runs renderGesture before paint/acquire. The
        // published frame itself is not a reason to render another frame.
        if (g_asyncFrame.ready || g_asyncFrame.acquired ||
            g_asyncFrame.renderTaskQueued || g_asyncFrame.rendering) {
            return 0;
        }
    }
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

MAPLIBRE_API void maplibre_set_camera(double lat, double lon, double zoom) {
    runCameraMutation("set camera", [=] {
        mbgl::CameraOptions camera;
        camera.center = mbgl::LatLng{lat, lon};
        camera.zoom = zoom;
        g_map->jumpTo(camera);
        return true;
    });
}

MAPLIBRE_API void maplibre_set_camera_full(
    double lat,
    double lon,
    double zoom,
    double bearing,
    double pitch) {
    runCameraMutation("set camera", [=] {
        mbgl::CameraOptions camera;
        camera.center = mbgl::LatLng{lat, lon};
        camera.zoom = zoom;
        camera.bearing = bearing;
        camera.pitch = pitch;
        g_map->jumpTo(camera);
        return true;
    });
}

MAPLIBRE_API void maplibre_set_max_pitch(double pitch) {
    runCameraMutation("set max pitch", [=] {
        mbgl::BoundOptions options;
        options.maxPitch = pitch;
        g_map->setBounds(options);
        return true;
    }, false);
}

MAPLIBRE_API void maplibre_set_min_pitch(double pitch) {
    runCameraMutation("set min pitch", [=] {
        mbgl::BoundOptions options;
        options.minPitch = pitch;
        g_map->setBounds(options);
        return true;
    }, false);
}

MAPLIBRE_API int maplibre_camera_ease_to(
    double lat,
    double lon,
    double zoom,
    double bearing,
    double pitch,
    int duration_ms,
    int easing) {
    return runCameraMutation("camera ease", [=] {
        mbgl::CameraOptions camera;
        camera.center = mbgl::LatLng{lat, lon};
        camera.zoom = zoom;
        camera.bearing = bearing;
        camera.pitch = pitch;
        g_map->easeTo(camera, cameraAnimationOptions(duration_ms, easing));
        return true;
    });
}

MAPLIBRE_API int maplibre_camera_fly_to(
    double lat,
    double lon,
    double zoom,
    double bearing,
    double pitch,
    int duration_ms,
    int easing) {
    return runCameraMutation("camera flight", [=] {
        mbgl::CameraOptions camera;
        camera.center = mbgl::LatLng{lat, lon};
        camera.zoom = zoom;
        camera.bearing = bearing;
        camera.pitch = pitch;
        g_map->flyTo(camera, cameraAnimationOptions(duration_ms, easing));
        return true;
    });
}

MAPLIBRE_API int maplibre_camera_move_by_animated(
    double dx,
    double dy,
    int duration_ms,
    int easing) {
    return runCameraMutation("animated camera move", [=] {
        g_map->moveBy(
            mbgl::ScreenCoordinate{dx, dy},
            cameraAnimationOptions(duration_ms, easing));
        return true;
    });
}

MAPLIBRE_API int maplibre_camera_scale_by_animated(
    double scale,
    int has_anchor,
    double x,
    double y,
    int duration_ms,
    int easing) {
    return runCameraMutation("animated camera scale", [=] {
        const std::optional<mbgl::ScreenCoordinate> anchor = has_anchor
            ? std::optional<mbgl::ScreenCoordinate>{mbgl::ScreenCoordinate{x, y}}
            : std::nullopt;
        g_map->scaleBy(
            scale,
            anchor,
            cameraAnimationOptions(duration_ms, easing));
        return true;
    });
}

MAPLIBRE_API int maplibre_camera_fit_bounds(
    double south,
    double west,
    double north,
    double east,
    double left,
    double top,
    double right,
    double bottom,
    int duration_ms,
    int easing,
    int fly_to) {
    if (south > north) return 0;
    if (east < west) east += 360.0;
    return runCameraMutation("camera bounds fit", [=] {
        const auto bounds = mbgl::LatLngBounds::hull(
            mbgl::LatLng{south, west},
            mbgl::LatLng{north, east});
        const mbgl::EdgeInsets padding{top, left, bottom, right};
        auto camera = g_map->cameraForLatLngBounds(bounds, padding, 0.0, 0.0);
        if (!camera.center || !camera.zoom) return false;
        if (duration_ms > 0 && fly_to) {
            g_map->flyTo(camera, cameraAnimationOptions(duration_ms, easing));
        } else if (duration_ms > 0) {
            g_map->easeTo(camera, cameraAnimationOptions(duration_ms, easing));
        } else {
            g_map->jumpTo(camera);
        }
        return true;
    });
}

MAPLIBRE_API int maplibre_is_camera_moving(void) {
#ifdef __ANDROID__
    const bool awaitingPresentedCamera =
        g_pendingCameraMutations.load(std::memory_order_acquire) != 0 ||
        g_cameraStateRevision.load(std::memory_order_acquire) !=
            g_cameraPresentedRevision.load(std::memory_order_acquire);
#else
    const bool awaitingPresentedCamera = false;
#endif
    return (g_cameraMoving.load(std::memory_order_relaxed) ||
            awaitingPresentedCamera)
               ? 1
               : 0;
}

MAPLIBRE_API int maplibre_cancel_camera_transitions(void) {
    const auto result = runCameraMutation("cancel camera transitions", [] {
        g_map->cancelTransitions();
        return true;
    });
    if (result) g_cameraMoving.store(false, std::memory_order_relaxed);
    return result;
}

MAPLIBRE_API int maplibre_set_content_insets(
    double top,
    double left,
    double bottom,
    double right,
    int animated) {
    return runCameraMutation("content insets", [=] {
        mbgl::CameraOptions camera;
        camera.padding = mbgl::EdgeInsets{top, left, bottom, right};
        if (animated) {
            g_map->easeTo(camera, cameraAnimationOptions(300, -1));
        } else {
            g_map->jumpTo(camera);
        }
        return true;
    });
}

MAPLIBRE_API int maplibre_set_content_insets_with_duration(
    double top,
    double left,
    double bottom,
    double right,
    int animated,
    int duration_ms) {
    return runCameraMutation("content insets", [=] {
        mbgl::CameraOptions camera;
        camera.padding = mbgl::EdgeInsets{top, left, bottom, right};
        if (animated) {
            g_map->easeTo(camera, cameraAnimationOptions(duration_ms, -1));
        } else {
            g_map->jumpTo(camera);
        }
        return true;
    });
}

MAPLIBRE_API void maplibre_set_bounds(
    int has_bounds,
    double south,
    double west,
    double north,
    double east,
    int has_min_zoom,
    double min_zoom,
    int has_max_zoom,
    double max_zoom) {
    runCameraMutation("set bounds", [=] {
        mbgl::BoundOptions options;
        auto adjustedEast = east;
        if (has_bounds) {
            // Preserve antimeridian-crossing bounds as an unwrapped interval.
            if (adjustedEast < west) adjustedEast += 360.0;
            options.bounds = mbgl::LatLngBounds::hull(
                mbgl::LatLng{south, west},
                mbgl::LatLng{north, adjustedEast});
            g_map->setConstrainMode(mbgl::ConstrainMode::Screen);
        } else {
            options.bounds = mbgl::LatLngBounds{};
            g_map->setConstrainMode(mbgl::ConstrainMode::HeightOnly);
        }
        options.minZoom = has_min_zoom ? min_zoom : mbgl::util::MIN_ZOOM;
        options.maxZoom = has_max_zoom ? max_zoom : mbgl::util::MAX_ZOOM;
        g_map->setBounds(options);
        return true;
    }, false);
}

// ── Camera query ─────────────────────────────────────────────────────

MAPLIBRE_API int maplibre_get_camera(double* output) {
    if (!output) return 0;
    mbgl::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        output[0] = publishedCamera.center
            ? publishedCamera.center->latitude()
            : 0.0;
        output[1] = publishedCamera.center
            ? publishedCamera.center->longitude()
            : 0.0;
        output[2] = publishedCamera.zoom.value_or(0.0);
        output[3] = publishedCamera.bearing.value_or(0.0);
        output[4] = publishedCamera.pitch.value_or(0.0);
        return 1;
    }
    return runCameraOperation("get camera", [&] {
        const auto camera = g_map->getCameraOptions();
        output[0] = camera.center ? camera.center->latitude() : 0.0;
        output[1] = camera.center ? camera.center->longitude() : 0.0;
        output[2] = camera.zoom.value_or(0.0);
        output[3] = camera.bearing.value_or(0.0);
        output[4] = camera.pitch.value_or(0.0);
        return true;
    });
}

MAPLIBRE_API double maplibre_get_camera_lat(void) {
    mbgl::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return publishedCamera.center
            ? publishedCamera.center->latitude()
            : 0.0;
    }
    try {
        return bridge_runOnOwnerSync([] {
            if (!g_map) return 0.0;
            const auto camera = g_map->getCameraOptions();
            return camera.center ? camera.center->latitude() : 0.0;
        });
    } catch (...) {
        return 0.0;
    }
}

MAPLIBRE_API double maplibre_get_camera_lon(void) {
    mbgl::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return publishedCamera.center
            ? publishedCamera.center->longitude()
            : 0.0;
    }
    try {
        return bridge_runOnOwnerSync([] {
            if (!g_map) return 0.0;
            const auto camera = g_map->getCameraOptions();
            return camera.center ? camera.center->longitude() : 0.0;
        });
    } catch (...) {
        return 0.0;
    }
}

MAPLIBRE_API double maplibre_get_camera_zoom(void) {
    mbgl::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return publishedCamera.zoom.value_or(0.0);
    }
    try {
        return bridge_runOnOwnerSync([] {
            if (!g_map) return 0.0;
            return g_map->getCameraOptions().zoom.value_or(0.0);
        });
    } catch (...) {
        return 0.0;
    }
}

MAPLIBRE_API double maplibre_get_camera_bearing(void) {
    mbgl::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return publishedCamera.bearing.value_or(0.0);
    }
    try {
        return bridge_runOnOwnerSync([] {
            if (!g_map) return 0.0;
            return g_map->getCameraOptions().bearing.value_or(0.0);
        });
    } catch (...) {
        return 0.0;
    }
}

MAPLIBRE_API double maplibre_get_camera_pitch(void) {
    mbgl::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return publishedCamera.pitch.value_or(0.0);
    }
    try {
        return bridge_runOnOwnerSync([] {
            if (!g_map) return 0.0;
            return g_map->getCameraOptions().pitch.value_or(0.0);
        });
    } catch (...) {
        return 0.0;
    }
}

MAPLIBRE_API int maplibre_get_visible_region(
    double* out_south,
    double* out_west,
    double* out_north,
    double* out_east) {
    if (!out_south || !out_west || !out_north || !out_east) return 0;
    if (bridge_getPublishedVisibleRegion(
            *out_south,
            *out_west,
            *out_north,
            *out_east)) {
        return 1;
    }
    return runCameraOperation("visible region query", [&] {
        const auto bounds = g_map->latLngBoundsForCameraUnwrapped(g_map->getCameraOptions());
        if (!bounds.valid()) return false;
        *out_south = bounds.south();
        *out_west = bounds.west();
        *out_north = bounds.north();
        *out_east = bounds.east();
        return true;
    });
}

MAPLIBRE_API double maplibre_get_meters_per_pixel_at_latitude(double latitude) {
    mbgl::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return mbgl::Projection::getMetersPerPixelAtLatitude(
            latitude,
            publishedCamera.zoom.value_or(0.0));
    }
    try {
        return bridge_runOnOwnerSync([=] {
            if (!g_map) return 0.0;
            const auto camera = g_map->getCameraOptions();
            return mbgl::Projection::getMetersPerPixelAtLatitude(
                latitude,
                camera.zoom.value_or(0.0));
        });
    } catch (...) {
        return 0.0;
    }
}

// ── Gesture forwarding ───────────────────────────────────────────────

MAPLIBRE_API void maplibre_move_by(double dx, double dy) {
    postGestureOperation("camera move", [=] {
        g_map->moveBy(mbgl::ScreenCoordinate{dx, dy});
    });
}

MAPLIBRE_API void maplibre_scale_by(double scale, double cx, double cy) {
    postGestureOperation("camera scale", [=] {
        g_map->scaleBy(scale, mbgl::ScreenCoordinate{cx, cy});
    });
}

MAPLIBRE_API void maplibre_rotate_by(double degrees) {
    postGestureOperation("camera rotate", [=] {
        auto camera = g_map->getCameraOptions();
        camera.bearing = camera.bearing.value_or(0.0) + degrees;
        g_map->jumpTo(camera);
    });
}

MAPLIBRE_API void maplibre_pitch_by(double degrees) {
    postGestureOperation("camera pitch", [=] {
        auto camera = g_map->getCameraOptions();
        camera.pitch = camera.pitch.value_or(0.0) + degrees;
        g_map->jumpTo(camera);
    });
}

// ── Coordinate conversion (MapLibre authoritative) ───────────────────

MAPLIBRE_API void maplibre_lat_lon_to_screen(double lat, double lon, double* out_x, double* out_y) {
    if (!out_x || !out_y) return;
    float projectedX = 0.0f;
    float projectedY = 0.0f;
    if (bridge_projectPublishedCoordinates(
            &lat,
            sizeof(double),
            &lon,
            sizeof(double),
            &projectedX,
            &projectedY,
            1)) {
        *out_x = projectedX;
        *out_y = projectedY;
        return;
    }
    runCameraOperation("project coordinate", [&] {
        const auto screen = g_map->pixelForLatLng(mbgl::LatLng{lat, lon});
        *out_x = screen.x;
        *out_y = screen.y;
        return true;
    });
}

MAPLIBRE_API void maplibre_project_coordinates(
    const double* latitudes,
    const double* longitudes,
    float* out_x,
    float* out_y,
    int count) {
    if (!latitudes || !longitudes || !out_x || !out_y || count <= 0) return;
    if (bridge_projectPublishedCoordinates(
            latitudes,
            sizeof(double),
            longitudes,
            sizeof(double),
            out_x,
            out_y,
            count)) {
        return;
    }
    runCameraOperation("project coordinates", [&] {
        for (int index = 0; index < count; index++) {
            const auto screen = g_map->pixelForLatLng(
                mbgl::LatLng{latitudes[index], longitudes[index]});
            out_x[index] = static_cast<float>(screen.x);
            out_y[index] = static_cast<float>(screen.y);
        }
        return true;
    });
}

MAPLIBRE_API void maplibre_project_wrapped_coordinates(
    const double* latitudes,
    const double* longitudes,
    const int32_t* tile_wraps,
    float* out_x,
    float* out_y,
    int count) {
    if (!latitudes || !longitudes || !tile_wraps || !out_x || !out_y ||
        count <= 0) {
        return;
    }
    if (bridge_projectPublishedWrappedCoordinates(
            latitudes,
            longitudes,
            tile_wraps,
            out_x,
            out_y,
            count)) {
        return;
    }
    runCameraOperation("project wrapped coordinates", [&] {
        const auto state = g_map->getTransfromState();
        for (int index = 0; index < count; ++index) {
            const mbgl::LatLng coordinate{
                latitudes[index],
                longitudes[index] +
                    static_cast<double>(tile_wraps[index]) *
                        mbgl::util::DEGREES_MAX};
            const auto screen = state.latLngToScreenCoordinate(coordinate);
            out_x[index] = static_cast<float>(screen.x);
            out_y[index] = static_cast<float>(state.getSize().height - screen.y);
        }
        return true;
    });
}

MAPLIBRE_API void maplibre_screen_to_lat_lon(double x, double y, double* out_lat, double* out_lon) {
    if (!out_lat || !out_lon) return;
    if (bridge_unprojectPublishedCoordinate(
            x,
            y,
            *out_lat,
            *out_lon)) {
        return;
    }
    runCameraOperation("unproject coordinate", [&] {
        const auto latLng =
            g_map->latLngForPixel(mbgl::ScreenCoordinate{x, y});
        *out_lat = latLng.latitude();
        *out_lon = latLng.longitude();
        return true;
    });
}

MAPLIBRE_API void maplibre_set_size(int width, int height) {
    runCameraMutation("set size", [=] {
        if (!g_frontend) return false;
        const mbgl::Size newSize{
            static_cast<uint32_t>(width),
            static_cast<uint32_t>(height)};
        g_frontend->setSize(newSize);
        g_map->setSize(newSize);
        return true;
    }, false);
}

// ── Drawable debug helpers ───────────────────────────────────────────
// Count drawables in the current render tree, grouped by shader name.

MAPLIBRE_API int maplibre_get_drawable_count(void) {
    try {
        return bridge_runOnOwnerSync([] {
            if (!g_frontend) return 0;
            auto* renderer = g_frontend->getRenderer();
            if (!renderer) return 0;

            g_drawables.clear();
            renderer->visitDrawables([](
                                         const std::string& name,
                                         const mbgl::gfx::Drawable::ExportedData&) {
                DrawableInfo info;
                strncpy(info.name, name.c_str(), sizeof(info.name) - 1);
                info.name[sizeof(info.name) - 1] = '\0';
                g_drawables.push_back(info);
            });

            g_drawable_count = static_cast<int>(g_drawables.size());
            return g_drawable_count;
        });
    } catch (...) {
        return 0;
    }
}

MAPLIBRE_API const char* maplibre_get_drawable_name(int index) {
    if (index < 0 || index >= g_drawable_count) return "";
    return g_drawables[index].name;
}

// Get a summary string of drawable types and counts

MAPLIBRE_API const char* maplibre_get_drawable_summary(void) {
    try {
        return bridge_runOnOwnerSync([]() -> const char* {
            if (!g_frontend) return "";
            auto* renderer = g_frontend->getRenderer();
            if (!renderer) return "";

            struct Stats {
                int count = 0;
                size_t verts = 0;
                size_t idxs = 0;
            };
            std::map<std::string, Stats> counts;
            renderer->visitDrawables(
                [&](const std::string& name,
                    const mbgl::gfx::Drawable::ExportedData& data) {
                    auto& stats = counts[name];
                    stats.count++;
                    stats.verts += data.vertexBytes;
                    stats.idxs += data.indexCount;
                });

            std::string result;
            for (const auto& [name, stats] : counts) {
                if (!result.empty()) result += "\n";
                result += name + ": " + std::to_string(stats.count) +
                          " v:" + std::to_string(stats.verts / 1024) + "K" +
                          " i:" + std::to_string(stats.idxs);
            }
            strncpy(
                g_drawable_summary,
                result.c_str(),
                sizeof(g_drawable_summary) - 1);
            g_drawable_summary[sizeof(g_drawable_summary) - 1] = '\0';
            return g_drawable_summary;
        });
    } catch (...) {
        return "";
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
    // Kept for ABI compatibility. Placement snapshots are now published
    // automatically when MapLibre reports placementChanged.
}

MAPLIBRE_API int maplibre_frame_get_command_count(void) {
    return static_cast<int>(g_snapshot.size());
}

MAPLIBRE_API const void* maplibre_frame_get_commands(void) {
    if (g_snapshot.empty()) return nullptr;
    return g_snapshot.data();
}

MAPLIBRE_API int maplibre_frame_get_command_stride(void) {
    return static_cast<int>(sizeof(mbgl::command_export::DrawCommand));
}

MAPLIBRE_API const float* maplibre_frame_get_clear_color(void) {
    return g_snapshotClearColor ? g_snapshotClearColor->data() : nullptr;
}

MAPLIBRE_API const FrameMetadata* maplibre_frame_get_metadata(void) {
    g_frameMetadata.commands = g_snapshot.empty() ? nullptr : g_snapshot.data();
    g_frameMetadata.commandCount = static_cast<int32_t>(g_snapshot.size());
    g_frameMetadata.commandStride =
        static_cast<int32_t>(sizeof(mbgl::command_export::DrawCommand));
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
