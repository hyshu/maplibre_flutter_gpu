#include <mln/command_export/draw_command.hpp>

#include <algorithm>
#include <cassert>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <thread>

extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
int maplibre_init(int, int, float, const char*);
int maplibre_style_set(const char*);
int maplibre_style_set_layer_visibility(const char*, int);
void maplibre_set_camera_full(double, double, double, double, double);
void maplibre_set_size(int, int);
void maplibre_frame_begin();
void maplibre_frame_end();
int maplibre_render_frame();
int maplibre_frame_get_command_count();
const void* maplibre_frame_get_commands();
void maplibre_destroy();
void maplibre_shutdown_all();
}

using namespace mln::command_export;

static constexpr const char* style = R"JSON({
  "version": 8,
  "transition": {"duration": 0, "delay": 0},
  "sources": {"points": {"type": "geojson", "data": {
    "type": "FeatureCollection", "features": [
      {"type": "Feature", "properties": {"weight": 0.5, "radius": 24},
       "geometry": {"type": "Point", "coordinates": [1, 1]}}
    ]
  }}},
  "layers": [
    {"id": "background", "type": "background", "paint": {"background-color": "white"}},
    {"id": "constant", "type": "heatmap", "source": "points",
     "paint": {"heatmap-weight": 1, "heatmap-radius": 20}},
    {"id": "data-driven", "type": "heatmap", "source": "points",
     "paint": {"heatmap-weight": ["get", "weight"],
               "heatmap-radius": ["interpolate", ["linear"], ["zoom"],
                                  0, ["get", "radius"], 10, ["*", 2, ["get", "radius"]]]}},
    {"id": "circle", "type": "circle", "source": "points"}
  ]
})JSON";

static void render() {
    maplibre_frame_begin();
    assert(maplibre_render_frame() == 0);
    maplibre_frame_end();
}

static bool checkFrame(uint32_t width, uint32_t height, size_t expectedTargets) {
    std::map<uint32_t, const DrawCommand*> targets;
    std::set<uint32_t> densityTargets;
    std::set<uint32_t> compositeTargets;
    bool constant = false;
    bool dataDriven = false;
    bool circle = false;
    const auto* commands = static_cast<const DrawCommand*>(maplibre_frame_get_commands());
    const auto count = maplibre_frame_get_command_count();
    for (int i = 0; i < count; ++i) {
        const auto& command = commands[i];
        if (command.shaderType == ShaderType::RenderTarget) {
            assert(command.renderTargetId != 0);
            assert(command.renderTargetWidth == std::max(1u, width / 2));
            assert(command.renderTargetHeight == std::max(1u, height / 2));
            assert(command.vertexCount == 0 && command.indexCount == 0);
            assert(targets.emplace(command.renderTargetId, &command).second);
        } else if (command.shaderType == ShaderType::Heatmap) {
            assert(command.drawableUBOSize == 80 && command.propsUBOSize == 16);
            assert((command.flags & (DrawCommandFlags::DepthTest | DrawCommandFlags::DepthWrite)) == 0);
            const auto flags = command.flags & DrawCommandFlags::HeatmapDataDrivenMask;
            uint32_t mask;
            std::memcpy(&mask, command.propsUBO + 12, sizeof(mask));
            if (flags != 0) {
                assert(flags == DrawCommandFlags::HeatmapDataDrivenMask && mask == 3);
                assert(command.vertexStride == 20);
                dataDriven = true;
            } else {
                assert(command.vertexStride == 4 && mask == 0);
                constant = true;
            }
            densityTargets.insert(command.renderTargetId);
        } else if (command.shaderType == ShaderType::HeatmapTexture) {
            assert(command.drawableUBOSize == 80 && command.propsUBOSize == 0);
            assert(command.texData && command.texWidth == 256 && command.texHeight == 1);
            assert(command.texChannels == 4 && command.texFilter == TextureFilterType::Linear);
            compositeTargets.insert(command.renderTargetId);
        } else if (command.shaderType == ShaderType::Circle) {
            circle = true;
        }
    }
    if (compositeTargets.size() != expectedTargets || !circle) return false;
    if (expectedTargets == 2 && (!constant || !dataDriven)) return false;
    if (expectedTargets == 1 && (!constant || dataDriven)) return false;
    assert(densityTargets == compositeTargets);
    if (expectedTargets != 0) assert(targets.size() == expectedTargets);
    for (const auto target : compositeTargets) assert(targets.contains(target));
    return true;
}

static void awaitFrame(uint32_t width, uint32_t height, size_t targets) {
    for (int attempt = 0; attempt < 200; ++attempt) {
        render();
        if (checkFrame(width, height, targets)) return;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    const auto* commands = static_cast<const DrawCommand*>(maplibre_frame_get_commands());
    for (int i = 0; i < maplibre_frame_get_command_count(); ++i) {
        const auto& command = commands[i];
        float opacity = 0;
        if (command.shaderType == ShaderType::HeatmapTexture) {
            std::memcpy(&opacity, command.drawableUBO + 64, sizeof(opacity));
        }
        std::fprintf(stderr, "shader=%u target=%u stride=%u flags=%u drawable=%u props=%u\n",
                     static_cast<uint32_t>(command.shaderType), command.renderTargetId,
                     command.vertexStride, command.flags, command.drawableUBOSize, command.propsUBOSize);
        if (command.shaderType == ShaderType::HeatmapTexture) std::fprintf(stderr, "opacity=%f\n", opacity);
    }
    assert(false && "Heatmap commands did not become ready");
}

static void awaitHeatmapRemoval() {
    for (int attempt = 0; attempt < 200; ++attempt) {
        render();
        bool hasHeatmap = false;
        const auto* commands = static_cast<const DrawCommand*>(maplibre_frame_get_commands());
        for (int i = 0; i < maplibre_frame_get_command_count(); ++i) {
            hasHeatmap |= commands[i].shaderType == ShaderType::Heatmap ||
                          commands[i].shaderType == ShaderType::HeatmapTexture ||
                          commands[i].shaderType == ShaderType::RenderTarget;
        }
        if (!hasHeatmap) return;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    assert(false && "Removed heatmap retained commands");
}

int main() {
    auto* session = maplibre_session_create();
    assert(session);
    maplibre_session_select(session);
    assert(maplibre_init(256, 256, 2, style) == 0);
    maplibre_set_camera_full(1, 1, 4, 0, 0);
    awaitFrame(256, 256, 2);
    maplibre_set_size(480, 320);
    maplibre_set_camera_full(1, 1, 5, 25, 40);
    awaitFrame(480, 320, 2);
    maplibre_set_size(1, 320);
    awaitFrame(1, 320, 2);
    maplibre_set_size(480, 1);
    awaitFrame(480, 1, 2);
    maplibre_set_size(480, 320);
    awaitFrame(480, 320, 2);
    assert(maplibre_style_set_layer_visibility("data-driven", 0) == 1);
    awaitFrame(480, 320, 1);
    assert(maplibre_style_set(style) == 1);
    awaitFrame(480, 320, 2);
    assert(maplibre_style_set(R"({"version":8,"sources":{},"layers":[]})") == 1);
    awaitHeatmapRemoval();
    assert(maplibre_style_set(style) == 1);
    awaitFrame(480, 320, 2);
    auto transparent = std::string(style);
    const std::string key = "\"heatmap-weight\"";
    for (auto offset = transparent.find(key); offset != std::string::npos; offset = transparent.find(key, offset)) {
        const std::string opacity = "\"heatmap-opacity\": 0, ";
        transparent.insert(offset, opacity);
        offset += opacity.size() + key.size();
    }
    assert(maplibre_style_set(transparent.c_str()) == 1);
    awaitFrame(480, 320, 0);
    assert(maplibre_style_set(style) == 1);
    awaitFrame(480, 320, 2);
    maplibre_destroy();
    maplibre_session_release(session);
    maplibre_shutdown_all();
    std::puts("Heatmap native export, resize, visibility, removal, opacity, and style reload passed");
}
