// Session storage shared by lifecycle, rendering, and camera operations.
#pragma once

#include "bridge_state.hpp"

#include <array>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>
#include <optional>
#include <string>

#include <mln/map/map_observer.hpp>
#include <mln/map/transform_state.hpp>

using RenderRequestCallback = void (*)();
struct BridgeSession;

class SimpleObserver : public mln::MapObserver {
public:
    explicit SimpleObserver(BridgeSession* owner_) : owner(owner_) {}
    void onCameraWillChange(CameraChangeMode mode) override;
    void onCameraIsChanging() override;
    void onCameraDidChange(CameraChangeMode) override;
    void onWillStartLoadingMap() override;
    void onDidFinishLoadingStyle() override;
    void onDidFailLoadingMap(mln::MapLoadError, const std::string& message) override;
    void onDidFinishRenderingFrame(const RenderFrameStatus& status) override;

private:
    BridgeSession* owner;
};

class BridgeFrontend final : public mln::HeadlessFrontend {
public:
    template <typename... Args>
    BridgeFrontend(BridgeSession* owner_, Args&&... args)
        : mln::HeadlessFrontend(std::forward<Args>(args)...), owner(owner_) {}
    void update(std::shared_ptr<mln::UpdateParameters> parameters) override;

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
    BridgeSession() : observer(this) {}

    std::unique_ptr<mln::HeadlessFrontend> frontend;
    std::unique_ptr<mln::Map> map;
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
    uint32_t stationaryRepaintFrames = 0;
    std::atomic<bool> snapshotWakePending{false};
    std::atomic<RenderRequestCallback> renderRequestCallback{nullptr};
    std::mutex renderRequestCallbackMutex;
    std::vector<DrawableInfo> drawables;
    char drawableSummary[16384]{};
#if MLN_RENDER_BACKEND_COMMAND_EXPORT
    bool labelCollectionEnabled = false;
    std::vector<mln::command_export::DrawCommand> snapshot;
    std::optional<std::array<float, 4>> snapshotClearColor;
    FrameMetadata frameMetadata{};
    MapTransformMetadata mapTransformMetadata{};
#ifdef __ANDROID__
    std::optional<mln::TransformState> snapshotTransform;
    std::optional<mln::CameraOptions> snapshotCamera;
    std::optional<mln::LatLngBounds> snapshotVisibleRegion;
    AsyncFrameState asyncFrame;
#endif
#endif
};

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
#define g_stationaryRepaintFrames SESSION.stationaryRepaintFrames
#define g_snapshotWakePending SESSION.snapshotWakePending
#define g_renderRequestCallback SESSION.renderRequestCallback
#define g_renderRequestCallbackMutex SESSION.renderRequestCallbackMutex
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

// Runs the registered callback while holding its lifetime guard.
void notifyRenderRequested() noexcept;

// Requires the selected session's async frame mutex on Android.
void discardUnacquiredFrameLocked();

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
void resetAsyncFrameState();
#endif
