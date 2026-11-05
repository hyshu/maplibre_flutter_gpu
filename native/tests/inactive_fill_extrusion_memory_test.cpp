#include <cassert>
#include <cstdint>
#include <cstdio>
#include <map>
#include <memory>
#include <vector>

#if TEST_ANDROID
#define __ANDROID__ 1
#endif
#define MLN_RENDER_BACKEND_COMMAND_EXPORT TEST_COMMAND_EXPORT

template <class T>
std::shared_ptr<T> makeMutable() {
    return std::make_shared<T>();
}

namespace style {
struct FillExtrusionLayer {
    struct Impl {
        static const void* staticTypeInfo() {
            static const int token = 0;
            return &token;
        }
    };
};
}

struct LayerImpl {
    const void* type = nullptr;
    const void* getTypeInfo() const { return type; }
};

struct RenderTile {
    std::shared_ptr<std::vector<uint8_t>> payload;
};

struct TileLayerGroup {
    std::shared_ptr<std::vector<const RenderTile*>> stencilTiles;
    void setStencilTiles(std::shared_ptr<std::vector<const RenderTile*>> value) {
        stencilTiles = std::move(value);
    }
};

struct Layer {
    virtual ~Layer() = default;
    std::shared_ptr<LayerImpl> baseImpl = std::make_shared<LayerImpl>();
};

struct RenderFillExtrusionLayer : Layer {
    bool active = false;
    std::shared_ptr<std::vector<RenderTile>> renderTilesOwner = makeMutable<std::vector<RenderTile>>();
    std::shared_ptr<std::vector<const RenderTile*>> renderTiles;
    std::vector<std::shared_ptr<std::vector<RenderTile>>> drawables;
    std::vector<int> renderTileIDs;
    std::vector<int> newRenderTileIDs;
    std::unique_ptr<TileLayerGroup> layerGroup = std::make_unique<TileLayerGroup>();

    RenderFillExtrusionLayer() {
        baseImpl->type = style::FillExtrusionLayer::Impl::staticTypeInfo();
    }

    bool isLayerRenderable() const { return active; }
    size_t removeAllDrawables() {
        const auto removed = drawables.size();
        drawables.clear();
        return removed;
    }
    size_t releaseInactiveRenderData();

    std::weak_ptr<std::vector<uint8_t>> populate() {
        auto payload = std::make_shared<std::vector<uint8_t>>(1024 * 1024, 42);
        renderTilesOwner = makeMutable<std::vector<RenderTile>>();
        renderTilesOwner->push_back({payload});
        renderTiles = std::make_shared<std::vector<const RenderTile*>>();
        renderTiles->push_back(&renderTilesOwner->front());
        layerGroup->setStencilTiles(renderTiles);
        drawables = {renderTilesOwner, renderTilesOwner};
        renderTileIDs = {1};
        newRenderTileIDs = {2};
        return payload;
    }
};

struct RenderOrchestrator {
    uint32_t tileCacheSize = UINT32_MAX;
    std::map<int, std::unique_ptr<Layer>> renderLayers;
    void releaseInactiveFillExtrusionData();
};

#include "inactive_fill_extrusion.inc"

int main() {
    RenderOrchestrator orchestrator;
    auto owned = std::make_unique<RenderFillExtrusionLayer>();
    auto& layer = *owned;
    orchestrator.renderLayers.emplace(1, std::move(owned));
    orchestrator.renderLayers.emplace(2, std::make_unique<Layer>());

    const auto retained = layer.populate();
    orchestrator.releaseInactiveFillExtrusionData();
    assert(!retained.expired());
    orchestrator.tileCacheSize = 8;
    orchestrator.releaseInactiveFillExtrusionData();
    assert(!retained.expired());

    layer.active = true;
    orchestrator.tileCacheSize = 0;
    orchestrator.releaseInactiveFillExtrusionData();
    assert(!retained.expired());
    assert(layer.drawables.size() == 2);
    assert(retained.lock()->front() == 42);

    layer.active = false;
    orchestrator.releaseInactiveFillExtrusionData();
#if TEST_ANDROID && TEST_COMMAND_EXPORT
    assert(retained.expired());
    assert(layer.drawables.empty());
    assert(!layer.renderTiles && layer.renderTilesOwner->empty());
    assert(layer.renderTileIDs.empty() && layer.newRenderTileIDs.empty());
    assert(!layer.layerGroup->stencilTiles);
#else
    assert(!retained.expired());
    assert(layer.releaseInactiveRenderData() == 2);
    assert(retained.expired());
#endif
    assert(layer.releaseInactiveRenderData() == 0);

    layer.active = true;
    const auto reappeared = layer.populate();
    orchestrator.releaseInactiveFillExtrusionData();
    assert(!reappeared.expired());
    assert(layer.drawables.size() == 2);

    orchestrator.tileCacheSize = 4;
    layer.active = false;
    orchestrator.releaseInactiveFillExtrusionData();
    assert(!reappeared.expired());
    assert(layer.releaseInactiveRenderData() == 2);
    assert(reappeared.expired());
    std::puts("Inactive FE ownership, cache policy, and platform guards passed");
}
