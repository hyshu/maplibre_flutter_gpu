// Published labels and reusable extraction caches belong to one map session.
#pragma once

#if MLN_RENDER_BACKEND_COMMAND_EXPORT

#include "label_encoding.hpp"
#include "label_paint.hpp"

#include <unordered_map>

#include <mln/util/mat4.hpp>

namespace maplibre_bridge::labels {

uint64_t hashBytes(uint64_t hash, const void* data, std::size_t size);
uint64_t hashString(uint64_t hash, const std::string& value);

template <typename T>
uint64_t hashValue(uint64_t hash, const T& value) {
    return hashBytes(hash, &value, sizeof(value));
}

struct PendingLabel {
    LabelExport label{};
    const mln::PlacedSymbolData* symbol = nullptr;
    const std::string* layer = nullptr;
    std::size_t frameSymbolIndex = 0;
    uint64_t layerHash = 0;
};

struct PathRefs {
    uint32_t textOffset = 0;
    uint32_t textCount = 0;
    uint32_t iconOffset = 0;
    uint32_t iconCount = 0;
};

// Static symbol content is immutable for the lifetime of a bucket instance.
struct SymbolContentKey {
    uint32_t bucketInstanceID = 0;
    uint32_t symbolInstanceIndex = 0;
    uint32_t crossTileID = 0;

    bool operator==(const SymbolContentKey& other) const {
        return bucketInstanceID == other.bucketInstanceID &&
               symbolInstanceIndex == other.symbolInstanceIndex && crossTileID == other.crossTileID;
    }
};

struct SymbolContentKeyHash {
    std::size_t operator()(const SymbolContentKey& key) const {
        constexpr uint64_t offset = 1469598103934665603ull;
        auto hash = hashValue(offset, key.bucketInstanceID);
        hash = hashValue(hash, key.symbolInstanceIndex);
        return static_cast<std::size_t>(hashValue(hash, key.crossTileID));
    }
};

SymbolContentKey contentKey(const mln::PlacedSymbolData& symbol);

struct SymbolContentCacheEntry {
    uint64_t hash = 0;
    uint64_t lastSeenGeneration = 0;
};

struct FrameSymbolScratch {
    const mln::PlacedSymbolData* symbol = nullptr;
    SymbolContentKey key{};
    uint64_t sharedHash = 0;
    StaticContentRefs staticRefs{};
    PathRefs pathRefs{};
    bool pathsAppended = false;
};

struct LayerMetadata {
    int32_t index = std::numeric_limits<int32_t>::max();
    uint64_t hash = 0;
    std::size_t paintPlanIndex = std::numeric_limits<std::size_t>::max();
};

struct FeatureStateKey {
    std::string source;
    std::string sourceLayer;
    std::string feature;

    bool operator==(const FeatureStateKey& other) const {
        return source == other.source && sourceLayer == other.sourceLayer && feature == other.feature;
    }
};

struct FeatureStateKeyHash {
    std::size_t operator()(const FeatureStateKey& key) const {
        constexpr uint64_t offset = 1469598103934665603ull;
        auto hash = hashString(offset, key.source);
        hash = hashString(hash, key.sourceLayer);
        return static_cast<std::size_t>(hashString(hash, key.feature));
    }
};

struct PaintTranslationKey {
    std::size_t layerPlanIndex = 0;
    int16_t tileWrap = 0;
    uint8_t canonicalZ = 0;
    uint8_t component = 0;
    uint32_t canonicalX = 0;
    uint32_t canonicalY = 0;

    bool operator==(const PaintTranslationKey& other) const {
        return layerPlanIndex == other.layerPlanIndex && tileWrap == other.tileWrap &&
               canonicalZ == other.canonicalZ && component == other.component &&
               canonicalX == other.canonicalX && canonicalY == other.canonicalY;
    }
};

struct PaintTranslationKeyHash {
    std::size_t operator()(const PaintTranslationKey& key) const {
        constexpr uint64_t offset = 1469598103934665603ull;
        auto hash = hashValue(offset, key.layerPlanIndex);
        hash = hashValue(hash, key.tileWrap);
        hash = hashValue(hash, key.canonicalZ);
        hash = hashValue(hash, key.component);
        hash = hashValue(hash, key.canonicalX);
        return static_cast<std::size_t>(hashValue(hash, key.canonicalY));
    }
};

struct PaintTranslationMatrices {
    mln::mat4 tile;
    mln::mat4 translated;
};

struct BucketLayerPlanCacheEntry {
    // Plan indices are rebuilt before an entry is read in a new extraction generation.
    std::vector<std::size_t> plans;
    uint64_t lastSeenGeneration = 0;
};

struct LabelSessionState {
    std::vector<LabelStaticExport> staticLabels;
    std::vector<uint8_t> staticBlob;
    std::vector<uint64_t> staticContentHashes;
    uint32_t staticVersion = 0;
    uint32_t staticContentVersion = 0;
    std::vector<LabelDynamicExport> dynamicLabels;
    std::vector<uint8_t> dynamicBlob;
    uint32_t dynamicVersion = 0;
    std::vector<LabelExport> labels;
    std::vector<uint8_t> blob;
    uint32_t version = 0;
    bool legacyDirty = false;

    std::vector<PendingLabel> pending;
    std::vector<FrameSymbolScratch> frameSymbols;
    std::vector<LabelStaticExport> scratchStaticLabels;
    std::vector<uint8_t> scratchStaticBlob;
    std::vector<uint64_t> scratchContentHashes;
    std::vector<std::size_t> order;
    std::vector<LabelDynamicExport> scratchDynamicLabels;
    std::vector<uint8_t> scratchDynamicBlob;
    std::string utf8Scratch;
    std::vector<LabelStringRefExport> fontRefScratch;
    std::vector<LabelTextSectionExport> sectionScratch;
    std::unordered_map<SymbolContentKey, SymbolContentCacheEntry, SymbolContentKeyHash> contentHashCache;
    uint64_t contentCacheGeneration = 0;
    std::vector<std::string> layerOrder;
    std::unordered_map<std::string, LayerMetadata> layerMetadata;
    std::vector<LayerPaintPlan> layerPaintPlans;
    std::unordered_map<uint32_t, BucketLayerPlanCacheEntry> bucketLayerPlans;
    std::vector<std::size_t> uncachedLayerPlans;
    std::unordered_map<FeatureStateKey, mln::FeatureState, FeatureStateKeyHash> featureStates;
    mln::FeatureState emptyFeatureState;
    std::unordered_map<PaintTranslationKey,
                       PaintTranslationMatrices,
                       PaintTranslationKeyHash>
        paintTranslationMatrices;

    void beginFrame();

    uint64_t cachedSharedContentHash(FrameSymbolScratch& frameSymbol);

    void pruneContentHashCache();

    void pruneBucketLayerPlans();

    void materializeLegacy();
};

LabelSessionState& labelSession();

// Publishes only changed bytes and keeps unchanged exported pointers stable.
void publishPendingLabels();

} // namespace maplibre_bridge::labels

#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT
