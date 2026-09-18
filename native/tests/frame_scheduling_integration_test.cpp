#include "bridge_session.hpp"

#include <cassert>
#include <cstdio>
#include <chrono>

extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
int maplibre_init(int, int, float, const char*);
int maplibre_style_set(const char*);
int maplibre_style_set_layer_properties(const char*, const char*);
int maplibre_render_frame();
void maplibre_destroy();
void maplibre_shutdown_all();
}

static constexpr const char* style = R"({"version":8,"sources":{},"layers":[]})";

static void finishTransitionFrame() {
    g_observer.onDidFinishRenderingFrame({
        .mode = mln::MapObserver::RenderMode::Full,
        .needsRepaint = true,
        .placementChanged = false,
        .renderingStats = {},
    });
    g_renderDirty = true;
    bridge_finishRenderOnOwner();
}

static void exhaustTransition() {
    for (int i = 0; i < 29; ++i) {
        finishTransitionFrame();
        assert(g_renderDirty && g_frameNeedsRepaint);
    }
    finishTransitionFrame();
    assert(!g_renderDirty && !g_frameNeedsRepaint);
}

int main() {
    auto* session = maplibre_session_create();
    assert(session);
    maplibre_session_select(session);
    assert(maplibre_init(256, 256, 1, style) == 0);
    bridge_runOnOwnerSync([] {
        g_stationaryRepaintBudget.setMinimumDuration(StationaryRepaintBudget::Milliseconds(0));
        exhaustTransition();
        g_observer.onGlyphsLoaded({}, {0, 255});
        exhaustTransition();
        g_observer.onSpriteLoaded(std::nullopt);
        exhaustTransition();
        g_observer.onTileAction(
            mln::TileOperation::EndParse, mln::OverscaledTileID{0, 0, {0, 0, 0}}, "tiles");
        exhaustTransition();
        g_observer.onCameraWillChange(mln::MapObserver::CameraChangeMode::Immediate);
        exhaustTransition();
    });
    assert(maplibre_style_set(style) == 1);
    bridge_runOnOwnerSync([] {
        g_stationaryRepaintBudget.setMinimumDuration(StationaryRepaintBudget::Milliseconds(0));
        exhaustTransition();
    });
    assert(maplibre_style_set(R"({"version":8,"transition":{"duration":2000,"delay":250},"sources":{},"layers":[{"id":"background","type":"background","paint":{"background-color":"red","background-color-transition":{"delay":500}}}]})") == 1);
    assert(maplibre_render_frame() == 0);
    assert(maplibre_style_set_layer_properties("background", R"({"background-color":"blue"})") == 1);
    for (int i = 0; i < 100; ++i) {
        assert(maplibre_render_frame() == 0);
        bridge_runOnOwnerSync([] {
            bridge_finishRenderOnOwner();
            assert(g_frameNeedsRepaint && g_renderDirty);
        });
    }
    bridge_runOnOwnerSync([] {
        for (int i = 0; i < 100; ++i) {
            g_observer.onDidFinishRenderingFrame({
                .mode = mln::MapObserver::RenderMode::Partial,
                .needsRepaint = true,
                .placementChanged = false,
                .renderingStats = {},
            });
            bridge_finishRenderOnOwner();
            assert(g_frameNeedsRepaint && g_renderDirty);
        }
    });
    bridge_runOnOwnerSync([] {
        const auto start = StationaryRepaintBudget::Clock::time_point{};
        bridge_resetRepaintBudget();
        for (int i = 0; i < 30; ++i) {
            assert(!g_stationaryRepaintBudget.expired(false, true, start));
        }
        assert(!g_stationaryRepaintBudget.expired(false, true, start + std::chrono::milliseconds(2499)));
        assert(g_stationaryRepaintBudget.expired(false, true, start + std::chrono::milliseconds(2500)));
    });
    assert(maplibre_style_set_layer_properties(
        "background", R"({"background-color-transition":{"duration":4000},"background-color":"green"})") == 1);
    bridge_runOnOwnerSync([] {
        const auto start = StationaryRepaintBudget::Clock::time_point{};
        for (int i = 0; i < 30; ++i) {
            assert(!g_stationaryRepaintBudget.expired(false, true, start));
        }
        assert(!g_stationaryRepaintBudget.expired(false, true, start + std::chrono::milliseconds(4249)));
        assert(g_stationaryRepaintBudget.expired(false, true, start + std::chrono::milliseconds(4250)));
    });
    maplibre_destroy();
    maplibre_session_release(session);
    maplibre_shutdown_all();
    std::puts("Owner-thread repaint scheduling passed");
}
