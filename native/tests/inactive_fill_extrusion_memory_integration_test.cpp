#include "bridge_state.hpp"
#include "command_frame_test_support.hpp"

#include <mln/actor/scheduler.hpp>
#include <mln/geometry/line_atlas.hpp>
#include <mln/renderer/buckets/debug_bucket.hpp>
#include <mln/renderer/image_manager.hpp>
#include <mln/renderer/layers/render_fill_extrusion_layer.hpp>
#include <mln/renderer/paint_parameters.hpp>
#include <mln/renderer/pattern_atlas.hpp>
#include <mln/renderer/render_tile.hpp>
#include <mln/renderer/sources/render_tile_source.hpp>
#include <mln/renderer/tile_render_data.hpp>
#include <mln/style/source_impl.hpp>
#include <mln/tile/tile.hpp>
#include <mln/util/run_loop.hpp>

#include <algorithm>
#include <chrono>
#include <compare>
#include <cstdio>
#include <cstring>
#include <thread>
#include <vector>

extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
int maplibre_init(int, int, float, const char*);
void maplibre_set_camera_full(double, double, double, double, double);
void maplibre_frame_begin();
int maplibre_render_frame();
void maplibre_frame_end();
int maplibre_set_tile_cache_size(uint32_t);
int maplibre_reduce_memory_use();
void maplibre_destroy();
void maplibre_shutdown_all();
}

using namespace mln;
using namespace mln::command_export;

class OwnedTileData final : public TileRenderData {
public:
    explicit OwnedTileData(std::shared_ptr<int> payload_) : payload(std::move(payload_)) {}
    const LayerRenderData* getLayerRenderData(const style::Layer::Impl&) const override { return nullptr; }
private:
    std::shared_ptr<int> payload;
};

class OwnedTile final : public Tile {
public:
    explicit OwnedTile(std::shared_ptr<int> payload_)
        : Tile(Kind::Geometry, OverscaledTileID{0, 0, 0}, "memory"), payload(std::move(payload_)) {
        renderable = loaded = true;
    }
    std::unique_ptr<TileRenderData> createRenderData() override {
        return std::make_unique<OwnedTileData>(payload);
    }
    void cancel() override {}
    bool layerPropertiesUpdated(const Immutable<style::LayerProperties>&) override { return false; }
private:
    std::shared_ptr<int> payload;
};

class MemorySourceImpl final : public style::Source::Impl {
public:
    MemorySourceImpl() : Impl(style::SourceType::Vector, "memory") {}
    std::optional<std::string> getAttribution() const override { return std::nullopt; }
};

class MemorySource final : public RenderTileSource {
public:
    explicit MemorySource(const TaggedScheduler& scheduler)
        : RenderTileSource(makeMutable<MemorySourceImpl>(), scheduler) {
        enabled = true;
    }
    void update(Immutable<style::Source::Impl>, const std::vector<Immutable<style::LayerProperties>>&,
                bool, bool, const TileParameters&) override {}
    void retain(OwnedTile& tile, const SourcePrepareParameters& parameters) {
        auto tiles = makeMutable<std::vector<RenderTile>>();
        tiles->emplace_back(UnwrappedTileID{0, CanonicalTileID{0, 0, 0}}, tile);
        tiles->back().prepare(parameters);
        renderTiles = std::move(tiles);
        filteredRenderTiles.reset();
    }
    void forget() {
        filteredRenderTiles.reset();
        renderTilesSortedByY.reset();
        renderTiles = makeMutable<std::vector<RenderTile>>();
    }
};

static void checkRealLayerOwnership() {
    util::RunLoop loop;
    TaggedScheduler scheduler(Scheduler::GetBackground(), util::SimpleIdentity{});
    MemorySource source(scheduler);
    TransformState transform;
    transform.setSize({256, 256});
    transform.setLatLngZoom({0, 0}, 0);
    TransformParameters transformParameters(transform);
    const auto images = ImageManager::create();
    PatternAtlas patterns;
    LineAtlas lines;
    const MapDebugOptions debug = MapDebugOptions::NoDebug;
    const SourcePrepareParameters sourceParameters{transformParameters, debug, *images, "memory"};
    const LayerPrepareParameters layerParameters{&source, *images, patterns, lines, transform};
    style::FillExtrusionLayer definition("building", "memory");
    RenderFillExtrusionLayer layer(staticImmutableCast<style::FillExtrusionLayer::Impl>(definition.baseImpl));
    UniqueChangeRequestVec changes;

    const auto prepare = [&] {
        auto payload = std::make_shared<int>(42);
        std::weak_ptr<int> weak = payload;
        auto tile = std::make_unique<OwnedTile>(std::move(payload));
        source.retain(*tile, sourceParameters);
        layer.prepare(layerParameters);
        source.forget();
        tile.reset();
        return weak;
    };

    layer.markLayerRenderable(true, changes);
    const auto retained = prepare();
    MAPLIBRE_TEST_CHECK(!retained.expired());
    layer.releaseInactiveRenderData();
    MAPLIBRE_TEST_CHECK(!retained.expired());
    layer.markLayerRenderable(false, changes);
    MAPLIBRE_TEST_CHECK(!retained.expired());
    layer.releaseInactiveRenderData();
    MAPLIBRE_TEST_CHECK(retained.expired());
    MAPLIBRE_TEST_CHECK(layer.releaseInactiveRenderData() == 0);

    layer.markLayerRenderable(true, changes);
    const auto reappeared = prepare();
    layer.releaseInactiveRenderData();
    MAPLIBRE_TEST_CHECK(!reappeared.expired());
    layer.markLayerRenderable(false, changes);
    layer.releaseInactiveRenderData();
    MAPLIBRE_TEST_CHECK(reappeared.expired());
}

static constexpr const char* styleJSON = R"JSON({
  "version": 8,
  "transition": {"duration": 0, "delay": 0},
  "sources": {
    "ground": {"type": "geojson", "data": {"type": "Feature", "properties": {},
      "geometry": {"type": "Polygon", "coordinates": [
        [[0.9998,0.9998],[1.0002,0.9998],[1.0002,1.0002],[0.9998,1.0002],[0.9998,0.9998]]
      ]}}},
    "buildings": {"type": "geojson", "data": {"type": "Feature", "properties": {"height": 60},
      "geometry": {"type": "Polygon", "coordinates": [
        [[0.9998,0.9998],[1.0002,0.9998],[1.0002,1.0002],[0.9998,1.0002],[0.9998,0.9998]]
      ]}}}
  },
  "layers": [
    {"id": "background", "type": "background", "paint": {"background-color": "white"}},
    {"id": "ground", "type": "fill", "source": "ground", "paint": {"fill-color": "blue"}},
    {"id": "building", "type": "fill-extrusion", "source": "buildings", "minzoom": 14.5,
     "paint": {"fill-extrusion-height": ["get", "height"], "fill-extrusion-color": "gray",
               "fill-extrusion-opacity": 0.85}}
  ]
})JSON";

struct ExportedGeometry {
    uint32_t shader;
    uint32_t layer;
    uint32_t flags;
    std::vector<uint8_t> vertices;
    std::vector<uint8_t> indices;
    std::vector<uint8_t> paint;
    auto operator<=>(const ExportedGeometry&) const = default;
};

static std::vector<ExportedGeometry> geometryFor(ShaderType shader) {
    const auto* frame = maplibre_frame_get_metadata();
    const auto* commands = static_cast<const DrawCommand*>(frame->commands);
    std::vector<ExportedGeometry> result;
    for (int index = 0; index < frame->commandCount; ++index) {
        const auto& command = commands[index];
        if (command.shaderType != shader) continue;
        ExportedGeometry geometry{static_cast<uint32_t>(shader), command.layerIndex, command.flags, {}, {}, {}};
        const auto* vertices = static_cast<const uint8_t*>(command.vertexData);
        geometry.vertices.assign(vertices, vertices + command.vertexCount * command.vertexStride);
        const auto* indices = reinterpret_cast<const uint8_t*>(command.indexData);
        geometry.indices.assign(indices, indices + command.indexCount * sizeof(uint16_t));
        const auto payload = payloadFor(command);
        geometry.paint.assign(payload.propsUBO.begin(), payload.propsUBO.end());
        result.push_back(std::move(geometry));
    }
    std::sort(result.begin(), result.end());
    return result;
}

static void render() {
    maplibre_frame_begin();
    MAPLIBRE_TEST_CHECK(maplibre_render_frame() == 0);
    maplibre_frame_end();
}

static void awaitBuildings(bool visible) {
    for (int attempt = 0; attempt < 500; ++attempt) {
        render();
        const auto loaded = bridge_runOnOwnerSync([] { return g_map && g_map->isFullyLoaded(); });
        if (loaded && !geometryFor(ShaderType::Fill).empty() &&
            geometryFor(ShaderType::FillExtrusion).empty() != visible) return;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    MAPLIBRE_TEST_CHECK(false && "Expected building visibility did not settle");
}

int main() {
    checkRealLayerOwnership();
    auto* session = maplibre_session_create();
    MAPLIBRE_TEST_CHECK(session);
    maplibre_session_select(session);
    MAPLIBRE_TEST_CHECK(maplibre_init(392, 788, 2.75f, styleJSON) == 0);
    MAPLIBRE_TEST_CHECK(maplibre_set_tile_cache_size(8) == 1);
    maplibre_set_camera_full(1, 1, 15, 20, 40);
    awaitBuildings(true);
    const auto buildings = geometryFor(ShaderType::FillExtrusion);
    const auto ground = geometryFor(ShaderType::Fill);
    MAPLIBRE_TEST_CHECK(!buildings.empty() && !ground.empty());

    MAPLIBRE_TEST_CHECK(maplibre_set_tile_cache_size(0) == 1);
    MAPLIBRE_TEST_CHECK(maplibre_reduce_memory_use() == 1);
    for (int frame = 0; frame < 20; ++frame) {
        render();
        MAPLIBRE_TEST_CHECK(geometryFor(ShaderType::FillExtrusion) == buildings);
    }
    for (const uint32_t cap : {0u, 8u, 0u}) {
        MAPLIBRE_TEST_CHECK(maplibre_set_tile_cache_size(cap) == 1);
        maplibre_set_camera_full(1, 1, 13, 20, 40);
        awaitBuildings(false);
        MAPLIBRE_TEST_CHECK(maplibre_reduce_memory_use() == 1);
        render();
        MAPLIBRE_TEST_CHECK(geometryFor(ShaderType::FillExtrusion).empty());
        maplibre_set_camera_full(1, 1, 15, 20, 40);
        awaitBuildings(true);
        MAPLIBRE_TEST_CHECK(geometryFor(ShaderType::FillExtrusion) == buildings);
        MAPLIBRE_TEST_CHECK(geometryFor(ShaderType::Fill) == ground);
    }
    maplibre_destroy();
    maplibre_session_release(session);
    maplibre_shutdown_all();
    std::puts("Real FE tile ownership and visible-hidden-visible geometry passed");
}
