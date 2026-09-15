#include "repaint_budget.hpp"

#include <atomic>
#include <cassert>
#include <deque>
#include <functional>
#include <mutex>

#define __ANDROID__ 1
#define MLN_RENDER_BACKEND_COMMAND_EXPORT 1

static std::atomic<bool> g_cameraMoving{false};
static std::atomic<bool> g_frameNeedsRepaint{false};
static std::atomic<bool> g_frameModeFull{true};
static std::atomic<bool> g_renderDirty{false};
static StationaryRepaintBudget g_stationaryRepaintBudget;
static struct {
    std::mutex mutex;
    bool ready = false;
    bool acquired = false;
    bool renderTaskQueued = false;
    bool rendering = false;
    bool renderDeferred = false;
    bool syncFrameOpen = false;
    std::deque<std::function<void()>> deferredMutations;
} g_asyncFrame;

static void prepareAsyncRenderOnOwner() {}
static bool bridge_runOnOwnerAsync(std::function<void()>) { return true; }

#include "frame_scheduling.inc"

static void finishFrame(bool full, bool repaint, bool moving = false) {
    g_frameModeFull = full;
    g_frameNeedsRepaint = repaint;
    g_cameraMoving = moving;
    g_renderDirty = true;
    bridge_finishRenderOnOwner();
}

static void exhaustTransition() {
    for (int i = 0; i < 29; ++i) {
        finishFrame(true, true);
        assert(g_renderDirty && g_frameNeedsRepaint);
    }
    finishFrame(true, true);
    assert(!g_renderDirty && !g_frameNeedsRepaint);
}

int main() {
    for (int i = 0; i < 1000; ++i) {
        finishFrame(true, false);
        assert(!g_renderDirty);
    }
    exhaustTransition();
    finishFrame(true, true);
    assert(!g_renderDirty && !g_frameNeedsRepaint);

    bridge_resetRepaintBudget();
    exhaustTransition();

    for (int i = 0; i < 100; ++i) {
        finishFrame(false, true, true);
        assert(g_renderDirty && g_frameNeedsRepaint);
    }
    exhaustTransition();

    bridge_resetRepaintBudget();
    finishFrame(false, true);
    assert(!g_renderDirty && !g_frameNeedsRepaint);
    bridge_resetRepaintBudget();
    exhaustTransition();

    // A self-update requested during the last allowed render must not survive
    // completion or be restored by a late completion callback.
    g_asyncFrame.rendering = true;
    g_renderDirty = true;
    assert(enqueueAsyncRenderTask());
    assert(g_asyncFrame.renderDeferred);
    finishFrame(true, true);
    assert(!g_asyncFrame.renderDeferred);
    assert(!enqueueAsyncRenderTask());
    assert(!g_asyncFrame.renderDeferred);

    g_asyncFrame.deferredMutations.push_back([] {});
    g_asyncFrame.renderDeferred = true;
    finishFrame(true, true);
    assert(g_asyncFrame.renderDeferred);
    assert(g_asyncFrame.deferredMutations.size() == 1);
    g_asyncFrame.deferredMutations.clear();
    g_asyncFrame.renderDeferred = false;
    bridge_resetRepaintBudget();
    finishFrame(true, true);
    assert(enqueueAsyncRenderTask());
    assert(g_asyncFrame.renderDeferred);
}
