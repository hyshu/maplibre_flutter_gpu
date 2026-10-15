#include "bridge_session.hpp"

#include <mln/actor/scheduler.hpp>
#include <mln/gfx/backend_scope.hpp>
#include <mln/gfx/context.hpp>
#include <mln/gfx/renderer_backend.hpp>
#include <mln/renderer/renderer.hpp>
#include <mln/renderer/tile_parameters.hpp>
#include <mln/renderer/tile_pyramid.hpp>
#include <mln/renderer/tile_render_data.hpp>
#include <mln/style/source_impl.hpp>
#include <mln/tile/geometry_tile.hpp>
#include <mln/tile/tile_cache.hpp>
#include <mln/util/run_loop.hpp>

#include <atomic>
#include <cassert>
#include <cstdio>
#include <limits>

extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
int maplibre_init(int, int, float, const char*);
int maplibre_style_set(const char*);
void maplibre_frame_begin();
int maplibre_render_frame();
void maplibre_frame_end();
uint64_t maplibre_get_physical_memory();
uint64_t maplibre_get_available_memory();
uint64_t maplibre_get_memory_usage();
int maplibre_set_tile_cache_size(uint32_t);
int maplibre_reduce_memory_use();
void maplibre_destroy();
void maplibre_shutdown_all();
}

static std::atomic<size_t> liveTiles{0};

class MemoryTile final : public mln::Tile {
public:
    MemoryTile(const mln::OverscaledTileID& id, mln::TileObserver* observer)
        : Tile(Kind::Geometry, id, "memory", observer) {
        renderable = loaded = true;
        ++liveTiles;
    }
    ~MemoryTile() override { --liveTiles; }
    std::unique_ptr<mln::TileRenderData> createRenderData() override { return nullptr; }
    void cancel() override {}
    bool layerPropertiesUpdated(const mln::Immutable<mln::style::LayerProperties>&) override { return false; }
};

class MemorySource final : public mln::style::Source::Impl {
public:
    MemorySource() : Impl(mln::style::SourceType::Vector, "memory") {}
    std::optional<std::string> getAttribution() const override { return std::nullopt; }
};

static void checkTileRetention() {
    mln::util::RunLoop loop;
    mln::TaggedScheduler threadPool(mln::Scheduler::GetBackground(), mln::util::SimpleIdentity{});
    mln::TransformState transform;
    transform.setSize({512, 512});
    const mln::TileParameters parameters{
        .pixelRatio = 1,
        .debugOptions = {},
        .transformState = transform,
        .fileSource = {},
        .mode = mln::MapMode::Continuous,
        .annotationManager = {},
        .imageManager = {},
        .glyphManager = {},
        .prefetchZoomDelta = 0,
        .threadPool = threadPool,
    };
    MemorySource source;
    {
        mln::TilePyramid pyramid(threadPool);
        pyramid.setCacheSize(2);
        const auto update = [&](double longitude) {
            transform.setLatLngZoom({5, longitude}, 6);
            pyramid.update({}, true, false, parameters, source, 512, {0, 14}, std::nullopt,
                           [](const mln::OverscaledTileID& id, mln::TileObserver* observer) {
                               return std::make_unique<MemoryTile>(id, observer);
                           });
            threadPool.waitForEmpty();
        };
        update(0);
        assert(!pyramid.getTiles().empty());
        update(45);
        update(90);
        assert(liveTiles == pyramid.getTiles().size() + 2);

        const auto activeID = pyramid.getTiles().begin()->first;
        const auto* active = pyramid.getTiles().begin()->second.get();
        pyramid.reduceMemoryUse();
        threadPool.waitForEmpty();
        assert(liveTiles == pyramid.getTiles().size());
        assert(pyramid.getTile(activeID) == active);

        update(120);
        assert(liveTiles == pyramid.getTiles().size() + 2);
        const auto retained = pyramid.getTiles().size();
        pyramid.setCacheSize(0);
        threadPool.waitForEmpty();
        assert(liveTiles == retained);
        update(150);
        assert(liveTiles == pyramid.getTiles().size());

        pyramid.setCacheSize(1);
        update(175);
        assert(liveTiles == pyramid.getTiles().size() + 1);
    }
    threadPool.waitForEmpty();
    assert(liveTiles == 0);
}

static void assertCap(uint32_t cap) {
    bridge_runOnOwnerSync([=] {
        assert(g_frontend->getRenderer()->getTileCacheSize() == cap);
    });
}

static void checkDeferredTilePayloads() {
    bridge_runOnOwnerSync([] {
        auto& backend = *g_frontend->getBackend();
        mln::gfx::BackendScope scope{backend};
        auto& context = backend.getContext();
        auto& threadPool = backend.getThreadPool();
        mln::TransformState transform;
        const mln::TileParameters parameters{
            .pixelRatio = 1,
            .debugOptions = {},
            .transformState = transform,
            .fileSource = {},
            .mode = mln::MapMode::Continuous,
            .annotationManager = {},
            .imageManager = mln::ImageManager::create(),
            .glyphManager = std::make_shared<mln::GlyphManager>(),
            .prefetchZoomDelta = 0,
            .threadPool = threadPool,
            .dynamicTextureAtlas = std::make_shared<mln::gfx::DynamicTextureAtlas>(context),
        };
        mln::TileCache cache(threadPool);
        cache.setSize(0);
        const auto discardTile = [&](std::unique_ptr<mln::TileRenderData>* renderData = nullptr) {
            auto tile = std::make_unique<mln::GeometryTile>(mln::OverscaledTileID{0, 0, 0}, "memory", parameters);
            auto layout = std::make_shared<mln::GeometryTile::LayoutResult>(
                mln::unordered_map<std::string, mln::LayerRenderData>{},
                std::unique_ptr<mln::FeatureIndex>{},
                mln::gfx::GlyphAtlas{},
                mln::gfx::ImageAtlas{},
                parameters.dynamicTextureAtlas);
            std::weak_ptr<mln::GeometryTile::LayoutResult> weakLayout = layout;
            tile->onLayout(std::move(layout), 0);
            if (renderData) {
                *renderData = tile->createRenderData();
            }
            cache.add(tile->id, std::move(tile));
            cache.deferPendingReleases();
            return weakLayout;
        };

        for (int i = 0; i < 32; ++i) {
            const auto payload = discardTile();
            threadPool.waitForEmpty();
            assert(!payload.expired());
            context.beginFrame();
            assert(payload.expired());
            context.endFrame();
        }

        std::unique_ptr<mln::TileRenderData> renderData;
        const auto displayed = discardTile(&renderData);
        threadPool.waitForEmpty();
        context.performCleanup();
        assert(!displayed.expired());
        renderData.reset();
        assert(displayed.expired());

        const auto pressure = discardTile();
        g_frontend->getRenderer()->reduceMemoryUse();
        assert(pressure.expired());
    });
}

static std::weak_ptr<int> queueDeferredPayload() {
    std::weak_ptr<int> result;
    bridge_runOnOwnerSync([&] {
        auto& threadPool = g_frontend->getBackend()->getThreadPool();
        auto payload = std::make_shared<int>(1);
        result = payload;
        threadPool.schedule([threadPool, payload = std::move(payload)]() mutable {
            threadPool.runOnRenderThread([payload = std::move(payload)] {});
        });
    });
    return result;
}

int main() {
    assert(maplibre_get_physical_memory() > 0);
    assert(maplibre_get_available_memory() > 0);
    assert(maplibre_get_memory_usage() > 0);
    checkTileRetention();

    constexpr auto automatic = std::numeric_limits<uint32_t>::max();
    constexpr const char* style = R"({"version":8,"sources":{},"layers":[]})";
    auto* first = maplibre_session_create();
    auto* second = maplibre_session_create();
    assert(first && second);
    maplibre_session_select(first);
    assert(maplibre_reduce_memory_use() == 0);
    assert(maplibre_init(256, 256, 1, style) == 0);
    checkDeferredTilePayloads();
    assertCap(automatic);
    assert(maplibre_set_tile_cache_size(4) == 1);
    assertCap(4);
    maplibre_frame_begin();
    assert(maplibre_render_frame() == 0);
    maplibre_frame_end();
    const auto metadata = g_mapTransformMetadata;
    assert(maplibre_reduce_memory_use() == 1);
    assert(g_mapTransformMetadata.valid == metadata.valid);
    assert(g_mapTransformMetadata.worldSize == metadata.worldSize);

    maplibre_session_select(second);
    assert(maplibre_init(256, 256, 1, style) == 0);
    assertCap(automatic);
    assert(maplibre_set_tile_cache_size(1) == 1);
    const auto secondPayload = queueDeferredPayload();
    maplibre_session_select(first);
    assertCap(4);
    assert(maplibre_reduce_memory_use() == 1);
    assert(!secondPayload.expired());
    assert(maplibre_style_set(style) == 1);
    assertCap(4);
    const auto destroyedPayload = queueDeferredPayload();
    maplibre_destroy();
    assert(destroyedPayload.expired());
    assert(!secondPayload.expired());
    assert(maplibre_set_tile_cache_size(0) == 0);
    assert(maplibre_reduce_memory_use() == 0);
    assert(maplibre_init(256, 256, 1, style) == 0);
    assertCap(automatic);
    maplibre_destroy();
    maplibre_session_release(first);
    maplibre_session_select(second);
    assertCap(1);
    assert(maplibre_reduce_memory_use() == 1);
    assert(secondPayload.expired());
    maplibre_destroy();
    maplibre_session_release(second);
    maplibre_shutdown_all();
    std::puts("Native memory pressure, tile retention, and session isolation passed");
}
