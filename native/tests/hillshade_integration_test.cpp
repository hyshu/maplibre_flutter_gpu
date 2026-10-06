#include <mln/command_export/draw_command.hpp>
#include <mln/util/image.hpp>

#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <string>
#include <thread>
#include <unistd.h>

extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
int maplibre_init(int, int, float, const char*);
int maplibre_style_set(const char*);
int maplibre_style_set_layer_visibility(const char*, int);
int maplibre_style_set_layer_properties(const char*, const char*);
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

static constexpr uint32_t demSize = 32;

static std::string makeStyle(const std::filesystem::path& image, const std::string& encoding, int maxzoom = 0) {
    return R"({"version":8,"transition":{"duration":0,"delay":0},"sources":{"dem":{
      "type":"raster-dem","tileSize":256,"maxzoom":)" + std::to_string(maxzoom) + R"(,"encoding":")" + encoding +
      R"(","tiles":["file://)" + image.string() + R"("]}},"layers":[
      {"id":"background","type":"background","paint":{"background-color":"white"}},
      {"id":"first","type":"hillshade","source":"dem","paint":{
        "hillshade-illumination-anchor":"viewport","hillshade-illumination-direction":[90,180],
        "hillshade-illumination-altitude":[45,70],"hillshade-method":"standard"}},
      {"id":"second","type":"hillshade","source":"dem","paint":{"hillshade-method":"igor"}}
    ]})";
}

static float floatAt(const uint8_t* bytes, size_t offset) {
    float value;
    std::memcpy(&value, bytes + offset, sizeof(value));
    return value;
}

static int32_t intAt(const uint8_t* bytes, size_t offset) {
    int32_t value;
    std::memcpy(&value, bytes + offset, sizeof(value));
    return value;
}

static void render() {
    maplibre_frame_begin();
    assert(maplibre_render_frame() == 0);
    maplibre_frame_end();
}

struct Frame {
    std::set<uint32_t> targets;
    std::set<uint32_t> layers;
    std::map<uint32_t, float> azimuths;
    std::map<uint8_t, std::pair<uint32_t, uint8_t>> borders;
};

static Frame inspectFrame(bool terrarium) {
    Frame frame;
    std::set<uint32_t> prepared;
    std::set<uint32_t> sampled;
    const auto* commands = static_cast<const DrawCommand*>(maplibre_frame_get_commands());
    const auto count = maplibre_frame_get_command_count();
    for (int i = 0; i < count; ++i) {
        const auto& command = commands[i];
        if (command.shaderType == ShaderType::RenderTarget) {
            assert(command.renderTargetId != 0);
            assert(command.renderTargetWidth == demSize && command.renderTargetHeight == demSize);
            assert(command.flags == DrawCommandFlags::RenderTargetRGBA8);
            assert(command.vertexCount == 0 && command.indexCount == 0);
            assert(frame.targets.insert(command.renderTargetId).second);
        } else if (command.shaderType == ShaderType::HillshadePrepare) {
            assert(frame.targets.contains(command.renderTargetId));
            assert(command.vertexStride == 8 && command.vertexCount == 4 && command.indexCount == 6);
            assert(command.drawableUBOSize == 64 && command.propsUBOSize == 0 && command.tilePropsUBOSize == 32);
            assert(command.texData && command.texWidth == demSize + 2 && command.texHeight == demSize + 2);
            assert(command.texChannels == 4 && command.texFilter == TextureFilterType::Nearest);
            assert((command.flags & (DrawCommandFlags::DepthTest | DrawCommandFlags::DepthWrite)) == 0);
            assert(command.stencilMode == StencilModeType::Disabled);
            assert(std::abs(floatAt(command.tilePropsUBO, 0) - (terrarium ? 256.0f : 6553.6f)) < 0.01f);
            assert(floatAt(command.tilePropsUBO, 12) == (terrarium ? 32768.0f : 10000.0f));
            assert(floatAt(command.tilePropsUBO, 16) == demSize + 2);
            assert(floatAt(command.tilePropsUBO, 20) == demSize + 2);
            assert(prepared.insert(command.renderTargetId).second);
            if (floatAt(command.tilePropsUBO, 24) == 1) {
                const auto* pixels = static_cast<const uint8_t*>(command.texData);
                const auto firstPixel = (command.texWidth + 1) * 4;
                const auto rightBorder = (command.texWidth * 10 + command.texWidth - 1) * 4;
                frame.borders.emplace(pixels[firstPixel + 1],
                                      std::make_pair(command.renderTargetId, pixels[rightBorder + 1]));
            }
        } else if (command.shaderType == ShaderType::Hillshade) {
            assert(prepared.contains(command.renderTargetId));
            assert(command.vertexStride == 8 && command.indexCount > 0);
            assert(command.drawableUBOSize == 64 && command.propsUBOSize == 176 && command.tilePropsUBOSize == 32);
            assert(command.texData == nullptr && command.texId == 0);
            assert(floatAt(command.tilePropsUBO, 0) > floatAt(command.tilePropsUBO, 4));
            assert(floatAt(command.tilePropsUBO, 8) > 0);
            assert(intAt(command.tilePropsUBO, 16) >= 1 && intAt(command.tilePropsUBO, 16) <= 4);
            const int method = intAt(command.tilePropsUBO, 12);
            assert(method == 0 || method == 2);
            if (method == 0) {
                assert(intAt(command.tilePropsUBO, 16) == 2);
                assert(std::abs(floatAt(command.propsUBO, 16) - 0.785398f) < 0.0001f);
                assert(std::abs(floatAt(command.propsUBO, 20) - 1.221730f) < 0.0001f);
                frame.azimuths.emplace(command.layerIndex, floatAt(command.propsUBO, 32));
            }
            frame.layers.insert(command.layerIndex);
            sampled.insert(command.renderTargetId);
        }
    }
    assert(prepared == frame.targets);
    assert(sampled == frame.targets);
    return frame;
}

static Frame awaitFrame(size_t layers, bool terrarium = false) {
    for (int attempt = 0; attempt < 300; ++attempt) {
        render();
        auto frame = inspectFrame(terrarium);
        if (frame.layers.size() == layers && frame.targets.size() == (layers == 0 ? 0 : 1)) return frame;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    assert(false && "Hillshade commands did not become ready");
    return {};
}

static uint32_t awaitBorder(uint8_t tileValue, uint8_t neighborValue) {
    for (int attempt = 0; attempt < 300; ++attempt) {
        render();
        const auto frame = inspectFrame(false);
        const auto found = frame.borders.find(tileValue);
        if (found != frame.borders.end() && found->second.second == neighborValue) return found->second.first;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    const auto frame = inspectFrame(false);
    std::fprintf(stderr, "Waiting for DEM value %u beside %u with %zu targets\n",
                 tileValue, neighborValue, frame.targets.size());
    for (const auto& [marker, border] : frame.borders) {
        std::fprintf(stderr, "DEM value %u has right border %u and target %u\n", marker, border.second, border.first);
    }
    assert(false && "Neighbor DEM border did not become ready");
    return 0;
}

int main() {
    const auto directory = std::filesystem::temp_directory_path() /
                           ("maplibre-hillshade-" + std::to_string(getpid()));
    std::filesystem::create_directories(directory);
    const auto imagePath = directory / "dem.png";
    mln::PremultipliedImage dem({demSize, demSize});
    for (uint32_t y = 0; y < demSize; ++y) {
        for (uint32_t x = 0; x < demSize; ++x) {
            auto* pixel = dem.data.get() + (y * demSize + x) * 4;
            pixel[0] = 1;
            pixel[1] = static_cast<uint8_t>(80 + x);
            pixel[2] = static_cast<uint8_t>(y * 8);
            pixel[3] = 255;
        }
    }
    std::ofstream(imagePath, std::ios::binary) << mln::encodePNG(dem);
    auto* session = maplibre_session_create();
    assert(session);
    maplibre_session_select(session);
    const auto style = makeStyle(imagePath, "mapbox");
    assert(maplibre_init(128, 128, 2, style.c_str()) == 0);
    maplibre_set_camera_full(0, 0, 2, 0, 0);
    const auto initial = awaitFrame(2);
    assert(awaitFrame(2).targets == initial.targets);
    maplibre_set_camera_full(0, 0, 2, 90, 0);
    const auto rotated = awaitFrame(2);
    assert(rotated.targets == initial.targets);
    assert(std::abs(std::abs(rotated.azimuths.begin()->second - initial.azimuths.begin()->second) - 1.570796f) < 0.0001f);
    maplibre_set_size(480, 320);
    assert(awaitFrame(2).targets == initial.targets);
    assert(maplibre_style_set_layer_visibility("second", 0) == 1);
    assert(awaitFrame(1).targets == initial.targets);
    assert(maplibre_style_set_layer_visibility("first", 0) == 1);
    awaitFrame(0);
    assert(maplibre_style_set_layer_visibility("second", 1) == 1);
    awaitFrame(1);
    assert(maplibre_style_set_layer_visibility("first", 1) == 1);
    awaitFrame(2);
    assert(maplibre_style_set_layer_properties("second", R"({"hillshade-exaggeration":0})") == 1);
    awaitFrame(1);
    assert(maplibre_style_set_layer_properties("first", R"({"hillshade-exaggeration":0})") == 1);
    awaitFrame(0);
    assert(maplibre_style_set_layer_properties("second", R"({"hillshade-exaggeration":0.5})") == 1);
    awaitFrame(1);
    assert(maplibre_style_set_layer_properties("first", R"({"hillshade-exaggeration":0.5})") == 1);
    awaitFrame(2);
    assert(maplibre_style_set(R"({"version":8,"sources":{},"layers":[]})") == 1);
    awaitFrame(0);
    const auto terrariumStyle = makeStyle(imagePath, "terrarium");
    assert(maplibre_style_set(terrariumStyle.c_str()) == 1);
    assert(awaitFrame(2, true).targets != initial.targets);
    assert(maplibre_style_set(style.c_str()) == 1);
    awaitFrame(2);
    for (uint32_t y = 0; y < 2; ++y) {
        for (uint32_t x = 0; x < 2; ++x) {
            for (uint32_t pixel = 0; pixel < demSize * demSize; ++pixel) {
                dem.data[pixel * 4 + 1] = static_cast<uint8_t>(80 + x * 10 + y * 20);
            }
            std::ofstream(directory / ("1-" + std::to_string(x) + "-" + std::to_string(y) + ".png"),
                          std::ios::binary) << mln::encodePNG(dem);
        }
    }
    std::ofstream(directory / "0-0-0.png", std::ios::binary) << mln::encodePNG(dem);
    const auto neighborStyle = makeStyle(directory / "{z}-{x}-{y}.png", "mapbox", 1);
    maplibre_set_camera_full(66, -90, 4, 0, 0);
    assert(maplibre_style_set(neighborStyle.c_str()) == 1);
    const auto isolated = awaitBorder(80, 80);
    maplibre_set_camera_full(66, 0, 4, 0, 0);
    const auto backfilled = awaitBorder(80, 90);
    assert(backfilled != isolated);
    for (int frame = 0; frame < 10; ++frame) {
        render();
        inspectFrame(false);
    }
    maplibre_destroy();
    maplibre_session_release(session);
    maplibre_shutdown_all();
    std::filesystem::remove_all(directory);
    std::puts("Hillshade native export, shared targets, encodings, lighting, camera, visibility, exaggeration, reload, and DEM neighbor updates passed");
}
