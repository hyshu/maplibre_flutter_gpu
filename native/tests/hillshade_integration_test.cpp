#include "bridge_state.hpp"
#include "command_frame_test_support.hpp"
#include <mln/util/image.hpp>

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
#include <vector>

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
    MAPLIBRE_TEST_CHECK(maplibre_render_frame() == 0);
    maplibre_frame_end();
}

struct Preparation {
    uint32_t targetId;
    uint32_t bufferId;
    uint32_t bufferVersion;
    uint32_t vertexCount;
    uint32_t vertexStride;
    uint32_t indexCount;
    uint32_t textureId;
    uint32_t textureVersion;
    uint32_t textureWidth;
    uint32_t textureHeight;
    uint32_t textureChannels;
    TextureFilterType textureFilter;
    std::vector<uint8_t> vertices;
    std::vector<uint16_t> indices;
    std::vector<uint8_t> drawableUBO;
    std::vector<uint8_t> tilePropsUBO;
    std::vector<uint8_t> pixels;

    bool operator==(const Preparation&) const = default;
};

struct Frame {
    std::set<uint32_t> targets;
    std::set<uint32_t> layers;
    std::map<uint32_t, float> azimuths;
    std::map<uint8_t, std::pair<uint32_t, uint8_t>> borders;
    std::map<uint32_t, Preparation> preparations;
};

static Frame inspectFrame(bool terrarium) {
    Frame frame;
    std::set<uint32_t> prepared;
    std::set<uint32_t> sampled;
    const auto* commands = static_cast<const DrawCommand*>(maplibre_frame_get_commands());
    const auto count = maplibre_frame_get_command_count();
    for (int i = 0; i < count; ++i) {
        const auto& command = commands[i];
        const auto data = payloadFor(command);
        const auto target = data.renderTarget.value_or(CommandRenderTarget{});
        const auto texture = data.texture.value_or(CommandTexture{});
        const auto stencil = data.stencil.value_or(CommandStencil{});
        if (command.shaderType == ShaderType::RenderTarget) {
            MAPLIBRE_TEST_CHECK(target.id != 0);
            MAPLIBRE_TEST_CHECK(target.width == demSize && target.height == demSize);
            MAPLIBRE_TEST_CHECK(command.flags == DrawCommandFlags::RenderTargetRGBA8);
            MAPLIBRE_TEST_CHECK(command.vertexCount == 0 && command.indexCount == 0);
            MAPLIBRE_TEST_CHECK(frame.targets.insert(target.id).second);
        } else if (command.shaderType == ShaderType::HillshadePrepare) {
            MAPLIBRE_TEST_CHECK(frame.targets.contains(target.id));
            MAPLIBRE_TEST_CHECK(command.vertexStride == 8 && command.vertexCount == 4 && command.indexCount == 6);
            MAPLIBRE_TEST_CHECK(data.drawableUBO.size() == 64 && data.propsUBO.size() == 0 && data.tilePropsUBO.size() == 32);
            MAPLIBRE_TEST_CHECK(texture.data && texture.width == demSize + 2 && texture.height == demSize + 2);
            MAPLIBRE_TEST_CHECK(texture.channels == 4 && texture.filter == TextureFilterType::Nearest);
            MAPLIBRE_TEST_CHECK((command.flags & (DrawCommandFlags::DepthTest | DrawCommandFlags::DepthWrite)) == 0);
            MAPLIBRE_TEST_CHECK(stencil.mode == StencilModeType::Disabled);
            MAPLIBRE_TEST_CHECK(std::abs(floatAt(data.tilePropsUBO.data(), 0) - (terrarium ? 256.0f : 6553.6f)) < 0.01f);
            MAPLIBRE_TEST_CHECK(floatAt(data.tilePropsUBO.data(), 12) == (terrarium ? 32768.0f : 10000.0f));
            MAPLIBRE_TEST_CHECK(floatAt(data.tilePropsUBO.data(), 16) == demSize + 2);
            MAPLIBRE_TEST_CHECK(floatAt(data.tilePropsUBO.data(), 20) == demSize + 2);
            MAPLIBRE_TEST_CHECK(prepared.insert(target.id).second);
            MAPLIBRE_TEST_CHECK(command.bufferId != 0 && texture.id != 0);
            const auto* vertices = static_cast<const uint8_t*>(command.vertexData);
            const auto* pixels = static_cast<const uint8_t*>(texture.data);
            // Frame data is borrowed, so comparisons across renders own every byte.
            const Preparation preparation{
                target.id,
                command.bufferId,
                command.bufferVersion,
                command.vertexCount,
                command.vertexStride,
                command.indexCount,
                texture.id,
                texture.version,
                texture.width,
                texture.height,
                texture.channels,
                texture.filter,
                {vertices, vertices + command.vertexCount * command.vertexStride},
                {command.indexData, command.indexData + command.indexCount},
                {data.drawableUBO.begin(), data.drawableUBO.end()},
                {data.tilePropsUBO.begin(), data.tilePropsUBO.end()},
                {pixels, pixels + texture.width * texture.height * texture.channels},
            };
            MAPLIBRE_TEST_CHECK(frame.preparations.emplace(target.id, preparation).second);
            if (floatAt(data.tilePropsUBO.data(), 24) == 1) {
                const auto firstPixel = (texture.width + 1) * 4;
                const auto rightBorder = (texture.width * 10 + texture.width - 1) * 4;
                frame.borders.emplace(pixels[firstPixel + 1],
                                      std::make_pair(target.id, pixels[rightBorder + 1]));
            }
        } else if (command.shaderType == ShaderType::Hillshade) {
            MAPLIBRE_TEST_CHECK(prepared.contains(target.id));
            MAPLIBRE_TEST_CHECK(command.vertexStride == 8 && command.indexCount > 0);
            MAPLIBRE_TEST_CHECK(data.drawableUBO.size() == 64 && data.propsUBO.size() == 176 && data.tilePropsUBO.size() == 32);
            MAPLIBRE_TEST_CHECK(texture.data == nullptr && texture.id == 0);
            MAPLIBRE_TEST_CHECK(floatAt(data.tilePropsUBO.data(), 0) > floatAt(data.tilePropsUBO.data(), 4));
            MAPLIBRE_TEST_CHECK(floatAt(data.tilePropsUBO.data(), 8) > 0);
            MAPLIBRE_TEST_CHECK(intAt(data.tilePropsUBO.data(), 16) >= 1 && intAt(data.tilePropsUBO.data(), 16) <= 4);
            const int method = intAt(data.tilePropsUBO.data(), 12);
            MAPLIBRE_TEST_CHECK(method == 0 || method == 2);
            if (method == 0) {
                MAPLIBRE_TEST_CHECK(intAt(data.tilePropsUBO.data(), 16) == 2);
                MAPLIBRE_TEST_CHECK(std::abs(floatAt(data.propsUBO.data(), 16) - 0.785398f) < 0.0001f);
                MAPLIBRE_TEST_CHECK(std::abs(floatAt(data.propsUBO.data(), 20) - 1.221730f) < 0.0001f);
                frame.azimuths.emplace(command.layerIndex, floatAt(data.propsUBO.data(), 32));
            }
            frame.layers.insert(command.layerIndex);
            sampled.insert(target.id);
        }
    }
    MAPLIBRE_TEST_CHECK(prepared == frame.targets);
    MAPLIBRE_TEST_CHECK(sampled == frame.targets);
    return frame;
}

static Frame awaitFrame(size_t layers, bool terrarium = false) {
    Frame previous;
    bool previousReady = false;
    for (int attempt = 0; attempt < 300; ++attempt) {
        render();
        auto frame = inspectFrame(terrarium);
        // Loaded tiles can keep requesting repaint without changing preparation inputs.
        const auto loaded = bridge_runOnOwnerSync([] { return g_map && g_map->isFullyLoaded(); });
        const bool ready = frame.layers.size() == layers && frame.targets.size() == (layers == 0 ? 0 : 1) &&
                           loaded;
        if (ready && previousReady && frame.preparations == previous.preparations) return frame;
        previousReady = ready;
        if (ready) previous = std::move(frame);
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    MAPLIBRE_TEST_CHECK(false && "Hillshade commands did not become ready");
    return {};
}

static Preparation awaitBorder(uint8_t tileValue, uint8_t neighborValue) {
    for (int attempt = 0; attempt < 300; ++attempt) {
        render();
        const auto frame = inspectFrame(false);
        const auto found = frame.borders.find(tileValue);
        if (found != frame.borders.end() && found->second.second == neighborValue) {
            return frame.preparations.at(found->second.first);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    const auto frame = inspectFrame(false);
    std::fprintf(stderr, "Waiting for DEM value %u beside %u with %zu targets\n",
                 tileValue, neighborValue, frame.targets.size());
    for (const auto& [marker, border] : frame.borders) {
        std::fprintf(stderr, "DEM value %u has right border %u and target %u\n", marker, border.second, border.first);
    }
    MAPLIBRE_TEST_CHECK(false && "Neighbor DEM border did not become ready");
    return {};
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
    MAPLIBRE_TEST_CHECK(session);
    maplibre_session_select(session);
    const auto style = makeStyle(imagePath, "mapbox");
    MAPLIBRE_TEST_CHECK(maplibre_init(128, 128, 2, style.c_str()) == 0);
    maplibre_set_camera_full(0, 0, 2, 0, 0);
    const auto initial = awaitFrame(2);
    MAPLIBRE_TEST_CHECK(awaitFrame(2).preparations == initial.preparations);
    maplibre_set_camera_full(0, 0, 2, 90, 0);
    const auto rotated = awaitFrame(2);
    MAPLIBRE_TEST_CHECK(rotated.targets == initial.targets);
    MAPLIBRE_TEST_CHECK(rotated.preparations == initial.preparations);
    MAPLIBRE_TEST_CHECK(std::abs(std::abs(rotated.azimuths.begin()->second - initial.azimuths.begin()->second) - 1.570796f) < 0.0001f);
    maplibre_set_size(480, 320);
    MAPLIBRE_TEST_CHECK(awaitFrame(2).preparations == initial.preparations);
    MAPLIBRE_TEST_CHECK(maplibre_style_set_layer_visibility("second", 0) == 1);
    MAPLIBRE_TEST_CHECK(awaitFrame(1).targets == initial.targets);
    MAPLIBRE_TEST_CHECK(maplibre_style_set_layer_visibility("first", 0) == 1);
    awaitFrame(0);
    MAPLIBRE_TEST_CHECK(maplibre_style_set_layer_visibility("second", 1) == 1);
    awaitFrame(1);
    MAPLIBRE_TEST_CHECK(maplibre_style_set_layer_visibility("first", 1) == 1);
    awaitFrame(2);
    MAPLIBRE_TEST_CHECK(maplibre_style_set_layer_properties("second", R"({"hillshade-exaggeration":0})") == 1);
    awaitFrame(1);
    MAPLIBRE_TEST_CHECK(maplibre_style_set_layer_properties("first", R"({"hillshade-exaggeration":0})") == 1);
    awaitFrame(0);
    MAPLIBRE_TEST_CHECK(maplibre_style_set_layer_properties("second", R"({"hillshade-exaggeration":0.5})") == 1);
    awaitFrame(1);
    MAPLIBRE_TEST_CHECK(maplibre_style_set_layer_properties("first", R"({"hillshade-exaggeration":0.5})") == 1);
    awaitFrame(2);
    MAPLIBRE_TEST_CHECK(maplibre_style_set(R"({"version":8,"sources":{},"layers":[]})") == 1);
    awaitFrame(0);
    const auto terrariumStyle = makeStyle(imagePath, "terrarium");
    MAPLIBRE_TEST_CHECK(maplibre_style_set(terrariumStyle.c_str()) == 1);
    const auto terrarium = awaitFrame(2, true);
    MAPLIBRE_TEST_CHECK(terrarium.targets != initial.targets);
    MAPLIBRE_TEST_CHECK(terrarium.preparations.begin()->second.textureId != initial.preparations.begin()->second.textureId);
    MAPLIBRE_TEST_CHECK(terrarium.preparations.begin()->second.tilePropsUBO != initial.preparations.begin()->second.tilePropsUBO);
    MAPLIBRE_TEST_CHECK(maplibre_style_set(style.c_str()) == 1);
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
    MAPLIBRE_TEST_CHECK(maplibre_style_set(neighborStyle.c_str()) == 1);
    const auto isolated = awaitBorder(80, 80);
    maplibre_set_camera_full(66, 0, 4, 0, 0);
    const auto backfilled = awaitBorder(80, 90);
    MAPLIBRE_TEST_CHECK(backfilled.targetId != isolated.targetId);
    MAPLIBRE_TEST_CHECK(backfilled.textureId != isolated.textureId);
    MAPLIBRE_TEST_CHECK(backfilled.pixels != isolated.pixels);
    MAPLIBRE_TEST_CHECK(backfilled.vertices == isolated.vertices && backfilled.indices == isolated.indices);
    MAPLIBRE_TEST_CHECK(backfilled.drawableUBO == isolated.drawableUBO && backfilled.tilePropsUBO == isolated.tilePropsUBO);
    MAPLIBRE_TEST_CHECK(backfilled.textureWidth == isolated.textureWidth && backfilled.textureHeight == isolated.textureHeight);
    MAPLIBRE_TEST_CHECK(backfilled.textureChannels == isolated.textureChannels && backfilled.textureFilter == isolated.textureFilter);
    for (uint32_t y = 1; y <= demSize; ++y) {
        const auto row = (y * backfilled.textureWidth + 1) * 4;
        MAPLIBRE_TEST_CHECK(std::memcmp(backfilled.pixels.data() + row, isolated.pixels.data() + row, demSize * 4) == 0);
    }
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
