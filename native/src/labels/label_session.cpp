#include "label_session.hpp"

#if MLN_RENDER_BACKEND_COMMAND_EXPORT

#include "../bridge_state.hpp"

#include <algorithm>
#include <cstring>
#include <map>
#include <type_traits>

namespace maplibre_bridge::labels {

uint64_t hashBytes(uint64_t hash, const void* data, std::size_t size) {
    constexpr uint64_t prime = 1099511628211ull;
    const auto* bytes = static_cast<const uint8_t*>(data);
    for (std::size_t i = 0; i < size; ++i) {
        hash ^= bytes[i];
        hash *= prime;
    }
    return hash;
}

uint64_t hashString(uint64_t hash, const std::string& value) {
    hash = hashValue(hash, value.size());
    return hashBytes(hash, value.data(), value.size());
}

uint64_t hashString(uint64_t hash, const std::u16string& value) {
    hash = hashValue(hash, value.size());
    return hashBytes(hash, value.data(), value.size() * sizeof(char16_t));
}

uint64_t hashFonts(uint64_t hash, const mbgl::FontStack& fonts) {
    hash = hashValue(hash, fonts.size());
    for (const auto& font : fonts) hash = hashString(hash, font);
    return hash;
}

uint64_t hashSections(uint64_t hash,
                      const std::vector<mbgl::ShapingTextSection>& sections,
                      const mbgl::FontStack& fallbackFonts,
                      std::size_t fallbackLength) {
    const std::size_t count = sections.empty() && fallbackLength > 0 ? 1 : sections.size();
    hash = hashValue(hash, count);
    if (sections.empty()) {
        if (fallbackLength == 0) return hash;
        const uint32_t start = 0;
        const auto end = static_cast<uint32_t>(fallbackLength);
        const double scale = 1.0;
        hash = hashValue(hash, start);
        hash = hashValue(hash, end);
        hash = hashValue(hash, scale);
        return hashFonts(hash, fallbackFonts);
    }
    for (const auto& section : sections) {
        hash = hashValue(hash, section.start);
        hash = hashValue(hash, section.end);
        hash = hashValue(hash, section.scale);
        hash = hashFonts(hash, section.fontStack.empty() ? fallbackFonts : section.fontStack);
        const bool hasColor = section.textColor.has_value();
        hash = hashValue(hash, hasColor);
        if (section.textColor) hash = hashValue(hash, *section.textColor);
        const bool hasImage = section.imageID.has_value();
        hash = hashValue(hash, hasImage);
        if (section.imageID) hash = hashString(hash, *section.imageID);
    }
    return hash;
}

uint64_t sharedContentHash(const mbgl::PlacedSymbolData& symbol) {
    constexpr uint64_t offset = 1469598103934665603ull;
    const auto& visual = visualText(symbol);
    const auto& logical = logicalText(symbol);
    auto hash = hashValue(offset, symbol.bucketInstanceID);
    hash = hashValue(hash, symbol.symbolInstanceIndex);
    hash = hashValue(hash, symbol.crossTileID);
    hash = hashString(hash, visual);
    hash = hashString(hash, logical);
    hash = hashString(hash, symbol.icon);
    hash = hashFonts(hash, symbol.textFontStack);
    hash = hashSections(hash, symbol.textSections, symbol.textFontStack, logical.size());
    return hashSections(hash, symbol.visualTextSections, symbol.textFontStack, visual.size());
}

SymbolContentKey contentKey(const mbgl::PlacedSymbolData& symbol) {
    return {symbol.bucketInstanceID, symbol.symbolInstanceIndex, symbol.crossTileID};
}

uint64_t contentHash(const PendingLabel& pending, uint64_t sharedHash) {
    return hashValue(sharedHash, pending.layerHash);
}

template <typename T>
bool sameRecords(const std::vector<T>& lhs, const std::vector<T>& rhs) {
    static_assert(std::is_trivially_copyable_v<T>);
    return lhs.size() == rhs.size() &&
           (lhs.empty() || std::memcmp(lhs.data(), rhs.data(), lhs.size() * sizeof(T)) == 0);
}

template <typename T>
void releaseStorage(T& value) {
    T{}.swap(value);
}

void LabelSessionState::beginFrame() {
    pending.clear();
    frameSymbols.clear();
    layerPaintPlans.clear();
    uncachedLayerPlans.clear();
    featureStates.clear();
    paintTranslationMatrices.clear();
    if (++contentCacheGeneration == 0) {
        contentHashCache.clear();
        bucketLayerPlans.clear();
        contentCacheGeneration = 1;
    }
}

uint64_t LabelSessionState::cachedSharedContentHash(FrameSymbolScratch& frameSymbol) {
    // Bucket identity is only populated by continuous placement.
    if (frameSymbol.key.bucketInstanceID == 0) {
        frameSymbol.sharedHash = sharedContentHash(*frameSymbol.symbol);
        return frameSymbol.sharedHash;
    }
    auto found = contentHashCache.find(frameSymbol.key);
    if (found == contentHashCache.end()) {
        found = contentHashCache
                    .emplace(frameSymbol.key,
                             SymbolContentCacheEntry{
                                 sharedContentHash(*frameSymbol.symbol),
                                 contentCacheGeneration,
                             })
                    .first;
    } else {
        found->second.lastSeenGeneration = contentCacheGeneration;
    }
    frameSymbol.sharedHash = found->second.hash;
    return frameSymbol.sharedHash;
}

void LabelSessionState::pruneContentHashCache() {
    constexpr uint64_t retainedGenerations = 2;
    const auto minimumGeneration = contentCacheGeneration > retainedGenerations
                                       ? contentCacheGeneration - retainedGenerations
                                       : 0;
    const auto maxRetained = std::max<std::size_t>(1024, frameSymbols.size() * 2);
    if (contentHashCache.size() <= maxRetained && contentCacheGeneration % 64 != 0) return;
    for (auto item = contentHashCache.begin(); item != contentHashCache.end();) {
        const bool expired = item->second.lastSeenGeneration < minimumGeneration;
        const bool overLimit = contentHashCache.size() > maxRetained &&
                               item->second.lastSeenGeneration != contentCacheGeneration;
        if (expired || overLimit) {
            item = contentHashCache.erase(item);
        } else {
            ++item;
        }
    }
}

void LabelSessionState::pruneBucketLayerPlans() {
    constexpr uint64_t retainedGenerations = 2;
    const auto minimumGeneration = contentCacheGeneration > retainedGenerations
                                       ? contentCacheGeneration - retainedGenerations
                                       : 0;
    const auto maxRetained = std::max<std::size_t>(1024, frameSymbols.size() * 2);
    if (bucketLayerPlans.size() <= maxRetained && contentCacheGeneration % 64 != 0) return;
    for (auto item = bucketLayerPlans.begin(); item != bucketLayerPlans.end();) {
        const bool expired = item->second.lastSeenGeneration < minimumGeneration;
        const bool overLimit = bucketLayerPlans.size() > maxRetained &&
                               item->second.lastSeenGeneration != contentCacheGeneration;
        if (expired || overLimit) {
            item = bucketLayerPlans.erase(item);
        } else {
            ++item;
        }
    }
}

void LabelSessionState::materializeLegacy() {
    if (!legacyDirty) return;
    labels.clear();
    blob.clear();
    blob.reserve(staticBlob.size() + alignof(LabelPathPointExport) - 1 + dynamicBlob.size());
    blob.insert(blob.end(), staticBlob.begin(), staticBlob.end());
    alignBlob(blob, alignof(LabelPathPointExport));
    const auto dynamicBase = static_cast<uint32_t>(blob.size());
    blob.insert(blob.end(), dynamicBlob.begin(), dynamicBlob.end());
    labels.reserve(dynamicLabels.size());
    for (const auto& dynamic : dynamicLabels) {
        if (dynamic.staticIndex >= staticLabels.size()) continue;
        auto label = legacyRecord(staticLabels[dynamic.staticIndex], dynamic);
        if (label.textPathCount > 0) label.textPathOffset += dynamicBase;
        if (label.iconPathCount > 0) label.iconPathOffset += dynamicBase;
        labels.push_back(label);
    }
    legacyDirty = false;
}

std::map<void*, LabelSessionState> g_labelSessions;
LabelSessionState& labelSession() {
    return g_labelSessions[bridge_currentSession()];
}

#define g_labels labelSession().labels
#define g_labelBlob labelSession().blob
#define g_labelsVersion labelSession().version

void publishPendingLabels() {
    auto& session = labelSession();
    const auto& pending = session.pending;
    auto& staticLabels = session.scratchStaticLabels;
    auto& contentHashes = session.scratchContentHashes;
    staticLabels.clear();
    contentHashes.clear();
    staticLabels.reserve(pending.size());
    contentHashes.reserve(pending.size());
    for (auto& frameSymbol : session.frameSymbols) {
        session.cachedSharedContentHash(frameSymbol);
    }
    for (const auto& item : pending) {
        staticLabels.push_back(staticRecord(item.label));
        contentHashes.push_back(
            contentHash(item, session.frameSymbols[item.frameSymbolIndex].sharedHash));
    }

    const bool contentChanged = contentHashes != session.staticContentHashes;
    auto& staticBlob = session.scratchStaticBlob;
    staticBlob.clear();
    if (contentChanged) {
        staticBlob.reserve(session.staticBlob.size());
        for (auto& frameSymbol : session.frameSymbols) {
            frameSymbol.staticRefs = appendStaticContent(staticBlob,
                                                         *frameSymbol.symbol,
                                                         session.utf8Scratch,
                                                         session.fontRefScratch,
                                                         session.sectionScratch);
        }
        for (std::size_t i = 0; i < pending.size(); ++i) {
            const auto& item = pending[i];
            applyStaticContent(staticLabels[i],
                               staticBlob,
                               *item.layer,
                               session.frameSymbols[item.frameSymbolIndex].staticRefs);
        }
    } else {
        for (std::size_t i = 0; i < staticLabels.size(); ++i) {
            copyContentRefs(staticLabels[i], session.staticLabels[i]);
        }
    }
    const bool staticChanged = contentChanged || !sameRecords(staticLabels, session.staticLabels);
    if (staticChanged) {
        // The previous published allocation becomes scratch for the next frame.
        session.staticLabels.swap(staticLabels);
        ++session.staticVersion;
    }
    if (contentChanged) {
        session.staticBlob.swap(staticBlob);
        session.staticContentHashes.swap(contentHashes);
        ++session.staticContentVersion;
    }

    auto& order = session.order;
    order.clear();
    order.reserve(pending.size());
    for (std::size_t i = 0; i < pending.size(); ++i) order.push_back(i);
    std::sort(order.begin(), order.end(), [&](std::size_t lhs, std::size_t rhs) {
        const auto& left = pending[lhs].label;
        const auto& right = pending[rhs].label;
        if (left.layerIndex != right.layerIndex) return left.layerIndex < right.layerIndex;
        if (left.renderGroup != right.renderGroup) return left.renderGroup < right.renderGroup;
        if (left.renderOrder != right.renderOrder) return left.renderOrder < right.renderOrder;
        return lhs < rhs;
    });

    auto& dynamicLabels = session.scratchDynamicLabels;
    auto& dynamicBlob = session.scratchDynamicBlob;
    dynamicLabels.clear();
    dynamicBlob.clear();
    dynamicLabels.reserve(pending.size());
    dynamicBlob.reserve(session.dynamicBlob.size());
    for (const auto staticIndex : order) {
        const auto& item = pending[staticIndex];
        auto record = dynamicRecord(item.label, static_cast<uint32_t>(staticIndex));
        auto& frameSymbol = session.frameSymbols[item.frameSymbolIndex];
        if (!frameSymbol.pathsAppended) {
            frameSymbol.pathRefs = {
                .textOffset = appendPath(
                    dynamicBlob,
                    item.symbol->textPath,
                    item.label.textOffsetX,
                    item.label.textOffsetY),
                .textCount = static_cast<uint32_t>(item.symbol->textPath.size()),
                .iconOffset = appendPath(
                    dynamicBlob,
                    item.symbol->iconPath,
                    item.label.iconOffsetX,
                    item.label.iconOffsetY),
                .iconCount = static_cast<uint32_t>(item.symbol->iconPath.size()),
            };
            frameSymbol.pathsAppended = true;
        }
        record.textPathOffset = frameSymbol.pathRefs.textOffset;
        record.textPathCount = frameSymbol.pathRefs.textCount;
        record.iconPathOffset = frameSymbol.pathRefs.iconOffset;
        record.iconPathCount = frameSymbol.pathRefs.iconCount;
        dynamicLabels.push_back(record);
    }
    const bool dynamicChanged = !sameRecords(dynamicLabels, session.dynamicLabels) ||
                                dynamicBlob != session.dynamicBlob;
    if (dynamicChanged) {
        // Unchanged frames keep the published pointer and contents stable.
        session.dynamicLabels.swap(dynamicLabels);
        session.dynamicBlob.swap(dynamicBlob);
        ++session.dynamicVersion;
    }

    if (staticChanged || dynamicChanged) {
        ++session.version;
        session.legacyDirty = true;
    }
    session.pruneContentHashCache();
    session.pruneBucketLayerPlans();
}

} // namespace maplibre_bridge::labels

using namespace maplibre_bridge::labels;

void bridge_releaseLabelSession(void* session) {
    g_labelSessions.erase(session);
}

void bridge_resetLabels() {
    auto& session = labelSession();
    const bool staticChanged = !session.staticLabels.empty() || !session.staticBlob.empty();
    const bool dynamicChanged = !session.dynamicLabels.empty() || !session.dynamicBlob.empty();
    releaseStorage(session.staticLabels);
    releaseStorage(session.staticBlob);
    releaseStorage(session.staticContentHashes);
    releaseStorage(session.dynamicLabels);
    releaseStorage(session.dynamicBlob);
    releaseStorage(session.labels);
    releaseStorage(session.blob);
    releaseStorage(session.pending);
    releaseStorage(session.frameSymbols);
    releaseStorage(session.scratchStaticLabels);
    releaseStorage(session.scratchStaticBlob);
    releaseStorage(session.scratchContentHashes);
    releaseStorage(session.order);
    releaseStorage(session.scratchDynamicLabels);
    releaseStorage(session.scratchDynamicBlob);
    releaseStorage(session.utf8Scratch);
    releaseStorage(session.fontRefScratch);
    releaseStorage(session.sectionScratch);
    releaseStorage(session.contentHashCache);
    releaseStorage(session.layerOrder);
    releaseStorage(session.layerMetadata);
    releaseStorage(session.layerPaintPlans);
    releaseStorage(session.bucketLayerPlans);
    releaseStorage(session.uncachedLayerPlans);
    releaseStorage(session.featureStates);
    releaseStorage(session.paintTranslationMatrices);
    session.contentCacheGeneration = 0;
    session.legacyDirty = false;
    if (staticChanged) {
        ++session.staticVersion;
        ++session.staticContentVersion;
    }
    if (dynamicChanged) ++session.dynamicVersion;
    if (staticChanged || dynamicChanged) ++session.version;
}

extern "C" {

MAPLIBRE_API int maplibre_get_label_static_count(void) {
    return static_cast<int>(labelSession().staticLabels.size());
}

MAPLIBRE_API const void* maplibre_get_label_static_records(void) {
    const auto& records = labelSession().staticLabels;
    return records.empty() ? nullptr : records.data();
}

MAPLIBRE_API int maplibre_get_label_static_stride(void) {
    return static_cast<int>(sizeof(LabelStaticExport));
}

MAPLIBRE_API const void* maplibre_get_label_static_blob(void) {
    const auto& blob = labelSession().staticBlob;
    return blob.empty() ? nullptr : blob.data();
}

MAPLIBRE_API int maplibre_get_label_static_blob_size(void) {
    return static_cast<int>(labelSession().staticBlob.size());
}

MAPLIBRE_API uint32_t maplibre_get_label_static_version(void) {
    return labelSession().staticVersion;
}

MAPLIBRE_API uint32_t maplibre_get_label_static_content_version(void) {
    return labelSession().staticContentVersion;
}

MAPLIBRE_API int maplibre_get_label_dynamic_count(void) {
    return static_cast<int>(labelSession().dynamicLabels.size());
}

MAPLIBRE_API const void* maplibre_get_label_dynamic_records(void) {
    const auto& records = labelSession().dynamicLabels;
    return records.empty() ? nullptr : records.data();
}

MAPLIBRE_API int maplibre_get_label_dynamic_stride(void) {
    return static_cast<int>(sizeof(LabelDynamicExport));
}

MAPLIBRE_API const void* maplibre_get_label_dynamic_blob(void) {
    const auto& blob = labelSession().dynamicBlob;
    return blob.empty() ? nullptr : blob.data();
}

MAPLIBRE_API int maplibre_get_label_dynamic_blob_size(void) {
    return static_cast<int>(labelSession().dynamicBlob.size());
}

MAPLIBRE_API uint32_t maplibre_get_label_dynamic_version(void) {
    return labelSession().dynamicVersion;
}

MAPLIBRE_API int maplibre_get_label_count(void) {
    labelSession().materializeLegacy();
    return static_cast<int>(g_labels.size());
}

MAPLIBRE_API const void* maplibre_get_labels(void) {
    labelSession().materializeLegacy();
    return g_labels.empty() ? nullptr : g_labels.data();
}

MAPLIBRE_API int maplibre_get_label_stride(void) {
    return static_cast<int>(sizeof(LabelExport));
}

MAPLIBRE_API const void* maplibre_get_label_blob(void) {
    labelSession().materializeLegacy();
    return g_labelBlob.empty() ? nullptr : g_labelBlob.data();
}

MAPLIBRE_API int maplibre_get_label_blob_size(void) {
    labelSession().materializeLegacy();
    return static_cast<int>(g_labelBlob.size());
}

MAPLIBRE_API void maplibre_reproject_labels(float* outXs, float* outYs) {
    labelSession().materializeLegacy();
    if (!outXs || !outYs || g_labels.empty()) return;
    if (bridge_projectPublishedCoordinates(&g_labels.front().lat,
                                           sizeof(LabelExport),
                                           &g_labels.front().lon,
                                           sizeof(LabelExport),
                                           outXs,
                                           outYs,
                                           static_cast<int>(g_labels.size()))) {
        return;
    }
    try {
        bridge_runOnOwnerSync([&] {
            if (!g_map) return;
            for (int i = 0; i < static_cast<int>(g_labels.size()); ++i) {
                const auto pixel = g_map->pixelForLatLng(mbgl::LatLng{g_labels[i].lat, g_labels[i].lon});
                outXs[i] = static_cast<float>(pixel.x);
                outYs[i] = static_cast<float>(pixel.y);
            }
        });
    } catch (...) {
    }
}

MAPLIBRE_API uint32_t maplibre_get_labels_version(void) {
    return g_labelsVersion;
}

} // extern "C"

#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT
