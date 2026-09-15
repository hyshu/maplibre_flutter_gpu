#include "bridge_session.hpp"

#include <cassert>
#include <cstdio>

extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
int maplibre_init(int, int, float, const char*);
int maplibre_style_set(const char*);
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
    bridge_runOnOwnerSync([] { exhaustTransition(); });
    maplibre_destroy();
    maplibre_session_release(session);
    maplibre_shutdown_all();
    std::puts("Owner-thread repaint scheduling passed");
}
