#include "repaint_budget.hpp"

#include <atomic>
#include <cassert>

static std::atomic<bool> g_cameraMoving{false};
static std::atomic<bool> g_frameNeedsRepaint{false};
static std::atomic<bool> g_frameModeFull{true};
static std::atomic<bool> g_renderDirty{false};
static StationaryRepaintBudget g_stationaryRepaintBudget;

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
}
