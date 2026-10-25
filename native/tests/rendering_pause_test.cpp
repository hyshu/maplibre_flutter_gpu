#include <atomic>
#include <cassert>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <type_traits>
#include <vector>

#define __ANDROID__ 1
#define MLN_RENDER_BACKEND_COMMAND_EXPORT 1
#define MAPLIBRE_API

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
static std::atomic<uint64_t> g_renderTaskEpoch{0};
static std::mutex g_renderPauseMutex;
static uint64_t g_renderPauseRequestGeneration = 0;
static std::optional<uint64_t> g_renderPauseCameraCancellation;
static std::atomic<bool> g_cameraMoving{false};
static std::atomic<uint64_t> g_cameraStateRevision{0};
static std::atomic<uint64_t> g_cameraCommandGeneration{0};
static struct FakeMap {
    int cancellations = 0;
    bool gestureInProgress = true;
    void cancelTransitions() { ++cancellations; }
    void setGestureInProgress(bool value) { gestureInProgress = value; }
} map;
static auto* g_map = &map;
static std::vector<int> completions;
static void pauseCompleted(int result) { completions.push_back(result); }
static std::deque<std::function<void()>> ownerQueue;
static int renderedFrames = 0;
static uint64_t presentedRevision = 0;
static bool failOwnerDispatch = false;
static bool rejectOnOwner = false;

static bool bridge_ownerThreadRunning() { return !failOwnerDispatch; }

static void prepareAsyncRenderOnOwner();
static void runAsyncRenderOnOwner(uint64_t);
static void notifyRenderRequested() {}

static bool bridge_runOnOwnerAsync(std::function<void()> task) {
    if (failOwnerDispatch) return false;
    ownerQueue.push_back(std::move(task));
    return true;
}

static void runNextTask() {
    assert(!ownerQueue.empty());
    auto task = std::move(ownerQueue.front());
    ownerQueue.pop_front();
    task();
}

template <typename Operation>
static auto bridge_runOnOwnerSync(Operation operation) {
    if (failOwnerDispatch) throw std::runtime_error("Owner queue unavailable");
    std::optional<std::invoke_result_t<Operation>> result;
    bridge_runOnOwnerAsync([&] {
        if (rejectOnOwner) g_sessionActive = false;
        result = operation();
    });
    while (!result) runNextTask();
    return *result;
}

static void discardUnacquiredFrameLocked() {
    if (g_asyncFrame.ready && !g_asyncFrame.acquired) {
        g_asyncFrame.ready = false;
        g_snapshotWakePending = false;
    }
}

static void recordFrame(uint64_t revision) {
    assert(!g_renderingPaused);
    assert(g_asyncFrame.rendering);
    ++renderedFrames;
    presentedRevision = revision;
    g_asyncFrame.rendering = false;
    g_asyncFrame.ready = true;
    ++g_asyncFrame.generation;
    g_renderDirty = false;
}

#include "rendering_pause.inc"

static void drainOwnerQueue() {
    int remaining = 100;
    while (!ownerQueue.empty()) {
        assert(--remaining > 0);
        runNextTask();
    }
}

int main() {
    // A failed barrier must leave the caller's previous gate value intact.
    failOwnerDispatch = true;
    assert(maplibre_set_rendering_paused(1) == 0);
    assert(!g_renderingPaused);
    failOwnerDispatch = false;
    rejectOnOwner = true;
    assert(maplibre_set_rendering_paused(1) == 0);
    assert(!g_renderingPaused);
    rejectOnOwner = false;
    g_sessionActive = true;

    assert(enqueueAsyncRenderTask());
    drainOwnerQueue();
    assert(renderedFrames == 1);
    const auto lease = maplibre_frame_acquire();
    assert(lease != 0);

    // A pause preserves borrowed memory. Releasing it still applies accepted
    // mutations, without scheduling the dirty frame they would normally cause.
    assert(maplibre_set_rendering_paused(1) == 1);
    assert(g_asyncFrame.acquired);
    int mutations = 0;
    g_asyncFrame.deferredMutations.push_back([&] { ++mutations; });
    g_asyncFrame.renderDeferred = true;
    g_renderDirty = true;
    maplibre_frame_release(lease);
    drainOwnerQueue();
    assert(mutations == 1);
    assert(renderedFrames == 1);
    assert(!g_asyncFrame.acquired && !g_asyncFrame.ready);
    assert(maplibre_frame_acquire() == 0);

    for (int index = 0; index < 100; ++index) {
        assert(!enqueueAsyncRenderTask());
        prepareAsyncRenderOnOwner();
        runAsyncRenderOnOwner(g_cameraStateRevision);
    }
    assert(ownerQueue.empty());
    assert(renderedFrames == 1);

    std::deque<std::function<void()>> changes;
    changes.push_back([&] { ++mutations; });
    scheduleRenderAfterDeferredMutationsOnOwner(std::move(changes));
    assert(mutations == 2 && ownerQueue.empty());

    bool otherMapWorkRan = false;
    ownerQueue.push_back([&] { otherMapWorkRan = true; });
    assert(maplibre_set_rendering_paused(0) == 1);
    assert(!otherMapWorkRan);
    drainOwnerQueue();
    assert(otherMapWorkRan);
    assert(enqueueAsyncRenderTask());
    // A delayed task from an earlier active interval must not revive after a
    // rapid pause and resume, even if it is delivered after both barriers.
    auto delayed = std::move(ownerQueue.front());
    ownerQueue.pop_front();
    assert(maplibre_set_rendering_paused(1) == 1);
    assert(maplibre_set_rendering_paused(0) == 1);
    ownerQueue.push_back(std::move(delayed));
    drainOwnerQueue();
    assert(renderedFrames == 1);

    g_cameraStateRevision = 17;
    assert(enqueueAsyncRenderTask());
    assert(maplibre_set_rendering_paused(0) == 1);
    drainOwnerQueue();
    assert(renderedFrames == 2 && presentedRevision == 17);

    // A ready but unborrowed generation is discarded by the pause barrier.
    assert(g_asyncFrame.ready);
    assert(maplibre_set_rendering_paused(1) == 1);
    assert(!g_asyncFrame.ready);
    failOwnerDispatch = true;
    assert(maplibre_set_rendering_paused(0) == 0);
    assert(g_renderingPaused);
    failOwnerDispatch = false;
    assert(maplibre_set_rendering_paused(1) == 1);
    assert(ownerQueue.empty());

    // Both asynchronous transitions return before queued owner work runs.
    bool busyOwnerFinished = false;
    ownerQueue.push_back([&] { busyOwnerFinished = true; });
    maplibre_set_rendering_paused_async(0, pauseCompleted);
    assert(g_renderingPaused && completions.empty());
    assert(!busyOwnerFinished);
    drainOwnerQueue();
    assert(!g_renderingPaused && completions == std::vector<int>{1});
    completions.clear();
    maplibre_set_rendering_paused_async(1, pauseCompleted);
    assert(g_renderingPaused && completions.empty());
    drainOwnerQueue();
    assert(completions == std::vector<int>{1});
    assert(map.cancellations == 1 && !map.gestureInProgress);

    // Superseded barriers still complete once without reopening a newer gate
    // or cancelling camera work accepted after an intervening resume.
    completions.clear();
    maplibre_set_rendering_paused_async(1, pauseCompleted);
    maplibre_set_rendering_paused_async(0, pauseCompleted);
    maplibre_set_rendering_paused_async(1, pauseCompleted);
    drainOwnerQueue();
    assert((completions == std::vector<int>{0, 0, 1}));
    assert(g_renderingPaused && map.cancellations == 2);

    // Pausing an acquired generation keeps cancellation behind lease release.
    completions.clear();
    assert(maplibre_set_rendering_paused(0) == 1);
    assert(enqueueAsyncRenderTask());
    drainOwnerQueue();
    const auto pendingLease = maplibre_frame_acquire();
    assert(pendingLease != 0);
    maplibre_set_rendering_paused_async(1, pauseCompleted);
    drainOwnerQueue();
    assert(completions.empty() && map.cancellations == 2);
    maplibre_frame_release(pendingLease);
    drainOwnerQueue();
    assert(completions == std::vector<int>{1});
    assert(map.cancellations == 3);

    // A final resume still cancels motion that predates its superseded pause.
    completions.clear();
    maplibre_set_rendering_paused_async(1, pauseCompleted);
    maplibre_set_rendering_paused_async(0, pauseCompleted);
    drainOwnerQueue();
    assert((completions == std::vector<int>{0, 1}));
    assert(!g_renderingPaused && map.cancellations == 4);

    // A command accepted before the pause must be cancelled even when it has
    // not reached the owner. A command accepted afterwards remains valid.
    completions.clear();
    ++g_cameraCommandGeneration;
    ownerQueue.push_back([] { g_cameraMoving = true; });
    maplibre_set_rendering_paused_async(1, pauseCompleted);
    maplibre_set_rendering_paused_async(0, pauseCompleted);
    drainOwnerQueue();
    assert((completions == std::vector<int>{0, 1}));
    assert(!g_cameraMoving && map.cancellations == 5);
    completions.clear();
    maplibre_set_rendering_paused_async(1, pauseCompleted);
    ++g_cameraCommandGeneration;
    ownerQueue.push_back([] { g_cameraMoving = true; });
    maplibre_set_rendering_paused_async(0, pauseCompleted);
    drainOwnerQueue();
    assert((completions == std::vector<int>{0, 1}));
    assert(g_cameraMoving && map.cancellations == 5);

    completions.clear();
    assert(maplibre_set_rendering_paused(0) == 1);
    failOwnerDispatch = true;
    maplibre_set_rendering_paused_async(1, pauseCompleted);
    assert(!g_renderingPaused && completions == std::vector<int>{0});
    failOwnerDispatch = false;

    // Queue teardown must resolve the future even if its task never executes.
    completions.clear();
    maplibre_set_rendering_paused_async(1, pauseCompleted);
    ownerQueue.clear();
    assert(completions == std::vector<int>{0});

    g_sessionActive = false;
    assert(maplibre_set_rendering_paused(0) == 0);
    std::puts("Android rendering pause scheduling passed");
}
