#include "bridge_session.hpp"

#include <mln/map/map_options.hpp>

#include <cassert>
#include <cmath>
#include <cstdio>

extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
int maplibre_init(int, int, float, const char*);
void maplibre_set_bounds(int, double, double, double, double, int, double, int, double);
void maplibre_set_constrain_mode(int);
void maplibre_set_camera_full(double, double, double, double, double);
void maplibre_destroy();
void maplibre_shutdown_all();
}

static constexpr const char* style = R"({"version":8,"sources":{},"layers":[]})";

static void assertMode(mln::ConstrainMode expected) {
    bridge_runOnOwnerSync([expected] {
        assert(g_map->getMapOptions().constrainMode() == expected);
    });
}

static void assertCamera(double latitude, double longitude, double zoom) {
    bridge_runOnOwnerSync([=] {
        const auto camera = g_map->getCameraOptions();
        assert(std::abs(camera.center->latitude() - latitude) < 1e-8);
        assert(std::abs(camera.center->longitude() - longitude) < 1e-8);
        assert(std::abs(*camera.zoom - zoom) < 1e-8);
    });
}

int main() {
    auto* first = maplibre_session_create();
    auto* second = maplibre_session_create();
    assert(first && second);

    maplibre_session_select(first);
    assert(maplibre_init(256, 1024, 1, style) == 0);
    maplibre_set_bounds(0, 0, 0, 0, 0, 0, 0, 0, 0);
    assertMode(mln::ConstrainMode::HeightOnly);
    maplibre_set_camera_full(80, 139, 0, 0, 0);
    assertCamera(0, 139, 1);

    maplibre_set_constrain_mode(0);
    assertMode(mln::ConstrainMode::None);
    maplibre_set_camera_full(80, 139, 0, 0, 0);
    assertCamera(80, 139, 0);
    maplibre_set_bounds(0, 0, 0, 0, 0, 0, 0, 0, 0);
    assertMode(mln::ConstrainMode::None);
    assertCamera(80, 139, 0);

    maplibre_session_select(second);
    assert(maplibre_init(256, 1024, 1, style) == 0);
    maplibre_set_bounds(0, 0, 0, 0, 0, 0, 0, 0, 0);
    maplibre_set_constrain_mode(1);
    assertMode(mln::ConstrainMode::HeightOnly);
    maplibre_session_select(first);
    assertMode(mln::ConstrainMode::None);
    assertCamera(80, 139, 0);

    maplibre_set_bounds(1, 30, 130, 40, 150, 0, 0, 0, 0);
    assertMode(mln::ConstrainMode::None);
    maplibre_set_constrain_mode(0);
    maplibre_set_camera_full(50, 170, 0, 0, 0);
    assertCamera(40, 150, 0);

    maplibre_set_constrain_mode(2);
    assertMode(mln::ConstrainMode::Screen);
    maplibre_set_camera_full(35, 139, 0, 0, 0);
    bridge_runOnOwnerSync([] {
        assert(*g_map->getCameraOptions().zoom > 1);
    });
    maplibre_set_constrain_mode(-2);
    assertMode(mln::ConstrainMode::Screen);
    maplibre_set_constrain_mode(3);
    assertMode(mln::ConstrainMode::Screen);

    maplibre_set_constrain_mode(0);
    maplibre_set_constrain_mode(-1);
    assertMode(mln::ConstrainMode::Screen);
    maplibre_set_bounds(0, 0, 0, 0, 0, 1, 2, 1, 6);
    assertMode(mln::ConstrainMode::HeightOnly);
    maplibre_set_constrain_mode(0);
    maplibre_set_camera_full(80, 139, 0, 0, 0);
    assertCamera(80, 139, 2);

    maplibre_destroy();
    assert(maplibre_init(256, 1024, 1, style) == 0);
    maplibre_set_bounds(0, 0, 0, 0, 0, 0, 0, 0, 0);
    assertMode(mln::ConstrainMode::HeightOnly);
    maplibre_destroy();
    maplibre_session_release(first);
    maplibre_session_select(second);
    assertMode(mln::ConstrainMode::HeightOnly);
    maplibre_destroy();
    maplibre_session_release(second);
    maplibre_shutdown_all();
    std::puts("Camera constraints and session isolation passed");
}
