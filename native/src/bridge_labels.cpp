// Label extraction from placed symbol data, exported to Dart via FFI.
#if MLN_RENDER_BACKEND_COMMAND_EXPORT

#include "bridge_state.hpp"
#include "labels/label_session.hpp"

#include <mln/map/transform_state.hpp>
#include <mln/renderer/possibly_evaluated_property_value.hpp>
#include <mln/renderer/render_tile.hpp>
#include <mln/renderer/renderer.hpp>
#include <mln/style/layer.hpp>
#include <mln/style/layers/symbol_layer.hpp>
#include <mln/style/layers/symbol_layer_properties.hpp>
#include <mln/style/style.hpp>
#include <mln/tile/geometry_tile_data.hpp>
#include <mln/tile/tile_id.hpp>
#include <mln/util/math.hpp>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <limits>
#include <map>
#include <optional>
#include <string>
#include <type_traits>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

using namespace maplibre_bridge::labels;

class ExportFeature final : public mln::GeometryTileFeature {
public:
    explicit ExportFeature(const mln::PlacedSymbolData& symbol_)
        : symbol(symbol_) {}

    mln::FeatureType getType() const override { return symbol.featureType; }
    std::optional<mln::Value> getValue(const std::string& key) const override {
        const auto value = symbol.featureProperties.find(key);
        return value == symbol.featureProperties.end() ? std::nullopt : std::optional<mln::Value>{value->second};
    }
    const mln::PropertyMap& getProperties() const override { return symbol.featureProperties; }
    mln::FeatureIdentifier getID() const override { return symbol.featureID; }

private:
    const mln::PlacedSymbolData& symbol;
};

mln::Point<float> projectToScreen(const mln::TransformState& state,
                                   const mln::mat4& matrix,
                                   const mln::Point<float>& point) {
    mln::vec4 projected{{point.x, point.y, 0, 1}};
    mln::matrix::transformMat4(projected, projected, matrix);
    const auto size = state.getSize();
    return {static_cast<float>(((projected[0] / projected[3] + 1) * 0.5) * size.width),
            static_cast<float>(((-projected[1] / projected[3] + 1) * 0.5) * size.height)};
}

constexpr uint16_t kTextColorDynamic = 1u << 0;
constexpr uint16_t kTextHaloColorDynamic = 1u << 1;
constexpr uint16_t kTextHaloWidthDynamic = 1u << 2;
constexpr uint16_t kTextOpacityDynamic = 1u << 3;
constexpr uint16_t kTextHaloBlurDynamic = 1u << 4;
constexpr uint16_t kIconOpacityDynamic = 1u << 5;
constexpr uint16_t kIconColorDynamic = 1u << 6;
constexpr uint16_t kIconHaloColorDynamic = 1u << 7;
constexpr uint16_t kIconHaloWidthDynamic = 1u << 8;
constexpr uint16_t kIconHaloBlurDynamic = 1u << 9;
constexpr uint8_t kTextPaintTranslation = 0;
constexpr uint8_t kIconPaintTranslation = 1;

bool expressionUsesFeatureState(const mln::style::expression::Expression& expression) {
    if (expression.getOperator() == "feature-state") return true;

    bool usesFeatureState = false;
    expression.eachChild([&](const mln::style::expression::Expression& child) {
        if (!usesFeatureState) usesFeatureState = expressionUsesFeatureState(child);
    });
    return usesFeatureState;
}

template <typename T>
PaintPropertyPlan<T> planPaintProperty(const mln::PossiblyEvaluatedPropertyValue<T>& property,
                                       uint16_t bit,
                                       uint16_t& dynamicMask,
                                       uint16_t& featureStateMask) {
    PaintPropertyPlan<T> result;
    property.match(
        [&](const T& value) { result.constant = value; },
        [&](const mln::style::PropertyExpression<T>& expression) {
            result.dynamic = &expression;
            dynamicMask |= bit;
            if (expressionUsesFeatureState(expression.getExpression())) featureStateMask |= bit;
        });
    return result;
}

template <typename T, typename DefaultValue>
T evaluatePlannedPaintProperty(const PaintPropertyPlan<T>& property,
                               uint16_t bit,
                               const LayerPaintPlan& layer,
                               float zoom,
                               const ExportFeature& feature,
                               const mln::FeatureState& state,
                               const mln::CanonicalTileID& canonical,
                               DefaultValue&& defaultValue) {
    if ((layer.dynamicMask & bit) == 0) return property.constant;
    auto context = mln::style::expression::EvaluationContext(zoom, &feature, &state);
    context.withCanonicalTileID(&canonical);
    return property.dynamic->evaluate(context, std::forward<DefaultValue>(defaultValue)());
}

LayerPaintPlan makeLayerPaintPlan(
    const std::string* layer,
    int32_t layerIndex,
    uint64_t layerHash,
    const mln::style::SymbolPaintProperties::PossiblyEvaluated& evaluated) {
    LayerPaintPlan result{
        .layer = layer,
        .layerIndex = layerIndex,
        .layerHash = layerHash,
    };
    result.textColor = planPaintProperty(
        evaluated.get<mln::style::TextColor>(),
        kTextColorDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.textHaloColor = planPaintProperty(
        evaluated.get<mln::style::TextHaloColor>(),
        kTextHaloColorDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.textHaloWidth = planPaintProperty(
        evaluated.get<mln::style::TextHaloWidth>(),
        kTextHaloWidthDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.textOpacity = planPaintProperty(
        evaluated.get<mln::style::TextOpacity>(),
        kTextOpacityDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.textHaloBlur = planPaintProperty(
        evaluated.get<mln::style::TextHaloBlur>(),
        kTextHaloBlurDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.iconOpacity = planPaintProperty(
        evaluated.get<mln::style::IconOpacity>(),
        kIconOpacityDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.iconColor = planPaintProperty(
        evaluated.get<mln::style::IconColor>(),
        kIconColorDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.iconHaloColor = planPaintProperty(
        evaluated.get<mln::style::IconHaloColor>(),
        kIconHaloColorDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.iconHaloWidth = planPaintProperty(
        evaluated.get<mln::style::IconHaloWidth>(),
        kIconHaloWidthDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.iconHaloBlur = planPaintProperty(
        evaluated.get<mln::style::IconHaloBlur>(),
        kIconHaloBlurDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.textTranslate = evaluated.get<mln::style::TextTranslate>();
    result.textTranslateAnchor = evaluated.get<mln::style::TextTranslateAnchor>();
    result.iconTranslate = evaluated.get<mln::style::IconTranslate>();
    result.iconTranslateAnchor = evaluated.get<mln::style::IconTranslateAnchor>();
    return result;
}

void appendCandidateLayerPlans(LabelSessionState& session,
                               const mln::PlacedSymbolData& symbol,
                               std::vector<std::size_t>& result) {
    const auto append = [&](const std::string& layer) {
        const auto found = session.layerMetadata.find(layer);
        if (found != session.layerMetadata.end() &&
            found->second.paintPlanIndex < session.layerPaintPlans.size()) {
            result.push_back(found->second.paintPlanIndex);
        }
    };
    if (symbol.layers.empty()) {
        append(symbol.layer);
    } else {
        for (const auto& layer : symbol.layers) append(layer);
    }
}

const std::vector<std::size_t>& layerPlansForSymbol(LabelSessionState& session,
                                                    const mln::PlacedSymbolData& symbol) {
    if (symbol.bucketInstanceID == 0) {
        session.uncachedLayerPlans.clear();
        appendCandidateLayerPlans(session, symbol, session.uncachedLayerPlans);
        return session.uncachedLayerPlans;
    }

    auto item = session.bucketLayerPlans.try_emplace(symbol.bucketInstanceID).first;
    if (item->second.lastSeenGeneration != session.contentCacheGeneration) {
        item->second.plans.clear();
        appendCandidateLayerPlans(session, symbol, item->second.plans);
        item->second.lastSeenGeneration = session.contentCacheGeneration;
    }
    return item->second.plans;
}

const mln::FeatureState& featureStateForSymbol(LabelSessionState& session,
                                                const mln::PlacedSymbolData& symbol,
                                                const mln::Renderer& renderer) {
    const auto featureID = mln::featureIDtoString(symbol.featureID);
    if (!featureID || symbol.sourceID.empty()) return session.emptyFeatureState;

    FeatureStateKey key{symbol.sourceID, symbol.sourceLayer, *featureID};
    auto inserted = session.featureStates.try_emplace(std::move(key));
    if (inserted.second) {
        try {
            renderer.getFeatureState(
                inserted.first->second,
                symbol.sourceID,
                symbol.sourceLayer.empty() ? std::nullopt
                                           : std::optional<std::string>{symbol.sourceLayer},
                *featureID);
        } catch (...) {
        }
    }
    return inserted.first->second;
}

mln::Point<float> resolvePlannedPaintTranslation(LabelSessionState& session,
                                                  std::size_t layerPlanIndex,
                                                  uint8_t component,
                                                  const mln::PlacedSymbolData& symbol,
                                                  const mln::TransformState& state,
                                                  const std::array<float, 2>& translation,
                                                  mln::style::TranslateAnchorType anchor) {
    if (anchor == mln::style::TranslateAnchorType::Viewport ||
        (translation[0] == 0 && translation[1] == 0)) {
        return {translation[0], translation[1]};
    }

    const PaintTranslationKey key{
        .layerPlanIndex = layerPlanIndex,
        .tileWrap = symbol.tileWrap,
        .canonicalZ = symbol.canonicalZ,
        .component = component,
        .canonicalX = symbol.canonicalX,
        .canonicalY = symbol.canonicalY,
    };
    auto inserted = session.paintTranslationMatrices.try_emplace(key);
    auto& matrices = inserted.first->second;
    if (inserted.second) {
        const mln::UnwrappedTileID tileID{
            symbol.tileWrap,
            mln::CanonicalTileID{symbol.canonicalZ, symbol.canonicalX, symbol.canonicalY}};
        state.matrixFor(matrices.tile, tileID);
        mln::matrix::multiply(matrices.tile, state.getProjectionMatrix(), matrices.tile);
        matrices.translated = mln::RenderTile::translateVtxMatrix(
            tileID, matrices.tile, translation, anchor, state, false);
    }

    const auto before = projectToScreen(state, matrices.tile, symbol.tileAnchor);
    const auto after = projectToScreen(state, matrices.translated, symbol.tileAnchor);
    return after - before;
}

} // namespace

using namespace maplibre_bridge::labels;

void bridge_extractLabels(const mln::TransformState* renderedState) {
    auto& session = labelSession();
    session.beginFrame();
    if (!g_frontend || !g_labelCollectionEnabled) {
        publishPendingLabels();
        return;
    }
    auto* renderer = g_frontend->getRenderer();
    if (!renderer || !g_map) return;

    const auto currentState = g_map->getTransfromState();
    const auto& state = renderedState ? *renderedState : currentState;
    const float zoom = static_cast<float>(state.getZoom());
    const auto styleLayers = g_map->getStyle().getLayers();
    bool sameLayerOrder = session.layerOrder.size() == styleLayers.size();
    for (std::size_t i = 0; sameLayerOrder && i < styleLayers.size(); ++i) {
        sameLayerOrder = session.layerOrder[i] == styleLayers[i]->getID();
    }
    if (!sameLayerOrder) {
        constexpr uint64_t hashOffset = 1469598103934665603ull;
        session.layerOrder.clear();
        session.layerOrder.reserve(styleLayers.size());
        session.layerMetadata.clear();
        session.layerMetadata.reserve(styleLayers.size());
        for (std::size_t i = 0; i < styleLayers.size(); ++i) {
            const auto& id = styleLayers[i]->getID();
            session.layerOrder.push_back(id);
            session.layerMetadata.emplace(
                id,
                LayerMetadata{static_cast<int32_t>(i), hashString(hashOffset, id)});
        }
    }

    for (auto& item : session.layerMetadata) {
        item.second.paintPlanIndex = std::numeric_limits<std::size_t>::max();
    }
    session.layerPaintPlans.reserve(styleLayers.size());
    for (const auto* rawLayer : styleLayers) {
        if (!rawLayer || !rawLayer->getTypeInfo() ||
            std::strcmp(rawLayer->getTypeInfo()->type, "symbol") != 0 ||
            rawLayer->getVisibility() != mln::style::VisibilityType::Visible ||
            zoom < rawLayer->getMinZoom() || zoom >= rawLayer->getMaxZoom()) {
            continue;
        }
        auto layerID = rawLayer->getID();
        const auto* evaluatedLayer = renderer->getEvaluatedLayerProperties(layerID);
        if (!evaluatedLayer) continue;
        const auto& evaluated =
            static_cast<const mln::style::SymbolLayerProperties&>(*evaluatedLayer).evaluated;
        const auto metadata = session.layerMetadata.find(layerID);
        if (metadata == session.layerMetadata.end()) continue;
        const auto planIndex = session.layerPaintPlans.size();
        session.layerPaintPlans.push_back(
            makeLayerPaintPlan(&metadata->first, metadata->second.index, metadata->second.hash, evaluated));
        metadata->second.paintPlanIndex = planIndex;
    }

    const auto& placedSymbols = renderer->getPlacedSymbolsData();
    session.pending.reserve(placedSymbols.size());
    session.frameSymbols.reserve(placedSymbols.size());
    for (const auto& symbol : placedSymbols) {
        const bool hasText = symbol.textPlaced && symbol.textCollisionBox;
        const bool hasIcon = symbol.iconPlaced && symbol.iconCollisionBox && !symbol.icon.empty();
        if (!hasText && !hasIcon) continue;

        const auto& candidateLayerPlans = layerPlansForSymbol(session, symbol);
        if (candidateLayerPlans.empty()) continue;

        const auto& anchorLatLng = symbol.anchorLatLng;

        float textWidth = 0;
        float textHeight = 0;
        float textCenterX = 0;
        float textCenterY = 0;
        if (hasText) {
            const auto& box = *symbol.textCollisionBox;
            textWidth = symbol.textVisualWidth > 0 ? symbol.textVisualWidth : box.max.x - box.min.x;
            textHeight = symbol.textVisualHeight > 0 ? symbol.textVisualHeight : box.max.y - box.min.y;
            textCenterX = symbol.textVisualWidth > 0
                              ? symbol.textVisualOffset.x
                              : (box.min.x + box.max.x) * 0.5f - symbol.anchorPoint.x;
            textCenterY = symbol.textVisualHeight > 0
                              ? symbol.textVisualOffset.y
                              : (box.min.y + box.max.y) * 0.5f - symbol.anchorPoint.y;
        }
        float iconWidth = 0;
        float iconHeight = 0;
        float iconCenterX = 0;
        float iconCenterY = 0;
        if (hasIcon) {
            const auto& box = *symbol.iconCollisionBox;
            iconWidth = symbol.iconVisualWidth > 0 ? symbol.iconVisualWidth : box.max.x - box.min.x;
            iconHeight = symbol.iconVisualHeight > 0 ? symbol.iconVisualHeight : box.max.y - box.min.y;
            iconCenterX = symbol.iconVisualWidth > 0
                              ? symbol.iconVisualOffset.x
                              : (box.min.x + box.max.x) * 0.5f - symbol.anchorPoint.x;
            iconCenterY = symbol.iconVisualHeight > 0
                              ? symbol.iconVisualOffset.y
                              : (box.min.y + box.max.y) * 0.5f - symbol.anchorPoint.y;
        }
        const bool textOK = hasText && textWidth > 0 && textHeight > 0;
        const bool iconOK = hasIcon && iconWidth > 0 && iconHeight > 0;
        if (!textOK && !iconOK) continue;

        uint16_t featureStateMask = 0;
        for (const auto planIndex : candidateLayerPlans) {
            featureStateMask |= session.layerPaintPlans[planIndex].featureStateMask;
        }
        const auto& featureState = featureStateMask == 0
                                       ? session.emptyFeatureState
                                       : featureStateForSymbol(session, symbol, *renderer);
        ExportFeature feature(symbol);
        const mln::CanonicalTileID canonical{symbol.canonicalZ, symbol.canonicalX, symbol.canonicalY};
        const auto frameSymbolIndex = session.frameSymbols.size();
        LabelExport base{};
        base.lat = textOK ? anchorLatLng.latitude() : 0;
        base.lon = textOK ? anchorLatLng.longitude() : 0;
        base.iconLat = iconOK ? anchorLatLng.latitude() : 0;
        base.iconLon = iconOK ? anchorLatLng.longitude() : 0;
        base.fontSize = symbol.textSize;
        base.textW = textWidth;
        base.textH = textHeight;
        base.iconW = iconWidth;
        base.iconH = iconHeight;
        base.iconSize = symbol.iconSize;
        base.flags = (textOK ? kTextPlaced : 0u) | (iconOK ? kIconPlaced : 0u) |
                     (symbol.alongLine ? kTextAlongLine : 0u) |
                     (symbol.iconAlongLine ? kIconAlongLine : 0u);
        base.textAngle = symbol.textAngle;
        base.iconAngle = symbol.iconAngle;
        base.crossTileID = symbol.crossTileID;
        base.tileWrap = symbol.tileWrap;
        base.textOffsetX = textCenterX;
        base.textOffsetY = textCenterY;
        base.iconOffsetX = iconCenterX;
        base.iconOffsetY = iconCenterY;
        base.letterSpacing = symbol.letterSpacing;
        base.lineHeight = symbol.lineHeight;
        base.maxWidth = symbol.maxWidth;
        base.textRotation = symbol.textRotation;
        base.iconRotation = symbol.iconRotation;
        base.iconFitWidth = symbol.iconFitWidth;
        base.iconFitHeight = symbol.iconFitHeight;
        base.textTransformXX = symbol.textTransform[0];
        base.textTransformXY = symbol.textTransform[1];
        base.textTransformYX = symbol.textTransform[2];
        base.textTransformYY = symbol.textTransform[3];
        base.iconTransformXX = symbol.iconTransform[0];
        base.iconTransformXY = symbol.iconTransform[1];
        base.iconTransformYX = symbol.iconTransform[2];
        base.iconTransformYY = symbol.iconTransform[3];
        base.styleFlags = (symbol.vertical ? kVertical : 0u) |
                          (symbol.iconSDF ? kIconSDF : 0u) |
                          (symbol.textPitchAlignment == mln::style::AlignmentType::Map ? kTextPitchMap : 0u) |
                          (symbol.textRotationAlignment == mln::style::AlignmentType::Map
                               ? kTextRotationMap
                               : 0u) |
                          (symbol.iconPitchAlignment == mln::style::AlignmentType::Map ? kIconPitchMap : 0u) |
                          (symbol.iconRotationAlignment == mln::style::AlignmentType::Map
                               ? kIconRotationMap
                               : 0u) |
                          (symbol.textKeepUpright ? kTextKeepUpright : 0u) |
                          (symbol.iconKeepUpright ? kIconKeepUpright : 0u) |
                          (symbol.textRTL ? kTextRTL : 0u);
        base.textJustify = static_cast<uint32_t>(symbol.textJustify);
        base.renderGroup = symbol.renderGroup;
        base.renderOrder = symbol.renderOrder;

        for (const auto planIndex : candidateLayerPlans) {
            const auto& layer = session.layerPaintPlans[planIndex];
            auto label = base;
            label.layerIndex = layer.layerIndex;
            const auto textColor = evaluatePlannedPaintProperty(
                layer.textColor,
                kTextColorDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mln::style::SymbolLayer::getDefaultTextColor().asConstant(); });
            label.textR = textColor.r;
            label.textG = textColor.g;
            label.textB = textColor.b;
            label.textA = textColor.a;
            const auto haloColor = evaluatePlannedPaintProperty(
                layer.textHaloColor,
                kTextHaloColorDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mln::style::SymbolLayer::getDefaultTextHaloColor().asConstant(); });
            label.haloR = haloColor.r;
            label.haloG = haloColor.g;
            label.haloB = haloColor.b;
            label.haloA = haloColor.a;
            label.haloWidth = evaluatePlannedPaintProperty(
                layer.textHaloWidth,
                kTextHaloWidthDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mln::style::SymbolLayer::getDefaultTextHaloWidth().asConstant(); });
            label.textOpacity = evaluatePlannedPaintProperty(
                layer.textOpacity,
                kTextOpacityDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mln::style::SymbolLayer::getDefaultTextOpacity().asConstant(); });
            label.haloBlur = evaluatePlannedPaintProperty(
                layer.textHaloBlur,
                kTextHaloBlurDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mln::style::SymbolLayer::getDefaultTextHaloBlur().asConstant(); });
            label.iconOpacity = evaluatePlannedPaintProperty(
                layer.iconOpacity,
                kIconOpacityDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mln::style::SymbolLayer::getDefaultIconOpacity().asConstant(); });
            const auto iconColor = evaluatePlannedPaintProperty(
                layer.iconColor,
                kIconColorDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mln::style::SymbolLayer::getDefaultIconColor().asConstant(); });
            label.iconR = iconColor.r;
            label.iconG = iconColor.g;
            label.iconB = iconColor.b;
            label.iconA = iconColor.a;
            const auto iconHaloColor = evaluatePlannedPaintProperty(
                layer.iconHaloColor,
                kIconHaloColorDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mln::style::SymbolLayer::getDefaultIconHaloColor().asConstant(); });
            label.iconHaloR = iconHaloColor.r;
            label.iconHaloG = iconHaloColor.g;
            label.iconHaloB = iconHaloColor.b;
            label.iconHaloA = iconHaloColor.a;
            label.iconHaloWidth = evaluatePlannedPaintProperty(
                layer.iconHaloWidth,
                kIconHaloWidthDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mln::style::SymbolLayer::getDefaultIconHaloWidth().asConstant(); });
            label.iconHaloBlur = evaluatePlannedPaintProperty(
                layer.iconHaloBlur,
                kIconHaloBlurDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mln::style::SymbolLayer::getDefaultIconHaloBlur().asConstant(); });

            const auto screenTextTranslate = resolvePlannedPaintTranslation(
                session,
                planIndex,
                kTextPaintTranslation,
                symbol,
                state,
                layer.textTranslate,
                layer.textTranslateAnchor);
            label.textTranslateX = screenTextTranslate.x;
            label.textTranslateY = screenTextTranslate.y;
            const auto screenIconTranslate = resolvePlannedPaintTranslation(
                session,
                planIndex,
                kIconPaintTranslation,
                symbol,
                state,
                layer.iconTranslate,
                layer.iconTranslateAnchor);
            label.iconTranslateX = screenIconTranslate.x;
            label.iconTranslateY = screenIconTranslate.y;
            session.pending.push_back(
                {label, &symbol, layer.layer, frameSymbolIndex, layer.layerHash});
        }
        session.frameSymbols.push_back({
            .symbol = &symbol,
            .key = contentKey(symbol),
        });
    }

    publishPendingLabels();
}

#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT
