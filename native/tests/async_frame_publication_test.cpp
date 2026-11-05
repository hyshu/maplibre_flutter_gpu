#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

#define __ANDROID__ 1
#define MLN_RENDER_BACKEND_COMMAND_EXPORT 1
#define MAPLIBRE_API

namespace mln {
struct LatLng {
    double lat = 0;
    double lon = 0;
    double latitude() const { return lat; }
    double longitude() const { return lon; }
};
struct CameraOptions {
    std::optional<LatLng> center;
    std::optional<double> zoom;
    std::optional<double> bearing;
    std::optional<double> pitch;
};
struct UnitBezier {
    UnitBezier(double, double, double, double) {}
};
struct AnimationOptions {
    std::optional<std::chrono::milliseconds> duration;
    std::optional<UnitBezier> easing;
};
}

static struct {
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
} g_asyncFrame;
static std::atomic<bool> g_sessionActive{true};
static std::atomic<bool> g_renderingPaused{false};
static std::atomic<bool> g_renderDirty{true};
static std::atomic<bool> g_snapshotWakePending{false};
static std::atomic<bool> g_mapIdle{false};
static std::atomic<bool> g_cameraMoving{false};
static std::atomic<uint64_t> g_renderTaskEpoch{0};
static std::atomic<uint64_t> g_cameraStateRevision{0};
static uint64_t g_frontendCameraRevision = 0;
static std::atomic<uint64_t> g_cameraPresentedRevision{0};
static std::atomic<uint64_t> g_cameraCommandGeneration{0};
static std::atomic<uint64_t> g_pendingCameraMutations{0};
static std::optional<mln::CameraOptions> g_snapshotCamera;
static std::deque<std::function<void()>> ownerQueue;
static bool onOwnerThread = false;
static bool acceptsTasks = true;
static bool g_run_loop = true;
static int renderedFrames = 0;
static int publishedFrames = 0;
static int wakes = 0;
static bool failRender = false;
static std::function<void()> duringRender;
static std::vector<int> geometry;
static std::vector<int> mutationOrder;

static void runNextTask() {
    assert(!ownerQueue.empty());
    auto task = std::move(ownerQueue.front());
    ownerQueue.pop_front();
    onOwnerThread = true;
    task();
    onOwnerThread = false;
}

static void drainOwnerQueue() {
    int remaining = 1000;
    while (!ownerQueue.empty()) {
        assert(remaining-- > 0);
        runNextTask();
    }
}

static bool bridge_runOnOwnerAsync(std::function<void()> task) {
    if (!acceptsTasks) return false;
    ownerQueue.push_back(std::move(task));
    return true;
}

template <typename Operation>
static auto bridge_runOnOwnerSync(Operation&& operation) {
    if (onOwnerThread) return operation();
    using Result = std::invoke_result_t<Operation>;
    Result result{};
    bool completed = false;
    assert(bridge_runOnOwnerAsync([&] {
        result = operation();
        completed = true;
    }));
    while (!completed) runNextTask();
    return result;
}

static bool bridge_ownerThreadRunning() { return true; }

static std::vector<mln::CameraOptions> appliedCameras;
static int easeCalls = 0;
static int flyCalls = 0;

// Omitted fields keep their values, as MapLibre's Transform does.
struct Map {
    mln::CameraOptions camera{mln::LatLng{35, 139}, 13.0, 0.0, 0.0};
    mln::CameraOptions getCameraOptions() const {
        assert(onOwnerThread);
        return camera;
    }
    void jumpTo(const mln::CameraOptions& next) {
        assert(onOwnerThread);
        appliedCameras.push_back(next);
        if (next.center) camera.center = next.center;
        if (next.zoom) camera.zoom = next.zoom;
        if (next.bearing) camera.bearing = next.bearing;
        if (next.pitch) camera.pitch = next.pitch;
        ++g_cameraStateRevision;
        g_frontendCameraRevision = g_cameraStateRevision.load();
        g_renderDirty = true;
    }
    void easeTo(const mln::CameraOptions& next,
                const mln::AnimationOptions& animation) {
        assert(animation.duration && animation.duration->count() > 0);
        ++easeCalls;
        jumpTo(next);
    }
    void flyTo(const mln::CameraOptions& next,
               const mln::AnimationOptions& animation) {
        assert(animation.duration && animation.duration->count() > 0);
        ++flyCalls;
        jumpTo(next);
    }
};
static Map map;
static Map* g_map = &map;

template <typename Operation>
static int runCameraOperation(const char*, Operation&& operation) {
    return bridge_runOnOwnerSync([&] { return operation() ? 1 : 0; });
}

static void discardUnacquiredFrameLocked();
#include "camera_dispatch.inc"
#include "camera_query.inc"
using maplibre_bridge::camera::runCameraMutation;
#include "camera_partial.inc"
#include "frame_publication_helpers.inc"

struct Frontend {
    std::optional<mln::CameraOptions> getTransformState() {
        assert(onOwnerThread);
        return g_map->camera;
    }
    void renderFrame() {
        assert(onOwnerThread && g_asyncFrame.rendering);
        assert(!g_asyncFrame.ready && !g_asyncFrame.acquired);
        ++renderedFrames;
        geometry.assign(16, renderedFrames);
        if (duringRender) duringRender();
        if (failRender) throw std::runtime_error("test render failure");
    }
};
static Frontend frontend;
static Frontend* g_frontend = &frontend;

static bool beginCommandFrameOnOwner(bool) {
    assert(onOwnerThread && !g_asyncFrame.acquired);
    return true;
}
static bool endCommandFrameOnOwner(const mln::CameraOptions* camera) {
    assert(onOwnerThread);
    g_snapshotCamera = *camera;
    return true;
}
static void bridge_finishRenderOnOwner() { g_renderDirty = false; }
static void notifyRenderRequested() {
    ++wakes;
    if (g_asyncFrame.ready) ++publishedFrames;
}
#include "async_renderer.inc"

static void submitCamera(const mln::CameraOptions& camera) {
    assert(maplibre_bridge::camera::runCameraMutation("set camera", [camera] {
        g_map->jumpTo(camera);
        return true;
    }) == 1);
}

static mln::CameraOptions liveCamera() {
    std::array<double, 5> values{};
    assert(maplibre_get_camera(values.data()) == 1);
    return {
        .center = mln::LatLng{values[0], values[1]},
        .zoom = values[2],
        .bearing = values[3],
        .pitch = values[4],
    };
}

static std::array<double, 5> frameCamera() {
    std::array<double, 5> values{};
    assert(maplibre_frame_get_camera(values.data()) == 1);
    return values;
}

static void requestAndPublish() {
    assert(maplibre_render_frame_async() == 1);
    drainOwnerQueue();
    assert(g_asyncFrame.ready);
}

static void queueResourceMutation(int value) {
    assert(maplibre_bridge::camera::runCameraMutation("resource", [value] {
        assert(onOwnerThread && !g_asyncFrame.ready && !g_asyncFrame.acquired);
        mutationOrder.push_back(value);
        return true;
    }, false) == 1);
}

int main() {
    assert(maplibre_camera_preserves_frame() == 1);
    duringRender = [] {
        auto next = g_map->camera;
        next.zoom = next.zoom.value() + 1;
        submitCamera(next);
    };
    for (int frame = 0; frame < 100; ++frame) {
        requestAndPublish();
        assert(renderedFrames == frame + 1);
        assert(publishedFrames == renderedFrames);
        assert(wakes == publishedFrames);
        assert(g_pendingCameraMutations == 0);
        assert(frameCamera()[2] == 13 + frame);
        assert(liveCamera().zoom == 14 + frame);
        const auto lease = maplibre_frame_acquire();
        assert(lease != 0);
        maplibre_frame_release(lease);
    }
    duringRender = {};
    drainOwnerQueue();
    assert(renderedFrames == 101 && publishedFrames == 101);
    const auto publishedCamera = frameCamera();
    const auto publishedGeometry = geometry;
    const auto generation = g_asyncFrame.generation;

    // Live reads observe earlier accepted owner work in queue order.
    auto zoom = liveCamera();
    zoom.zoom = 15;
    submitCamera(zoom);
    auto target = liveCamera();
    assert(target.zoom == 15);
    target.center = mln::LatLng{36, 140};
    submitCamera(target);
    auto bearing = liveCamera();
    assert(bearing.zoom == 15 && bearing.center->latitude() == 36);
    bearing.bearing = 40;
    submitCamera(bearing);
    assert(liveCamera().bearing == 40);
    assert(maplibre_get_camera_zoom() == 15);
    assert(maplibre_get_camera_lat() == 36);
    assert(g_asyncFrame.ready && g_asyncFrame.generation == generation);
    assert(geometry == publishedGeometry && frameCamera() == publishedCamera);

    // Partial commands carry only the fields they set. The owner fills the
    // rest from the state left by earlier accepted work, so no live read
    // precedes them and the published frame stays untouched.
    appliedCameras.clear();
    assert(maplibre_camera_apply_partial(1, 37, 141, 0, 0, 0, 0, 0, 0, 0, -1, 0) == 1);
    assert(maplibre_camera_apply_partial(0, 0, 0, 1, 16, 0, 0, 0, 0, 0, -1, 0) == 1);
    assert(maplibre_camera_apply_partial(0, 0, 0, 0, 0, 0, 0, 1, 20, 0, -1, 1) == 1);
    assert(appliedCameras.empty() && g_pendingCameraMutations == 3);
    const auto composed = liveCamera();
    assert(composed.center->latitude() == 37 && composed.center->longitude() == 141);
    assert(composed.zoom == 16 && composed.bearing == 40 && composed.pitch == 20);
    assert(g_pendingCameraMutations == 0 && appliedCameras.size() == 3);
    assert(appliedCameras[0].center && !appliedCameras[0].zoom &&
           !appliedCameras[0].bearing && !appliedCameras[0].pitch);
    assert(!appliedCameras[1].center && appliedCameras[1].zoom &&
           !appliedCameras[1].bearing && !appliedCameras[1].pitch);
    assert(!appliedCameras[2].center && !appliedCameras[2].zoom &&
           !appliedCameras[2].bearing && appliedCameras[2].pitch);
    // A zero duration jumps even when a flight is requested.
    assert(easeCalls == 0 && flyCalls == 0);
    assert(maplibre_camera_apply_partial(0, 0, 0, 1, 15, 0, 0, 1, 0, 300, 1, 0) == 1);
    assert(maplibre_camera_apply_partial(1, 36, 140, 0, 0, 1, 40, 0, 0, 300, -1, 1) == 1);
    assert(liveCamera().zoom == 15 && liveCamera().pitch == 0);
    assert(easeCalls == 1 && flyCalls == 1);
    assert(g_asyncFrame.ready && g_asyncFrame.generation == generation);
    assert(geometry == publishedGeometry && frameCamera() == publishedCamera);

    const auto lease = maplibre_frame_acquire();
    assert(lease == generation);
    maplibre_bridge::camera::postGestureOperation("rotate", [] {
        auto camera = g_map->getCameraOptions();
        camera.bearing = camera.bearing.value() + 5;
        g_map->jumpTo(camera);
    });
    assert(liveCamera().bearing == 45);
    assert(g_asyncFrame.acquired && g_asyncFrame.generation == generation);
    assert(geometry == publishedGeometry && frameCamera() == publishedCamera);
    maplibre_frame_release(lease + 1);
    assert(g_asyncFrame.acquired);

    queueResourceMutation(1);
    queueResourceMutation(2);
    assert(mutationOrder.empty());
    assert(maplibre_camera_preserves_frame() == 0);
    // The widget releases a lease before composing camera changes when an
    // earlier resource mutation is waiting for that same frame.
    maplibre_frame_release(lease);
    drainOwnerQueue();
    assert((mutationOrder == std::vector<int>{1, 2}));
    assert(frameCamera()[2] == 15 && frameCamera()[3] == 45);
    assert(maplibre_camera_preserves_frame() == 1);

    // FIFO holds whether camera admission precedes or follows lease release.
    for (bool admitBeforeRelease : {true, false}) {
        const auto orderedLease = maplibre_frame_acquire();
        assert(orderedLease != 0);
        queueResourceMutation(20);
        assert(maplibre_bridge::camera::runCameraMutation("fit after resize", [] {
            assert(mutationOrder.back() == 20);
            mutationOrder.push_back(21);
            auto camera = g_map->camera;
            camera.zoom = 16;
            g_map->jumpTo(camera);
            return true;
        }) == 1);
        if (admitBeforeRelease) drainOwnerQueue();
        assert(mutationOrder.back() == 2 && g_pendingCameraMutations == 1);
        assert(maplibre_camera_preserves_frame() == 0);
        maplibre_frame_release(orderedLease);
        auto afterResources = liveCamera();
        assert(afterResources.zoom == 16);
        afterResources.center = mln::LatLng{37, 141};
        submitCamera(afterResources);
        assert(liveCamera().zoom == 16);
        drainOwnerQueue();
        assert((mutationOrder == std::vector<int>{1, 2, 20, 21}));
        mutationOrder.resize(2);
    }

    // Invalidating an unread frame preserves earlier resource mutation order.
    const auto resourceLease = maplibre_frame_acquire();
    maplibre_frame_release(resourceLease);
    g_renderDirty = true;
    duringRender = [] { queueResourceMutation(3); };
    requestAndPublish();
    duringRender = {};
    queueResourceMutation(4);
    assert(!g_asyncFrame.ready);
    assert((mutationOrder == std::vector<int>{1, 2, 3, 4}));
    g_renderDirty = true;
    duringRender = [] { queueResourceMutation(5); };
    requestAndPublish();
    duringRender = {};
    assert(bridge_runOnOwnerSync([] {
        assert(bridge_prepareSynchronousMutation());
        assert((mutationOrder == std::vector<int>{1, 2, 3, 4, 5}));
        return true;
    }));
    assert(!g_asyncFrame.ready);

    // Pausing retains borrowed storage and drains accepted work on release.
    g_renderDirty = true;
    requestAndPublish();
    const auto pausedLease = maplibre_frame_acquire();
    const auto beforePause = renderedFrames;
    g_renderingPaused = true;
    queueResourceMutation(6);
    maplibre_frame_release(pausedLease);
    drainOwnerQueue();
    assert(mutationOrder.back() == 6 && renderedFrames == beforePause);
    assert(maplibre_frame_acquire() == 0);
    g_renderingPaused = false;

    acceptsTasks = false;
    assert(maplibre_bridge::camera::runCameraMutation("rejected", [] {
        assert(false);
        return true;
    }) == 0);
    assert(g_pendingCameraMutations == 0);
    acceptsTasks = true;
    submitCamera(map.camera);
    assert(g_pendingCameraMutations == 1);
    ownerQueue.clear();
    assert(g_pendingCameraMutations == 0);

    // Failed renders never publish a partially captured generation.
    failRender = true;
    g_renderDirty = true;
    const auto beforeFailure = g_asyncFrame.generation;
    assert(maplibre_render_frame_async() == 1);
    drainOwnerQueue();
    assert(!g_asyncFrame.ready && g_asyncFrame.generation == beforeFailure);
    failRender = false;
    requestAndPublish();
    const auto finalLease = maplibre_frame_acquire();
    g_sessionActive = false;
    maplibre_frame_release(finalLease);
    assert(!g_asyncFrame.ready && !g_asyncFrame.acquired);
    assert(ownerQueue.empty());
    std::puts("Continuous camera input preserves frames, live query order, partial composition, and lease lifetime");
}
