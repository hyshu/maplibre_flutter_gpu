#include <atomic>
#include <cassert>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>

static struct {
    std::mutex mutex;
    bool renderTaskQueued = false;
    bool syncFrameOpen = false;
    bool ready = false;
    bool acquired = false;
    bool rendering = false;
    bool renderDeferred = false;
    std::deque<std::function<void()>> deferredMutations;
} g_asyncFrame;
static std::atomic<bool> g_sessionActive{true};
static std::atomic<bool> g_renderingPaused{false};
static std::atomic<uint64_t> g_renderTaskEpoch{0};
static std::atomic<uint64_t> g_cameraStateRevision{0};
static std::deque<std::function<void()>> ownerQueue;
static uint64_t frontendRevision = 0;
static uint64_t presentedRevision = 0;
static int renderedFrames = 0;
static bool acceptsTasks = true;

static void prepareAsyncRenderOnOwner();
static void runAsyncRenderOnOwner();

static bool bridge_runOnOwnerAsync(std::function<void()> task) {
    if (!acceptsTasks) return false;
    ownerQueue.push_back(std::move(task));
    return true;
}

static void scheduleRenderAfterDeferredMutationsOnOwner(
    std::deque<std::function<void()>> mutations) {
    for (auto& mutation : mutations) mutation();
    bridge_runOnOwnerAsync([] { prepareAsyncRenderOnOwner(); });
}

static void recordFrame() {
    assert(g_asyncFrame.rendering);
    presentedRevision = frontendRevision;
    ++renderedFrames;
    g_asyncFrame.rendering = false;
}

#include "camera_frame_order.inc"

static void runNextTask() {
    assert(!ownerQueue.empty());
    auto task = std::move(ownerQueue.front());
    ownerQueue.pop_front();
    task();
}

static void drainOwnerQueue() {
    int remaining = 30;
    while (!ownerQueue.empty()) {
        assert(remaining-- > 0);
        runNextTask();
    }
}

static void mutateCamera() {
    const auto revision = ++g_cameraStateRevision;
    bridge_runOnOwnerAsync([revision] { frontendRevision = revision; });
}

int main() {
    prepareAsyncRenderOnOwner();
    drainOwnerQueue();
    assert(renderedFrames == 1);

    // Render progress uses the available frontend revision even when a newer
    // camera update is queued behind this frame.
    prepareAsyncRenderOnOwner();
    mutateCamera();
    runNextTask();
    assert(renderedFrames == 2);
    assert(presentedRevision == 0);
    drainOwnerQueue();
    prepareAsyncRenderOnOwner();
    drainOwnerQueue();
    assert(renderedFrames == 3);
    assert(presentedRevision == 1);

    // Input between preparation and rendering cannot postpone every frame.
    for (int index = 0; index < 100; ++index) {
        prepareAsyncRenderOnOwner();
        mutateCamera();
        runNextTask();
        assert(renderedFrames == index + 4);
        assert(presentedRevision == static_cast<uint64_t>(index + 1));
        runNextTask();
        assert(ownerQueue.empty());
    }
    prepareAsyncRenderOnOwner();
    drainOwnerQueue();
    assert(renderedFrames == 104);
    assert(presentedRevision == 101);

    prepareAsyncRenderOnOwner();
    g_asyncFrame.deferredMutations.push_back(mutateCamera);
    drainOwnerQueue();
    assert(renderedFrames == 105);
    assert(presentedRevision == 102);

    g_asyncFrame.acquired = true;
    prepareAsyncRenderOnOwner();
    assert(ownerQueue.empty());
    assert(g_asyncFrame.renderDeferred);
    assert(renderedFrames == 105);
    g_asyncFrame.acquired = false;

    acceptsTasks = false;
    prepareAsyncRenderOnOwner();
    assert(!g_asyncFrame.renderTaskQueued);
    assert(renderedFrames == 105);
    drainOwnerQueue();
}
