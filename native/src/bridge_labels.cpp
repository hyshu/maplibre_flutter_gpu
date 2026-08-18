// Label extraction from placed symbol data, exported to Dart via FFI.
#if MLN_RENDER_BACKEND_COMMAND_EXPORT

#include "bridge_state.hpp"

#include <mbgl/map/transform_state.hpp>
#include <mbgl/renderer/possibly_evaluated_property_value.hpp>
#include <mbgl/renderer/render_tile.hpp>
#include <mbgl/renderer/renderer.hpp>
#include <mbgl/style/layer.hpp>
#include <mbgl/style/layers/symbol_layer.hpp>
#include <mbgl/style/layers/symbol_layer_properties.hpp>
#include <mbgl/style/style.hpp>
#include <mbgl/tile/geometry_tile_data.hpp>
#include <mbgl/tile/tile_id.hpp>
#include <mbgl/util/math.hpp>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <limits>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace {

constexpr uint32_t kTextPlaced = 1u << 0;
constexpr uint32_t kIconPlaced = 1u << 1;
constexpr uint32_t kTextAlongLine = 1u << 2;
constexpr uint32_t kIconAlongLine = 1u << 3;

constexpr uint32_t kVertical = 1u << 0;
constexpr uint32_t kIconSDF = 1u << 1;
constexpr uint32_t kTextPitchMap = 1u << 2;
constexpr uint32_t kTextRotationMap = 1u << 3;
constexpr uint32_t kIconPitchMap = 1u << 4;
constexpr uint32_t kIconRotationMap = 1u << 5;
constexpr uint32_t kTextKeepUpright = 1u << 6;
constexpr uint32_t kIconKeepUpright = 1u << 7;
constexpr uint32_t kTextRTL = 1u << 8;

constexpr uint32_t kSectionHasColor = 1u << 0;
constexpr uint32_t kSectionHasImage = 1u << 1;

struct LabelStringRefExport {
    uint32_t offset;
    uint32_t length;
};
static_assert(sizeof(LabelStringRefExport) == 8, "LabelStringRefExport size must be stable for FFI");
COMMAND_EXPORT_ABI_OFFSET(LabelStringRefExport, offset, 0);
COMMAND_EXPORT_ABI_OFFSET(LabelStringRefExport, length, 4);

struct LabelTextSectionExport {
    uint32_t start;
    uint32_t end;
    float fontScale;
    uint32_t flags;
    float colorR;
    float colorG;
    float colorB;
    float colorA;
    uint32_t fontsOffset;
    uint32_t fontCount;
    uint32_t imageOffset;
    uint32_t imageLength;
};
static_assert(sizeof(LabelTextSectionExport) == 48, "LabelTextSectionExport size must be stable for FFI");
COMMAND_EXPORT_ABI_OFFSET(LabelTextSectionExport, start, 0);
COMMAND_EXPORT_ABI_OFFSET(LabelTextSectionExport, end, 4);
COMMAND_EXPORT_ABI_OFFSET(LabelTextSectionExport, fontScale, 8);
COMMAND_EXPORT_ABI_OFFSET(LabelTextSectionExport, flags, 12);
COMMAND_EXPORT_ABI_OFFSET(LabelTextSectionExport, colorR, 16);
COMMAND_EXPORT_ABI_OFFSET(LabelTextSectionExport, colorG, 20);
COMMAND_EXPORT_ABI_OFFSET(LabelTextSectionExport, colorB, 24);
COMMAND_EXPORT_ABI_OFFSET(LabelTextSectionExport, colorA, 28);
COMMAND_EXPORT_ABI_OFFSET(LabelTextSectionExport, fontsOffset, 32);
COMMAND_EXPORT_ABI_OFFSET(LabelTextSectionExport, fontCount, 36);
COMMAND_EXPORT_ABI_OFFSET(LabelTextSectionExport, imageOffset, 40);
COMMAND_EXPORT_ABI_OFFSET(LabelTextSectionExport, imageLength, 44);

struct LabelPathPointExport {
    float x;
    float y;
};
static_assert(sizeof(LabelPathPointExport) == 8, "LabelPathPointExport size must be stable for FFI");
COMMAND_EXPORT_ABI_OFFSET(LabelPathPointExport, x, 0);
COMMAND_EXPORT_ABI_OFFSET(LabelPathPointExport, y, 4);

// Variable-size values use byte offsets into the session-owned label blob.
struct LabelExport {
    double lat;
    double lon;
    double iconLat;
    double iconLon;
    float fontSize;
    float textR;
    float textG;
    float textB;
    float textA;
    float haloR;
    float haloG;
    float haloB;
    float haloA;
    float haloWidth;
    float textW;
    float textH;
    float iconW;
    float iconH;
    float iconSize;
    float iconOpacity;
    float iconR;
    float iconG;
    float iconB;
    float iconA;
    uint32_t flags;
    float textAngle;
    uint32_t crossTileID;
    uint32_t textOffset;
    uint32_t textLength;
    uint32_t layerOffset;
    uint32_t layerLength;
    uint32_t iconOffset;
    uint32_t iconLength;
    uint32_t textFontsOffset;
    uint32_t textFontCount;
    uint32_t textSectionsOffset;
    uint32_t textSectionCount;
    uint32_t textPathOffset;
    uint32_t textPathCount;
    uint32_t iconPathOffset;
    uint32_t iconPathCount;
    float textOffsetX;
    float textOffsetY;
    float iconOffsetX;
    float iconOffsetY;
    float textOpacity;
    float haloBlur;
    float letterSpacing;
    float lineHeight;
    float maxWidth;
    float iconAngle;
    float textRotation;
    float iconRotation;
    float textTranslateX;
    float textTranslateY;
    float iconTranslateX;
    float iconTranslateY;
    float iconHaloR;
    float iconHaloG;
    float iconHaloB;
    float iconHaloA;
    float iconHaloWidth;
    float iconHaloBlur;
    float iconFitWidth;
    float iconFitHeight;
    float textTransformXX;
    float textTransformXY;
    float textTransformYX;
    float textTransformYY;
    float iconTransformXX;
    float iconTransformXY;
    float iconTransformYX;
    float iconTransformYY;
    int32_t layerIndex;
    uint32_t styleFlags;
    uint32_t textJustify;
    uint32_t renderGroup;
    uint32_t renderOrder;
    uint32_t logicalTextOffset;
    uint32_t logicalTextLength;
    uint32_t visualTextSectionsOffset;
    uint32_t visualTextSectionCount;
};
static_assert(sizeof(LabelExport) == 344, "LabelExport size must be stable for FFI");

COMMAND_EXPORT_ABI_OFFSET(LabelExport, lat, 0);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, lon, 8);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconLat, 16);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconLon, 24);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, fontSize, 32);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textR, 36);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textG, 40);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textB, 44);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textA, 48);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, haloR, 52);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, haloG, 56);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, haloB, 60);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, haloA, 64);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, haloWidth, 68);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textW, 72);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textH, 76);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconW, 80);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconH, 84);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconSize, 88);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconOpacity, 92);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconR, 96);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconG, 100);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconB, 104);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconA, 108);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, flags, 112);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textAngle, 116);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, crossTileID, 120);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textOffset, 124);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textLength, 128);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, layerOffset, 132);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, layerLength, 136);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconOffset, 140);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconLength, 144);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textFontsOffset, 148);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textFontCount, 152);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textSectionsOffset, 156);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textSectionCount, 160);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textPathOffset, 164);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textPathCount, 168);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconPathOffset, 172);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconPathCount, 176);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textOffsetX, 180);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textOffsetY, 184);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconOffsetX, 188);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconOffsetY, 192);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textOpacity, 196);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, haloBlur, 200);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, letterSpacing, 204);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, lineHeight, 208);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, maxWidth, 212);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconAngle, 216);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textRotation, 220);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconRotation, 224);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textTranslateX, 228);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textTranslateY, 232);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconTranslateX, 236);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconTranslateY, 240);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconHaloR, 244);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconHaloG, 248);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconHaloB, 252);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconHaloA, 256);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconHaloWidth, 260);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconHaloBlur, 264);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconFitWidth, 268);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconFitHeight, 272);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textTransformXX, 276);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textTransformXY, 280);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textTransformYX, 284);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textTransformYY, 288);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconTransformXX, 292);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconTransformXY, 296);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconTransformYX, 300);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconTransformYY, 304);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, layerIndex, 308);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, styleFlags, 312);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textJustify, 316);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, renderGroup, 320);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, renderOrder, 324);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, logicalTextOffset, 328);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, logicalTextLength, 332);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, visualTextSectionsOffset, 336);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, visualTextSectionCount, 340);

class ExportFeature final : public mbgl::GeometryTileFeature {
public:
    explicit ExportFeature(const mbgl::PlacedSymbolData& symbol_)
        : symbol(symbol_) {}

    mbgl::FeatureType getType() const override { return symbol.featureType; }
    std::optional<mbgl::Value> getValue(const std::string& key) const override {
        const auto value = symbol.featureProperties.find(key);
        return value == symbol.featureProperties.end() ? std::nullopt : std::optional<mbgl::Value>{value->second};
    }
    const mbgl::PropertyMap& getProperties() const override { return symbol.featureProperties; }
    mbgl::FeatureIdentifier getID() const override { return symbol.featureID; }

private:
    const mbgl::PlacedSymbolData& symbol;
};

template <typename T>
T evaluateProperty(const mbgl::PossiblyEvaluatedPropertyValue<T>& property,
                   float zoom,
                   const ExportFeature& feature,
                   const mbgl::FeatureState& state,
                   const mbgl::CanonicalTileID& canonical,
                   T defaultValue) {
    return property.match(
        [](const T& value) { return value; },
        [&](const mbgl::style::PropertyExpression<T>& expression) {
            auto context = mbgl::style::expression::EvaluationContext(zoom, &feature, &state);
            context.withCanonicalTileID(&canonical);
            return expression.evaluate(context, defaultValue);
        });
}

std::string utf8FromUTF16(const std::u16string& input) {
    std::string result;
    result.reserve(input.size() * 3);
    for (std::size_t i = 0; i < input.size(); ++i) {
        char32_t codePoint = input[i];
        if (codePoint >= 0xD800 && codePoint <= 0xDBFF && i + 1 < input.size()) {
            const char16_t low = input[i + 1];
            if (low >= 0xDC00 && low <= 0xDFFF) {
                codePoint = 0x10000 + ((codePoint - 0xD800) << 10) + (low - 0xDC00);
                ++i;
            }
        }
        if (codePoint >= 0xD800 && codePoint <= 0xDFFF) codePoint = 0xFFFD;
        if (codePoint < 0x80) {
            result += static_cast<char>(codePoint);
        } else if (codePoint < 0x800) {
            result += static_cast<char>(0xC0 | (codePoint >> 6));
            result += static_cast<char>(0x80 | (codePoint & 0x3F));
        } else if (codePoint < 0x10000) {
            result += static_cast<char>(0xE0 | (codePoint >> 12));
            result += static_cast<char>(0x80 | ((codePoint >> 6) & 0x3F));
            result += static_cast<char>(0x80 | (codePoint & 0x3F));
        } else {
            result += static_cast<char>(0xF0 | (codePoint >> 18));
            result += static_cast<char>(0x80 | ((codePoint >> 12) & 0x3F));
            result += static_cast<char>(0x80 | ((codePoint >> 6) & 0x3F));
            result += static_cast<char>(0x80 | (codePoint & 0x3F));
        }
    }
    return result;
}

void alignBlob(std::vector<uint8_t>& blob, std::size_t alignment) {
    while (blob.size() % alignment != 0) blob.push_back(0);
}

LabelStringRefExport appendString(std::vector<uint8_t>& blob, const std::string& value) {
    const auto offset = static_cast<uint32_t>(blob.size());
    blob.insert(blob.end(), value.begin(), value.end());
    return {offset, static_cast<uint32_t>(value.size())};
}

template <typename T>
uint32_t appendRecords(std::vector<uint8_t>& blob, const std::vector<T>& records) {
    if (records.empty()) return 0;
    alignBlob(blob, alignof(T));
    const auto offset = static_cast<uint32_t>(blob.size());
    const auto* bytes = reinterpret_cast<const uint8_t*>(records.data());
    blob.insert(blob.end(), bytes, bytes + records.size() * sizeof(T));
    return offset;
}

uint32_t appendFonts(std::vector<uint8_t>& blob, const mbgl::FontStack& fonts) {
    std::vector<LabelStringRefExport> refs;
    refs.reserve(fonts.size());
    for (const auto& font : fonts) refs.push_back(appendString(blob, font));
    return appendRecords(blob, refs);
}

uint32_t appendSections(std::vector<uint8_t>& blob,
                        const std::vector<mbgl::ShapingTextSection>& sections,
                        const mbgl::FontStack& fallbackFonts) {
    std::vector<LabelTextSectionExport> records;
    records.reserve(sections.size());
    for (const auto& section : sections) {
        LabelTextSectionExport record{};
        record.start = section.start;
        record.end = section.end;
        record.fontScale = static_cast<float>(section.scale);
        const auto& fonts = section.fontStack.empty() ? fallbackFonts : section.fontStack;
        record.fontsOffset = appendFonts(blob, fonts);
        record.fontCount = static_cast<uint32_t>(fonts.size());
        if (section.textColor) {
            record.flags |= kSectionHasColor;
            record.colorR = section.textColor->r;
            record.colorG = section.textColor->g;
            record.colorB = section.textColor->b;
            record.colorA = section.textColor->a;
        }
        if (section.imageID) {
            record.flags |= kSectionHasImage;
            const auto image = appendString(blob, *section.imageID);
            record.imageOffset = image.offset;
            record.imageLength = image.length;
        }
        records.push_back(record);
    }
    return appendRecords(blob, records);
}

uint32_t appendPath(std::vector<uint8_t>& blob,
                    const std::vector<mbgl::Point<float>>& path,
                    float originX,
                    float originY) {
    std::vector<LabelPathPointExport> records;
    records.reserve(path.size());
    for (const auto& point : path) records.push_back({point.x - originX, point.y - originY});
    return appendRecords(blob, records);
}

mbgl::Point<float> projectToScreen(const mbgl::TransformState& state,
                                   const mbgl::mat4& matrix,
                                   const mbgl::Point<float>& point) {
    mbgl::vec4 projected{{point.x, point.y, 0, 1}};
    mbgl::matrix::transformMat4(projected, projected, matrix);
    const auto size = state.getSize();
    return {static_cast<float>(((projected[0] / projected[3] + 1) * 0.5) * size.width),
            static_cast<float>(((-projected[1] / projected[3] + 1) * 0.5) * size.height)};
}

mbgl::Point<float> resolvePaintTranslation(const mbgl::PlacedSymbolData& symbol,
                                           const mbgl::TransformState* state,
                                           const std::array<float, 2>& translation,
                                           mbgl::style::TranslateAnchorType anchor) {
    if (anchor == mbgl::style::TranslateAnchorType::Viewport || !state ||
        (translation[0] == 0 && translation[1] == 0)) {
        return {translation[0], translation[1]};
    }

    const mbgl::UnwrappedTileID tileID{
        symbol.tileWrap,
        mbgl::CanonicalTileID{symbol.canonicalZ, symbol.canonicalX, symbol.canonicalY}};
    mbgl::mat4 tileMatrix;
    state->matrixFor(tileMatrix, tileID);
    mbgl::matrix::multiply(tileMatrix, state->getProjectionMatrix(), tileMatrix);
    const auto translated = mbgl::RenderTile::translateVtxMatrix(
        tileID, tileMatrix, translation, anchor, *state, false);
    const auto before = projectToScreen(*state, tileMatrix, symbol.tileAnchor);
    const auto after = projectToScreen(*state, translated, symbol.tileAnchor);
    return after - before;
}

struct LabelSessionState {
    std::vector<LabelExport> labels;
    std::vector<uint8_t> blob;
    uint32_t version = 0;
};

std::map<void*, LabelSessionState> g_labelSessions;
LabelSessionState& labelSession() {
    return g_labelSessions[bridge_currentSession()];
}

#define g_labels labelSession().labels
#define g_labelBlob labelSession().blob
#define g_labelsVersion labelSession().version

bool sameBytes(const std::vector<LabelExport>& lhs, const std::vector<LabelExport>& rhs) {
    return lhs.size() == rhs.size() &&
           (lhs.empty() || std::memcmp(lhs.data(), rhs.data(), lhs.size() * sizeof(LabelExport)) == 0);
}

bool sameBytes(const std::vector<uint8_t>& lhs, const std::vector<uint8_t>& rhs) {
    return lhs == rhs;
}

} // namespace

void bridge_releaseLabelSession(void* session) {
    g_labelSessions.erase(session);
}

void bridge_resetLabels() {
    const bool changed = !g_labels.empty() || !g_labelBlob.empty();
    g_labels.clear();
    g_labelBlob.clear();
    if (changed) ++g_labelsVersion;
}

void bridge_extractLabels(const mbgl::TransformState* renderedState) {
    std::vector<LabelExport> labels;
    std::vector<uint8_t> blob;
    if (!g_frontend || !g_labelCollectionEnabled) {
        if (!sameBytes(labels, g_labels) || !sameBytes(blob, g_labelBlob)) {
            g_labels = std::move(labels);
            g_labelBlob = std::move(blob);
            ++g_labelsVersion;
        }
        return;
    }
    auto* renderer = g_frontend->getRenderer();
    if (!renderer || !g_map) return;

    const auto currentState = g_map->getTransfromState();
    const auto& state = renderedState ? *renderedState : currentState;
    const float zoom = static_cast<float>(state.getZoom());
    const auto styleLayers = g_map->getStyle().getLayers();
    std::map<std::string, int32_t> layerIndices;
    for (std::size_t i = 0; i < styleLayers.size(); ++i) {
        layerIndices.emplace(styleLayers[i]->getID(), static_cast<int32_t>(i));
    }

    for (const auto& symbol : renderer->getPlacedSymbolsData()) {
        const bool hasText = symbol.textPlaced && symbol.textCollisionBox;
        const bool hasIcon = symbol.iconPlaced && symbol.iconCollisionBox && !symbol.icon.empty();
        if (!hasText && !hasIcon) continue;

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

        const auto& lineBrokenText = symbol.lineBrokenText.empty() ? symbol.key : symbol.lineBrokenText;
        const auto& logicalLineBrokenText = symbol.logicalLineBrokenText.empty()
                                                ? lineBrokenText
                                                : symbol.logicalLineBrokenText;
        const auto text = appendString(blob, utf8FromUTF16(lineBrokenText));
        const auto logicalText = appendString(blob, utf8FromUTF16(logicalLineBrokenText));
        const auto icon = appendString(blob, symbol.icon);
        const uint32_t fontsOffset = appendFonts(blob, symbol.textFontStack);
        auto sections = symbol.textSections;
        if (sections.empty() && !logicalLineBrokenText.empty()) {
            sections.push_back(mbgl::ShapingTextSection{
                .start = 0,
                .end = static_cast<uint32_t>(logicalLineBrokenText.size()),
                .fontStack = symbol.textFontStack,
            });
        }
        const uint32_t sectionsOffset = appendSections(blob, sections, symbol.textFontStack);
        auto visualSections = symbol.visualTextSections;
        if (visualSections.empty() && !lineBrokenText.empty()) {
            visualSections.push_back(mbgl::ShapingTextSection{
                .start = 0,
                .end = static_cast<uint32_t>(lineBrokenText.size()),
                .fontStack = symbol.textFontStack,
            });
        }
        const uint32_t visualSectionsOffset = appendSections(blob, visualSections, symbol.textFontStack);
        const uint32_t textPathOffset = appendPath(blob, symbol.textPath, textCenterX, textCenterY);
        const uint32_t iconPathOffset = appendPath(blob, symbol.iconPath, iconCenterX, iconCenterY);

        ExportFeature feature(symbol);
        const mbgl::CanonicalTileID canonical{symbol.canonicalZ, symbol.canonicalX, symbol.canonicalY};
        mbgl::FeatureState featureState;
        if (const auto id = mbgl::featureIDtoString(symbol.featureID); id && !symbol.sourceID.empty()) {
            try {
                featureState = renderer->getFeatureState(
                    symbol.sourceID,
                    symbol.sourceLayer.empty() ? std::nullopt
                                               : std::optional<std::string>{symbol.sourceLayer},
                    *id);
            } catch (...) {
            }
        }

        const auto candidateLayers = symbol.layers.empty() ? std::vector<std::string>{symbol.layer} : symbol.layers;
        for (const auto& layerID : candidateLayers) {
            const auto* rawLayer = g_map->getStyle().getLayer(layerID);
            if (!rawLayer || !rawLayer->getTypeInfo() ||
                std::strcmp(rawLayer->getTypeInfo()->type, "symbol") != 0 ||
                rawLayer->getVisibility() != mbgl::style::VisibilityType::Visible ||
                zoom < rawLayer->getMinZoom() || zoom >= rawLayer->getMaxZoom()) {
                continue;
            }
            const auto* evaluatedLayer = renderer->getEvaluatedLayerProperties(layerID);
            if (!evaluatedLayer) continue;
            const auto& evaluated =
                static_cast<const mbgl::style::SymbolLayerProperties&>(*evaluatedLayer).evaluated;
            LabelExport label{};
            label.lat = textOK ? anchorLatLng.latitude() : 0;
            label.lon = textOK ? anchorLatLng.longitude() : 0;
            label.iconLat = iconOK ? anchorLatLng.latitude() : 0;
            label.iconLon = iconOK ? anchorLatLng.longitude() : 0;
            label.fontSize = symbol.textSize;
            label.textW = textWidth;
            label.textH = textHeight;
            label.iconW = iconWidth;
            label.iconH = iconHeight;
            label.iconSize = symbol.iconSize;
            label.flags = (textOK ? kTextPlaced : 0u) | (iconOK ? kIconPlaced : 0u) |
                          (symbol.alongLine ? kTextAlongLine : 0u) |
                          (symbol.iconAlongLine ? kIconAlongLine : 0u);
            label.textAngle = symbol.textAngle;
            label.iconAngle = symbol.iconAngle;
            label.crossTileID = symbol.crossTileID;
            label.textOffset = text.offset;
            label.textLength = text.length;
            label.logicalTextOffset = logicalText.offset;
            label.logicalTextLength = logicalText.length;
            const auto layerName = appendString(blob, layerID);
            label.layerOffset = layerName.offset;
            label.layerLength = layerName.length;
            label.iconOffset = icon.offset;
            label.iconLength = icon.length;
            label.textFontsOffset = fontsOffset;
            label.textFontCount = static_cast<uint32_t>(symbol.textFontStack.size());
            label.textSectionsOffset = sectionsOffset;
            label.textSectionCount = static_cast<uint32_t>(sections.size());
            label.visualTextSectionsOffset = visualSectionsOffset;
            label.visualTextSectionCount = static_cast<uint32_t>(visualSections.size());
            label.textPathOffset = textPathOffset;
            label.textPathCount = static_cast<uint32_t>(symbol.textPath.size());
            label.iconPathOffset = iconPathOffset;
            label.iconPathCount = static_cast<uint32_t>(symbol.iconPath.size());
            label.textOffsetX = textCenterX;
            label.textOffsetY = textCenterY;
            label.iconOffsetX = iconCenterX;
            label.iconOffsetY = iconCenterY;
            label.letterSpacing = symbol.letterSpacing;
            label.lineHeight = symbol.lineHeight;
            label.maxWidth = symbol.maxWidth;
            label.textRotation = symbol.textRotation;
            label.iconRotation = symbol.iconRotation;
            label.iconFitWidth = symbol.iconFitWidth;
            label.iconFitHeight = symbol.iconFitHeight;
            label.textTransformXX = symbol.textTransform[0];
            label.textTransformXY = symbol.textTransform[1];
            label.textTransformYX = symbol.textTransform[2];
            label.textTransformYY = symbol.textTransform[3];
            label.iconTransformXX = symbol.iconTransform[0];
            label.iconTransformXY = symbol.iconTransform[1];
            label.iconTransformYX = symbol.iconTransform[2];
            label.iconTransformYY = symbol.iconTransform[3];
            const auto layerIndex = layerIndices.find(layerID);
            label.layerIndex = layerIndex == layerIndices.end()
                                   ? std::numeric_limits<int32_t>::max()
                                   : layerIndex->second;
            label.styleFlags = (symbol.vertical ? kVertical : 0u) |
                               (symbol.iconSDF ? kIconSDF : 0u) |
                               (symbol.textPitchAlignment == mbgl::style::AlignmentType::Map ? kTextPitchMap : 0u) |
                               (symbol.textRotationAlignment == mbgl::style::AlignmentType::Map
                                    ? kTextRotationMap
                                    : 0u) |
                               (symbol.iconPitchAlignment == mbgl::style::AlignmentType::Map ? kIconPitchMap : 0u) |
                               (symbol.iconRotationAlignment == mbgl::style::AlignmentType::Map
                                    ? kIconRotationMap
                                    : 0u) |
                               (symbol.textKeepUpright ? kTextKeepUpright : 0u) |
                               (symbol.iconKeepUpright ? kIconKeepUpright : 0u) |
                               (symbol.textRTL ? kTextRTL : 0u);
            label.textJustify = static_cast<uint32_t>(symbol.textJustify);
            label.renderGroup = symbol.renderGroup;
            label.renderOrder = symbol.renderOrder;

            const auto textColor = evaluateProperty(evaluated.get<mbgl::style::TextColor>(),
                                                    zoom,
                                                    feature,
                                                    featureState,
                                                    canonical,
                                                    mbgl::style::SymbolLayer::getDefaultTextColor().asConstant());
            label.textR = textColor.r;
            label.textG = textColor.g;
            label.textB = textColor.b;
            label.textA = textColor.a;
            const auto haloColor = evaluateProperty(
                evaluated.get<mbgl::style::TextHaloColor>(),
                zoom,
                feature,
                featureState,
                canonical,
                mbgl::style::SymbolLayer::getDefaultTextHaloColor().asConstant());
            label.haloR = haloColor.r;
            label.haloG = haloColor.g;
            label.haloB = haloColor.b;
            label.haloA = haloColor.a;
            label.haloWidth = evaluateProperty(
                evaluated.get<mbgl::style::TextHaloWidth>(),
                zoom,
                feature,
                featureState,
                canonical,
                mbgl::style::SymbolLayer::getDefaultTextHaloWidth().asConstant());
            label.textOpacity = evaluateProperty(
                evaluated.get<mbgl::style::TextOpacity>(),
                zoom,
                feature,
                featureState,
                canonical,
                mbgl::style::SymbolLayer::getDefaultTextOpacity().asConstant());
            label.haloBlur = evaluateProperty(
                evaluated.get<mbgl::style::TextHaloBlur>(),
                zoom,
                feature,
                featureState,
                canonical,
                mbgl::style::SymbolLayer::getDefaultTextHaloBlur().asConstant());
            label.iconOpacity = evaluateProperty(
                evaluated.get<mbgl::style::IconOpacity>(),
                zoom,
                feature,
                featureState,
                canonical,
                mbgl::style::SymbolLayer::getDefaultIconOpacity().asConstant());
            const auto iconColor = evaluateProperty(
                evaluated.get<mbgl::style::IconColor>(),
                zoom,
                feature,
                featureState,
                canonical,
                mbgl::style::SymbolLayer::getDefaultIconColor().asConstant());
            label.iconR = iconColor.r;
            label.iconG = iconColor.g;
            label.iconB = iconColor.b;
            label.iconA = iconColor.a;
            const auto iconHaloColor = evaluateProperty(
                evaluated.get<mbgl::style::IconHaloColor>(),
                zoom,
                feature,
                featureState,
                canonical,
                mbgl::style::SymbolLayer::getDefaultIconHaloColor().asConstant());
            label.iconHaloR = iconHaloColor.r;
            label.iconHaloG = iconHaloColor.g;
            label.iconHaloB = iconHaloColor.b;
            label.iconHaloA = iconHaloColor.a;
            label.iconHaloWidth = evaluateProperty(
                evaluated.get<mbgl::style::IconHaloWidth>(),
                zoom,
                feature,
                featureState,
                canonical,
                mbgl::style::SymbolLayer::getDefaultIconHaloWidth().asConstant());
            label.iconHaloBlur = evaluateProperty(
                evaluated.get<mbgl::style::IconHaloBlur>(),
                zoom,
                feature,
                featureState,
                canonical,
                mbgl::style::SymbolLayer::getDefaultIconHaloBlur().asConstant());

            const auto& textTranslate = evaluated.get<mbgl::style::TextTranslate>();
            const auto textTranslateAnchor = evaluated.get<mbgl::style::TextTranslateAnchor>();
            const auto screenTextTranslate =
                resolvePaintTranslation(symbol, &state, textTranslate, textTranslateAnchor);
            label.textTranslateX = screenTextTranslate.x;
            label.textTranslateY = screenTextTranslate.y;

            const auto& iconTranslate = evaluated.get<mbgl::style::IconTranslate>();
            const auto iconTranslateAnchor = evaluated.get<mbgl::style::IconTranslateAnchor>();
            const auto screenIconTranslate =
                resolvePaintTranslation(symbol, &state, iconTranslate, iconTranslateAnchor);
            label.iconTranslateX = screenIconTranslate.x;
            label.iconTranslateY = screenIconTranslate.y;
            labels.push_back(label);
        }
    }

    std::stable_sort(labels.begin(), labels.end(), [](const auto& lhs, const auto& rhs) {
        if (lhs.layerIndex != rhs.layerIndex) return lhs.layerIndex < rhs.layerIndex;
        if (lhs.renderGroup != rhs.renderGroup) return lhs.renderGroup < rhs.renderGroup;
        return lhs.renderOrder < rhs.renderOrder;
    });
    if (!sameBytes(labels, g_labels) || !sameBytes(blob, g_labelBlob)) {
        g_labels = std::move(labels);
        g_labelBlob = std::move(blob);
        ++g_labelsVersion;
    }
}

extern "C" {

MAPLIBRE_API int maplibre_get_label_count(void) {
    return static_cast<int>(g_labels.size());
}

MAPLIBRE_API const void* maplibre_get_labels(void) {
    return g_labels.empty() ? nullptr : g_labels.data();
}

MAPLIBRE_API int maplibre_get_label_stride(void) {
    return static_cast<int>(sizeof(LabelExport));
}

MAPLIBRE_API const void* maplibre_get_label_blob(void) {
    return g_labelBlob.empty() ? nullptr : g_labelBlob.data();
}

MAPLIBRE_API int maplibre_get_label_blob_size(void) {
    return static_cast<int>(g_labelBlob.size());
}

MAPLIBRE_API void maplibre_reproject_labels(float* outXs, float* outYs) {
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
