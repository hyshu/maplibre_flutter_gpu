#include "bridge_state.hpp"
#include "command_frame_test_support.hpp"

#include <array>
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <set>
#include <thread>
#include <vector>

#include <mln/map/transform_state.hpp>

extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
int maplibre_init(int, int, float, const char*);
void maplibre_set_camera_full(double, double, double, double, double);
int maplibre_frame_get_camera(double*);
void maplibre_frame_begin();
int maplibre_render_frame();
void maplibre_frame_end();
void maplibre_destroy();
void maplibre_shutdown_all();
}

using namespace mln::command_export;

static constexpr const char* style = R"JSON({
  "version": 8,
  "transition": {"duration": 0, "delay": 0},
  "sources": {"geometry": {"type": "geojson", "data": {
    "type": "FeatureCollection", "features": [
      {"type": "Feature", "properties": {"height": 60},
       "geometry": {"type": "Polygon", "coordinates": [
         [[0.99, 0.99], [1.01, 0.99], [1.01, 1.01], [0.99, 1.01], [0.99, 0.99]]
       ]}},
      {"type": "Feature", "properties": {},
       "geometry": {"type": "Point", "coordinates": [1, 1]}}
    ]
  }}},
  "layers": [
    {"id": "background", "type": "background", "paint": {"background-color": "white"}},
    {"id": "fill", "type": "fill", "source": "geometry",
     "filter": ["==", "$type", "Polygon"], "paint": {"fill-color": "blue"}},
    {"id": "line", "type": "line", "source": "geometry",
     "filter": ["==", "$type", "Polygon"], "paint": {"line-color": "red", "line-width": 3}},
    {"id": "building", "type": "fill-extrusion", "source": "geometry",
     "filter": ["==", "$type", "Polygon"],
     "paint": {"fill-extrusion-height": ["get", "height"], "fill-extrusion-color": "gray"}},
    {"id": "circle", "type": "circle", "source": "geometry",
     "filter": ["==", "$type", "Point"], "paint": {"circle-radius": 5}}
  ]
})JSON";

struct BorrowedBytes {
    const void* address;
    std::vector<uint8_t> bytes;

    BorrowedBytes(const void* address_, size_t size) : address(address_), bytes(size) {
        assert(address || size == 0);
        if (size != 0) std::memcpy(bytes.data(), address, size);
    }

    void check() const {
        assert(bytes.empty() || std::memcmp(bytes.data(), address, bytes.size()) == 0);
    }
};

static void render() {
    maplibre_frame_begin();
    assert(maplibre_render_frame() == 0);
    maplibre_frame_end();
}

static bool hasGeometry() {
    const auto* frame = maplibre_frame_get_metadata();
    const auto* commands = static_cast<const DrawCommand*>(frame->commands);
    std::set<ShaderType> shaders;
    for (int index = 0; index < frame->commandCount; ++index) {
        if (commands[index].vertexCount != 0) shaders.insert(commands[index].shaderType);
    }
    return shaders.contains(ShaderType::Fill) && shaders.contains(ShaderType::Line) &&
           shaders.contains(ShaderType::FillExtrusion) && shaders.contains(ShaderType::Circle);
}

int main() {
    auto* session = maplibre_session_create();
    assert(session);
    maplibre_session_select(session);
    assert(maplibre_init(512, 512, 1, style) == 0);
    maplibre_set_camera_full(1, 1, 13, 0, 25);
    for (int attempt = 0; attempt < 200; ++attempt) {
        render();
        if (hasGeometry()) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    assert(hasGeometry());
    const auto metadata = *maplibre_frame_get_metadata();
    const auto* commands = static_cast<const DrawCommand*>(metadata.commands);
    std::vector<BorrowedBytes> borrowed;
    borrowed.emplace_back(metadata.commands, metadata.commandCount * metadata.commandStride);
    borrowed.emplace_back(metadata.payload, metadata.payloadSize);
    for (int index = 0; index < metadata.commandCount; ++index) {
        const auto& command = commands[index];
        borrowed.emplace_back(command.vertexData, command.vertexCount * command.vertexStride);
        borrowed.emplace_back(command.indexData, command.indexCount * sizeof(uint16_t));
    }
    std::array<double, 5> renderedCamera{};
    assert(maplibre_frame_get_camera(renderedCamera.data()) == 1);

    // Transform updates and frontend parameter replacement cannot invalidate
    // exported geometry before the next explicit renderer invocation.
    for (int step = 0; step < 100; ++step) {
        bridge_runOnOwnerSync([step] {
            mln::CameraOptions camera;
            camera.center = mln::LatLng{1.0 + step * 0.001, 1.0 - step * 0.001};
            camera.zoom = 12.0 + step * 0.01;
            camera.bearing = step;
            camera.pitch = step % 50;
            g_map->jumpTo(camera);
            const auto frontendState = g_frontend->getTransformState();
            assert(frontendState);
            const auto frontendCamera = frontendState->getCameraOptions(std::nullopt);
            assert(std::abs(*frontendCamera.zoom - *camera.zoom) < 1e-8);
            assert(std::abs(*frontendCamera.bearing - *camera.bearing) < 1e-8);
        });
        for (const auto& bytes : borrowed) bytes.check();
        const auto* frame = maplibre_frame_get_metadata();
        assert(frame->commands == metadata.commands && frame->payload == metadata.payload);
        assert(frame->commandCount == metadata.commandCount && frame->payloadSize == metadata.payloadSize);
        std::array<double, 5> stillRendered{};
        assert(maplibre_frame_get_camera(stillRendered.data()) == 1);
        assert(stillRendered == renderedCamera);
    }
    maplibre_set_camera_full(1, 1, 14, 30, 20);
    render();
    std::array<double, 5> nextCamera{};
    assert(maplibre_frame_get_camera(nextCamera.data()) == 1);
    const std::array<double, 5> expectedCamera{1, 1, 14, 30, 20};
    for (size_t index = 0; index < nextCamera.size(); ++index) {
        assert(std::abs(nextCamera[index] - expectedCamera[index]) < 1e-8);
    }
    maplibre_destroy();
    maplibre_session_release(session);
    maplibre_shutdown_all();
    std::puts("Owner camera changes preserve exported command, geometry, payload, and camera storage");
}
