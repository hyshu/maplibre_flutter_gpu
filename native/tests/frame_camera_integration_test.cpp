#include "bridge_session.hpp"

#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>

extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
int maplibre_init(int, int, float, const char*);
int maplibre_style_set(const char*);
void maplibre_set_camera_full(double, double, double, double, double);
int maplibre_get_camera(double*);
int maplibre_frame_get_camera(double*);
const MapTransformMetadata* maplibre_frame_get_map_transform();
void maplibre_frame_begin();
int maplibre_render_frame();
void maplibre_frame_end();
void maplibre_destroy();
void maplibre_shutdown_all();
}

static constexpr const char* style = R"({"version":8,"sources":{},"layers":[]})";
using Camera = std::array<double, 5>;

static void setCamera(const Camera& camera) {
    maplibre_set_camera_full(
        camera[0], camera[1], camera[2], camera[3], camera[4]);
}

static void assertCamera(const Camera& actual, const Camera& expected) {
    for (size_t index = 0; index < actual.size(); ++index) {
        assert(std::abs(actual[index] - expected[index]) < 1e-8);
    }
}

static void assertFrameCamera(const Camera& expected) {
    Camera camera{};
    assert(maplibre_frame_get_camera(camera.data()) == 1);
    assertCamera(camera, expected);
    const auto* transform = maplibre_frame_get_map_transform();
    assert(transform && transform->valid);
    assert(std::abs(transform->zoom - expected[2]) < 1e-8);
}

static void assertNoFrameCamera() {
    const Camera sentinel{1, 2, 3, 4, 5};
    auto camera = sentinel;
    assert(maplibre_frame_get_camera(camera.data()) == 0);
    assert(camera == sentinel);
    assert(maplibre_frame_get_camera(nullptr) == 0);
    const auto* transform = maplibre_frame_get_map_transform();
    assert(transform && !transform->valid);
}

static void renderFrame() {
    maplibre_frame_begin();
    assert(maplibre_render_frame() == 0);
    maplibre_frame_end();
}

int main() {
    auto* first = maplibre_session_create();
    auto* second = maplibre_session_create();
    assert(first && second);
    maplibre_session_select(first);
    assert(maplibre_init(256, 256, 1, style) == 0);
    assertNoFrameCamera();

    const Camera rendered{35, 139, 12, 17, 25};
    const Camera advanced{36, 140, 10, 41, 7};
    const Camera following{37, 141, 11, 33, 12};
    setCamera(rendered);
    maplibre_frame_begin();
    assert(maplibre_render_frame() == 0);
    setCamera(advanced);
    maplibre_frame_end();
    assertFrameCamera(rendered);
    Camera live{};
    assert(maplibre_get_camera(live.data()) == 1);
    assertCamera(live, advanced);
    assert(maplibre_frame_get_camera(nullptr) == 0);
    assertFrameCamera(rendered);

    setCamera(following);
    assertFrameCamera(rendered);
    renderFrame();
    assertFrameCamera(following);
    assert(maplibre_style_set(style) == 1);
    assertNoFrameCamera();
    renderFrame();
    assertFrameCamera(following);

    maplibre_session_select(second);
    assert(maplibre_init(256, 256, 1, style) == 0);
    assertNoFrameCamera();
    setCamera(advanced);
    renderFrame();
    assertFrameCamera(advanced);
    maplibre_session_select(first);
    assertFrameCamera(following);

    maplibre_destroy();
    assertNoFrameCamera();
    assert(maplibre_init(256, 256, 1, style) == 0);
    assertNoFrameCamera();
    setCamera(rendered);
    renderFrame();
    assertFrameCamera(rendered);
    maplibre_destroy();
    maplibre_session_release(first);

    maplibre_session_select(second);
    assertFrameCamera(advanced);
    maplibre_destroy();
    assertNoFrameCamera();
    maplibre_session_release(second);
    maplibre_shutdown_all();
    std::puts("Rendered frame camera, transform, and session isolation passed");
}
