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
#include <type_traits>
#include <unordered_map>
#include <utility>
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
    int32_t tileWrap;
};
static_assert(sizeof(LabelExport) == 352, "LabelExport size must be stable for FFI");

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
COMMAND_EXPORT_ABI_OFFSET(LabelExport, tileWrap, 344);

// Variable-size values use byte offsets into the static label blob.
struct LabelStaticExport {
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
    float iconSize;
    float iconOpacity;
    float iconR;
    float iconG;
    float iconB;
    float iconA;
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
    float textOpacity;
    float haloBlur;
    float letterSpacing;
    float lineHeight;
    float maxWidth;
    float textRotation;
    float iconRotation;
    float iconHaloR;
    float iconHaloG;
    float iconHaloB;
    float iconHaloA;
    float iconHaloWidth;
    float iconHaloBlur;
    float iconFitWidth;
    float iconFitHeight;
    int32_t layerIndex;
    uint32_t styleFlags;
    uint32_t textJustify;
    uint32_t renderGroup;
    uint32_t logicalTextOffset;
    uint32_t logicalTextLength;
    uint32_t visualTextSectionsOffset;
    uint32_t visualTextSectionCount;
};
static_assert(sizeof(LabelStaticExport) == 200, "LabelStaticExport size must be stable for FFI");
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, fontSize, 0);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textR, 4);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textG, 8);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textB, 12);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textA, 16);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, haloR, 20);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, haloG, 24);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, haloB, 28);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, haloA, 32);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, haloWidth, 36);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconSize, 40);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconOpacity, 44);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconR, 48);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconG, 52);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconB, 56);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconA, 60);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, crossTileID, 64);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textOffset, 68);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textLength, 72);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, layerOffset, 76);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, layerLength, 80);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconOffset, 84);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconLength, 88);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textFontsOffset, 92);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textFontCount, 96);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textSectionsOffset, 100);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textSectionCount, 104);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textOpacity, 108);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, haloBlur, 112);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, letterSpacing, 116);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, lineHeight, 120);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, maxWidth, 124);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textRotation, 128);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconRotation, 132);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconHaloR, 136);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconHaloG, 140);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconHaloB, 144);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconHaloA, 148);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconHaloWidth, 152);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconHaloBlur, 156);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconFitWidth, 160);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, iconFitHeight, 164);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, layerIndex, 168);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, styleFlags, 172);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, textJustify, 176);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, renderGroup, 180);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, logicalTextOffset, 184);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, logicalTextLength, 188);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, visualTextSectionsOffset, 192);
COMMAND_EXPORT_ABI_OFFSET(LabelStaticExport, visualTextSectionCount, 196);

// Path offsets use the dynamic blob and staticIndex joins cached content.
struct LabelDynamicExport {
    double lat;
    double lon;
    double iconLat;
    double iconLon;
    float textW;
    float textH;
    float iconW;
    float iconH;
    uint32_t flags;
    float textAngle;
    uint32_t textPathOffset;
    uint32_t textPathCount;
    uint32_t iconPathOffset;
    uint32_t iconPathCount;
    float textOffsetX;
    float textOffsetY;
    float iconOffsetX;
    float iconOffsetY;
    float iconAngle;
    float textTranslateX;
    float textTranslateY;
    float iconTranslateX;
    float iconTranslateY;
    float textTransformXX;
    float textTransformXY;
    float textTransformYX;
    float textTransformYY;
    float iconTransformXX;
    float iconTransformXY;
    float iconTransformYX;
    float iconTransformYY;
    uint32_t renderOrder;
    uint32_t staticIndex;
    int32_t tileWrap;
};
static_assert(sizeof(LabelDynamicExport) == 152, "LabelDynamicExport size must be stable for FFI");
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, lat, 0);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, lon, 8);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconLat, 16);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconLon, 24);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textW, 32);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textH, 36);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconW, 40);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconH, 44);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, flags, 48);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textAngle, 52);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textPathOffset, 56);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textPathCount, 60);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconPathOffset, 64);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconPathCount, 68);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textOffsetX, 72);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textOffsetY, 76);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconOffsetX, 80);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconOffsetY, 84);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconAngle, 88);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textTranslateX, 92);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textTranslateY, 96);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconTranslateX, 100);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconTranslateY, 104);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textTransformXX, 108);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textTransformXY, 112);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textTransformYX, 116);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, textTransformYY, 120);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconTransformXX, 124);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconTransformXY, 128);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconTransformYX, 132);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, iconTransformYY, 136);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, renderOrder, 140);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, staticIndex, 144);
COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, tileWrap, 148);

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

void utf8FromUTF16(const std::u16string& input, std::string& result) {
    result.clear();
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

uint32_t appendFonts(std::vector<uint8_t>& blob,
                     const mbgl::FontStack& fonts,
                     std::vector<LabelStringRefExport>& refs) {
    refs.clear();
    refs.reserve(fonts.size());
    for (const auto& font : fonts) refs.push_back(appendString(blob, font));
    return appendRecords(blob, refs);
}

uint32_t appendSections(std::vector<uint8_t>& blob,
                        const std::vector<mbgl::ShapingTextSection>& sections,
                        const mbgl::FontStack& fallbackFonts,
                        std::size_t fallbackLength,
                        std::vector<LabelStringRefExport>& fontRefs,
                        std::vector<LabelTextSectionExport>& records) {
    records.clear();
    const std::size_t count = sections.empty() && fallbackLength > 0 ? 1 : sections.size();
    records.reserve(count);
    const auto appendSection = [&](uint32_t start,
                                   uint32_t end,
                                   double scale,
                                   const mbgl::FontStack& fonts,
                                   const auto* textColor,
                                   const std::string* imageID) {
        LabelTextSectionExport record{};
        record.start = start;
        record.end = end;
        record.fontScale = static_cast<float>(scale);
        record.fontsOffset = appendFonts(blob, fonts, fontRefs);
        record.fontCount = static_cast<uint32_t>(fonts.size());
        if (textColor) {
            record.flags |= kSectionHasColor;
            record.colorR = textColor->r;
            record.colorG = textColor->g;
            record.colorB = textColor->b;
            record.colorA = textColor->a;
        }
        if (imageID) {
            record.flags |= kSectionHasImage;
            const auto image = appendString(blob, *imageID);
            record.imageOffset = image.offset;
            record.imageLength = image.length;
        }
        records.push_back(record);
    };
    if (sections.empty()) {
        if (fallbackLength > 0) {
            appendSection(0,
                          static_cast<uint32_t>(fallbackLength),
                          1.0,
                          fallbackFonts,
                          static_cast<const mbgl::Color*>(nullptr),
                          nullptr);
        }
    } else {
        for (const auto& section : sections) {
            const auto& fonts = section.fontStack.empty() ? fallbackFonts : section.fontStack;
            appendSection(section.start,
                          section.end,
                          section.scale,
                          fonts,
                          section.textColor ? &*section.textColor : nullptr,
                          section.imageID ? &*section.imageID : nullptr);
        }
    }
    return appendRecords(blob, records);
}

uint32_t appendPath(std::vector<uint8_t>& blob,
                    const std::vector<mbgl::Point<float>>& path,
                    float originX,
                    float originY) {
    if (path.empty()) return 0;
    alignBlob(blob, alignof(LabelPathPointExport));
    const auto offset = static_cast<uint32_t>(blob.size());
    blob.resize(blob.size() + path.size() * sizeof(LabelPathPointExport));
    for (std::size_t i = 0; i < path.size(); ++i) {
        const LabelPathPointExport record{path[i].x - originX, path[i].y - originY};
        std::memcpy(blob.data() + offset + i * sizeof(record), &record, sizeof(record));
    }
    return offset;
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

struct PendingLabel {
    LabelExport label{};
    const mbgl::PlacedSymbolData* symbol = nullptr;
    const std::string* layer = nullptr;
    std::size_t frameSymbolIndex = 0;
    uint64_t layerHash = 0;
};

struct StaticContentRefs {
    LabelStringRefExport text{};
    LabelStringRefExport logicalText{};
    LabelStringRefExport icon{};
    uint32_t fontsOffset = 0;
    uint32_t fontCount = 0;
    uint32_t sectionsOffset = 0;
    uint32_t sectionCount = 0;
    uint32_t visualSectionsOffset = 0;
    uint32_t visualSectionCount = 0;
};

struct PathRefs {
    uint32_t textOffset = 0;
    uint32_t textCount = 0;
    uint32_t iconOffset = 0;
    uint32_t iconCount = 0;
};

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

bool expressionUsesFeatureState(const mbgl::style::expression::Expression& expression) {
    if (expression.getOperator() == "feature-state") return true;

    bool usesFeatureState = false;
    expression.eachChild([&](const mbgl::style::expression::Expression& child) {
        if (!usesFeatureState) usesFeatureState = expressionUsesFeatureState(child);
    });
    return usesFeatureState;
}

template <typename T>
struct PaintPropertyPlan {
    const mbgl::style::PropertyExpression<T>* dynamic = nullptr;
    T constant{};
};

template <typename T>
PaintPropertyPlan<T> planPaintProperty(const mbgl::PossiblyEvaluatedPropertyValue<T>& property,
                                       uint16_t bit,
                                       uint16_t& dynamicMask,
                                       uint16_t& featureStateMask) {
    PaintPropertyPlan<T> result;
    property.match(
        [&](const T& value) { result.constant = value; },
        [&](const mbgl::style::PropertyExpression<T>& expression) {
            result.dynamic = &expression;
            dynamicMask |= bit;
            if (expressionUsesFeatureState(expression.getExpression())) featureStateMask |= bit;
        });
    return result;
}

struct LayerPaintPlan {
    // Pointer members borrow storage that remains valid for the current extraction.
    const std::string* layer = nullptr;
    int32_t layerIndex = std::numeric_limits<int32_t>::max();
    uint64_t layerHash = 0;
    uint16_t dynamicMask = 0;
    uint16_t featureStateMask = 0;
    PaintPropertyPlan<mbgl::Color> textColor;
    PaintPropertyPlan<mbgl::Color> textHaloColor;
    PaintPropertyPlan<float> textHaloWidth;
    PaintPropertyPlan<float> textOpacity;
    PaintPropertyPlan<float> textHaloBlur;
    PaintPropertyPlan<float> iconOpacity;
    PaintPropertyPlan<mbgl::Color> iconColor;
    PaintPropertyPlan<mbgl::Color> iconHaloColor;
    PaintPropertyPlan<float> iconHaloWidth;
    PaintPropertyPlan<float> iconHaloBlur;
    std::array<float, 2> textTranslate{};
    mbgl::style::TranslateAnchorType textTranslateAnchor = mbgl::style::TranslateAnchorType::Map;
    std::array<float, 2> iconTranslate{};
    mbgl::style::TranslateAnchorType iconTranslateAnchor = mbgl::style::TranslateAnchorType::Map;
};

template <typename T, typename DefaultValue>
T evaluatePlannedPaintProperty(const PaintPropertyPlan<T>& property,
                               uint16_t bit,
                               const LayerPaintPlan& layer,
                               float zoom,
                               const ExportFeature& feature,
                               const mbgl::FeatureState& state,
                               const mbgl::CanonicalTileID& canonical,
                               DefaultValue&& defaultValue) {
    if ((layer.dynamicMask & bit) == 0) return property.constant;
    auto context = mbgl::style::expression::EvaluationContext(zoom, &feature, &state);
    context.withCanonicalTileID(&canonical);
    return property.dynamic->evaluate(context, std::forward<DefaultValue>(defaultValue)());
}

LabelStaticExport staticRecord(const LabelExport& label) {
    LabelStaticExport result{};
    result.fontSize = label.fontSize;
    result.textR = label.textR;
    result.textG = label.textG;
    result.textB = label.textB;
    result.textA = label.textA;
    result.haloR = label.haloR;
    result.haloG = label.haloG;
    result.haloB = label.haloB;
    result.haloA = label.haloA;
    result.haloWidth = label.haloWidth;
    result.iconSize = label.iconSize;
    result.iconOpacity = label.iconOpacity;
    result.iconR = label.iconR;
    result.iconG = label.iconG;
    result.iconB = label.iconB;
    result.iconA = label.iconA;
    result.crossTileID = label.crossTileID;
    result.textOpacity = label.textOpacity;
    result.haloBlur = label.haloBlur;
    result.letterSpacing = label.letterSpacing;
    result.lineHeight = label.lineHeight;
    result.maxWidth = label.maxWidth;
    result.textRotation = label.textRotation;
    result.iconRotation = label.iconRotation;
    result.iconHaloR = label.iconHaloR;
    result.iconHaloG = label.iconHaloG;
    result.iconHaloB = label.iconHaloB;
    result.iconHaloA = label.iconHaloA;
    result.iconHaloWidth = label.iconHaloWidth;
    result.iconHaloBlur = label.iconHaloBlur;
    result.iconFitWidth = label.iconFitWidth;
    result.iconFitHeight = label.iconFitHeight;
    result.layerIndex = label.layerIndex;
    result.styleFlags = label.styleFlags;
    result.textJustify = label.textJustify;
    result.renderGroup = label.renderGroup;
    return result;
}

void copyContentRefs(LabelStaticExport& target, const LabelStaticExport& source) {
    target.textOffset = source.textOffset;
    target.textLength = source.textLength;
    target.layerOffset = source.layerOffset;
    target.layerLength = source.layerLength;
    target.iconOffset = source.iconOffset;
    target.iconLength = source.iconLength;
    target.textFontsOffset = source.textFontsOffset;
    target.textFontCount = source.textFontCount;
    target.textSectionsOffset = source.textSectionsOffset;
    target.textSectionCount = source.textSectionCount;
    target.logicalTextOffset = source.logicalTextOffset;
    target.logicalTextLength = source.logicalTextLength;
    target.visualTextSectionsOffset = source.visualTextSectionsOffset;
    target.visualTextSectionCount = source.visualTextSectionCount;
}

LabelDynamicExport dynamicRecord(const LabelExport& label, uint32_t staticIndex) {
    LabelDynamicExport result{};
    result.lat = label.lat;
    result.lon = label.lon;
    result.iconLat = label.iconLat;
    result.iconLon = label.iconLon;
    result.textW = label.textW;
    result.textH = label.textH;
    result.iconW = label.iconW;
    result.iconH = label.iconH;
    result.flags = label.flags;
    result.textAngle = label.textAngle;
    result.textOffsetX = label.textOffsetX;
    result.textOffsetY = label.textOffsetY;
    result.iconOffsetX = label.iconOffsetX;
    result.iconOffsetY = label.iconOffsetY;
    result.iconAngle = label.iconAngle;
    result.textTranslateX = label.textTranslateX;
    result.textTranslateY = label.textTranslateY;
    result.iconTranslateX = label.iconTranslateX;
    result.iconTranslateY = label.iconTranslateY;
    result.textTransformXX = label.textTransformXX;
    result.textTransformXY = label.textTransformXY;
    result.textTransformYX = label.textTransformYX;
    result.textTransformYY = label.textTransformYY;
    result.iconTransformXX = label.iconTransformXX;
    result.iconTransformXY = label.iconTransformXY;
    result.iconTransformYX = label.iconTransformYX;
    result.iconTransformYY = label.iconTransformYY;
    result.renderOrder = label.renderOrder;
    result.staticIndex = staticIndex;
    result.tileWrap = label.tileWrap;
    return result;
}

LabelExport legacyRecord(const LabelStaticExport& statik, const LabelDynamicExport& dynamic) {
    LabelExport result{};
    result.lat = dynamic.lat;
    result.lon = dynamic.lon;
    result.iconLat = dynamic.iconLat;
    result.iconLon = dynamic.iconLon;
    result.fontSize = statik.fontSize;
    result.textR = statik.textR;
    result.textG = statik.textG;
    result.textB = statik.textB;
    result.textA = statik.textA;
    result.haloR = statik.haloR;
    result.haloG = statik.haloG;
    result.haloB = statik.haloB;
    result.haloA = statik.haloA;
    result.haloWidth = statik.haloWidth;
    result.textW = dynamic.textW;
    result.textH = dynamic.textH;
    result.iconW = dynamic.iconW;
    result.iconH = dynamic.iconH;
    result.iconSize = statik.iconSize;
    result.iconOpacity = statik.iconOpacity;
    result.iconR = statik.iconR;
    result.iconG = statik.iconG;
    result.iconB = statik.iconB;
    result.iconA = statik.iconA;
    result.flags = dynamic.flags;
    result.textAngle = dynamic.textAngle;
    result.crossTileID = statik.crossTileID;
    result.textOffset = statik.textOffset;
    result.textLength = statik.textLength;
    result.layerOffset = statik.layerOffset;
    result.layerLength = statik.layerLength;
    result.iconOffset = statik.iconOffset;
    result.iconLength = statik.iconLength;
    result.textFontsOffset = statik.textFontsOffset;
    result.textFontCount = statik.textFontCount;
    result.textSectionsOffset = statik.textSectionsOffset;
    result.textSectionCount = statik.textSectionCount;
    result.textPathOffset = dynamic.textPathOffset;
    result.textPathCount = dynamic.textPathCount;
    result.iconPathOffset = dynamic.iconPathOffset;
    result.iconPathCount = dynamic.iconPathCount;
    result.textOffsetX = dynamic.textOffsetX;
    result.textOffsetY = dynamic.textOffsetY;
    result.iconOffsetX = dynamic.iconOffsetX;
    result.iconOffsetY = dynamic.iconOffsetY;
    result.textOpacity = statik.textOpacity;
    result.haloBlur = statik.haloBlur;
    result.letterSpacing = statik.letterSpacing;
    result.lineHeight = statik.lineHeight;
    result.maxWidth = statik.maxWidth;
    result.iconAngle = dynamic.iconAngle;
    result.textRotation = statik.textRotation;
    result.iconRotation = statik.iconRotation;
    result.textTranslateX = dynamic.textTranslateX;
    result.textTranslateY = dynamic.textTranslateY;
    result.iconTranslateX = dynamic.iconTranslateX;
    result.iconTranslateY = dynamic.iconTranslateY;
    result.iconHaloR = statik.iconHaloR;
    result.iconHaloG = statik.iconHaloG;
    result.iconHaloB = statik.iconHaloB;
    result.iconHaloA = statik.iconHaloA;
    result.iconHaloWidth = statik.iconHaloWidth;
    result.iconHaloBlur = statik.iconHaloBlur;
    result.iconFitWidth = statik.iconFitWidth;
    result.iconFitHeight = statik.iconFitHeight;
    result.textTransformXX = dynamic.textTransformXX;
    result.textTransformXY = dynamic.textTransformXY;
    result.textTransformYX = dynamic.textTransformYX;
    result.textTransformYY = dynamic.textTransformYY;
    result.iconTransformXX = dynamic.iconTransformXX;
    result.iconTransformXY = dynamic.iconTransformXY;
    result.iconTransformYX = dynamic.iconTransformYX;
    result.iconTransformYY = dynamic.iconTransformYY;
    result.layerIndex = statik.layerIndex;
    result.styleFlags = statik.styleFlags;
    result.textJustify = statik.textJustify;
    result.renderGroup = statik.renderGroup;
    result.renderOrder = dynamic.renderOrder;
    result.logicalTextOffset = statik.logicalTextOffset;
    result.logicalTextLength = statik.logicalTextLength;
    result.visualTextSectionsOffset = statik.visualTextSectionsOffset;
    result.visualTextSectionCount = statik.visualTextSectionCount;
    result.tileWrap = dynamic.tileWrap;
    return result;
}

uint64_t hashBytes(uint64_t hash, const void* data, std::size_t size) {
    constexpr uint64_t prime = 1099511628211ull;
    const auto* bytes = static_cast<const uint8_t*>(data);
    for (std::size_t i = 0; i < size; ++i) {
        hash ^= bytes[i];
        hash *= prime;
    }
    return hash;
}

template <typename T>
uint64_t hashValue(uint64_t hash, const T& value) {
    return hashBytes(hash, &value, sizeof(value));
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

const std::u16string& visualText(const mbgl::PlacedSymbolData& symbol) {
    return symbol.lineBrokenText.empty() ? symbol.key : symbol.lineBrokenText;
}

const std::u16string& logicalText(const mbgl::PlacedSymbolData& symbol) {
    const auto& visual = visualText(symbol);
    return symbol.logicalLineBrokenText.empty() ? visual : symbol.logicalLineBrokenText;
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

SymbolContentKey contentKey(const mbgl::PlacedSymbolData& symbol) {
    return {symbol.bucketInstanceID, symbol.symbolInstanceIndex, symbol.crossTileID};
}

struct SymbolContentCacheEntry {
    uint64_t hash = 0;
    uint64_t lastSeenGeneration = 0;
};

struct FrameSymbolScratch {
    const mbgl::PlacedSymbolData* symbol = nullptr;
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
    mbgl::mat4 tile;
    mbgl::mat4 translated;
};

struct BucketLayerPlanCacheEntry {
    // Plan indices are rebuilt before an entry is read in a new extraction generation.
    std::vector<std::size_t> plans;
    uint64_t lastSeenGeneration = 0;
};

uint64_t contentHash(const PendingLabel& pending, uint64_t sharedHash) {
    return hashValue(sharedHash, pending.layerHash);
}

StaticContentRefs appendStaticContent(std::vector<uint8_t>& blob,
                                      const mbgl::PlacedSymbolData& symbol,
                                      std::string& utf8,
                                      std::vector<LabelStringRefExport>& fontRefs,
                                      std::vector<LabelTextSectionExport>& sectionRecords) {
    const auto& visual = visualText(symbol);
    const auto& logical = logicalText(symbol);
    utf8FromUTF16(visual, utf8);
    StaticContentRefs refs{
        .text = appendString(blob, utf8),
    };
    utf8FromUTF16(logical, utf8);
    refs.logicalText = appendString(blob, utf8);
    refs.icon = appendString(blob, symbol.icon);
    refs.fontsOffset = appendFonts(blob, symbol.textFontStack, fontRefs);
    refs.fontCount = static_cast<uint32_t>(symbol.textFontStack.size());
    refs.sectionsOffset = appendSections(blob,
                                         symbol.textSections,
                                         symbol.textFontStack,
                                         logical.size(),
                                         fontRefs,
                                         sectionRecords);
    refs.sectionCount = static_cast<uint32_t>(
        symbol.textSections.empty() && !logical.empty() ? 1 : symbol.textSections.size());
    refs.visualSectionsOffset = appendSections(blob,
                                               symbol.visualTextSections,
                                               symbol.textFontStack,
                                               visual.size(),
                                               fontRefs,
                                               sectionRecords);
    refs.visualSectionCount = static_cast<uint32_t>(
        symbol.visualTextSections.empty() && !visual.empty() ? 1 : symbol.visualTextSections.size());
    return refs;
}

void applyStaticContent(LabelStaticExport& record,
                        std::vector<uint8_t>& blob,
                        const std::string& layer,
                        const StaticContentRefs& refs) {
    record.textOffset = refs.text.offset;
    record.textLength = refs.text.length;
    record.logicalTextOffset = refs.logicalText.offset;
    record.logicalTextLength = refs.logicalText.length;
    record.iconOffset = refs.icon.offset;
    record.iconLength = refs.icon.length;
    record.textFontsOffset = refs.fontsOffset;
    record.textFontCount = refs.fontCount;
    record.textSectionsOffset = refs.sectionsOffset;
    record.textSectionCount = refs.sectionCount;
    record.visualTextSectionsOffset = refs.visualSectionsOffset;
    record.visualTextSectionCount = refs.visualSectionCount;
    const auto layerRef = appendString(blob, layer);
    record.layerOffset = layerRef.offset;
    record.layerLength = layerRef.length;
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
    std::unordered_map<FeatureStateKey, mbgl::FeatureState, FeatureStateKeyHash> featureStates;
    mbgl::FeatureState emptyFeatureState;
    std::unordered_map<PaintTranslationKey,
                       PaintTranslationMatrices,
                       PaintTranslationKeyHash>
        paintTranslationMatrices;

    void beginFrame() {
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

    uint64_t cachedSharedContentHash(FrameSymbolScratch& frameSymbol) {
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

    void pruneContentHashCache() {
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

    void pruneBucketLayerPlans() {
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

    void materializeLegacy() {
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
};

LayerPaintPlan makeLayerPaintPlan(
    const std::string* layer,
    int32_t layerIndex,
    uint64_t layerHash,
    const mbgl::style::SymbolPaintProperties::PossiblyEvaluated& evaluated) {
    LayerPaintPlan result{
        .layer = layer,
        .layerIndex = layerIndex,
        .layerHash = layerHash,
    };
    result.textColor = planPaintProperty(
        evaluated.get<mbgl::style::TextColor>(),
        kTextColorDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.textHaloColor = planPaintProperty(
        evaluated.get<mbgl::style::TextHaloColor>(),
        kTextHaloColorDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.textHaloWidth = planPaintProperty(
        evaluated.get<mbgl::style::TextHaloWidth>(),
        kTextHaloWidthDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.textOpacity = planPaintProperty(
        evaluated.get<mbgl::style::TextOpacity>(),
        kTextOpacityDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.textHaloBlur = planPaintProperty(
        evaluated.get<mbgl::style::TextHaloBlur>(),
        kTextHaloBlurDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.iconOpacity = planPaintProperty(
        evaluated.get<mbgl::style::IconOpacity>(),
        kIconOpacityDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.iconColor = planPaintProperty(
        evaluated.get<mbgl::style::IconColor>(),
        kIconColorDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.iconHaloColor = planPaintProperty(
        evaluated.get<mbgl::style::IconHaloColor>(),
        kIconHaloColorDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.iconHaloWidth = planPaintProperty(
        evaluated.get<mbgl::style::IconHaloWidth>(),
        kIconHaloWidthDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.iconHaloBlur = planPaintProperty(
        evaluated.get<mbgl::style::IconHaloBlur>(),
        kIconHaloBlurDynamic,
        result.dynamicMask,
        result.featureStateMask);
    result.textTranslate = evaluated.get<mbgl::style::TextTranslate>();
    result.textTranslateAnchor = evaluated.get<mbgl::style::TextTranslateAnchor>();
    result.iconTranslate = evaluated.get<mbgl::style::IconTranslate>();
    result.iconTranslateAnchor = evaluated.get<mbgl::style::IconTranslateAnchor>();
    return result;
}

void appendCandidateLayerPlans(LabelSessionState& session,
                               const mbgl::PlacedSymbolData& symbol,
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
                                                    const mbgl::PlacedSymbolData& symbol) {
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

const mbgl::FeatureState& featureStateForSymbol(LabelSessionState& session,
                                                const mbgl::PlacedSymbolData& symbol,
                                                const mbgl::Renderer& renderer) {
    const auto featureID = mbgl::featureIDtoString(symbol.featureID);
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

mbgl::Point<float> resolvePlannedPaintTranslation(LabelSessionState& session,
                                                  std::size_t layerPlanIndex,
                                                  uint8_t component,
                                                  const mbgl::PlacedSymbolData& symbol,
                                                  const mbgl::TransformState& state,
                                                  const std::array<float, 2>& translation,
                                                  mbgl::style::TranslateAnchorType anchor) {
    if (anchor == mbgl::style::TranslateAnchorType::Viewport ||
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
        const mbgl::UnwrappedTileID tileID{
            symbol.tileWrap,
            mbgl::CanonicalTileID{symbol.canonicalZ, symbol.canonicalX, symbol.canonicalY}};
        state.matrixFor(matrices.tile, tileID);
        mbgl::matrix::multiply(matrices.tile, state.getProjectionMatrix(), matrices.tile);
        matrices.translated = mbgl::RenderTile::translateVtxMatrix(
            tileID, matrices.tile, translation, anchor, state, false);
    }

    const auto before = projectToScreen(state, matrices.tile, symbol.tileAnchor);
    const auto after = projectToScreen(state, matrices.translated, symbol.tileAnchor);
    return after - before;
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

} // namespace

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

void bridge_extractLabels(const mbgl::TransformState* renderedState) {
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
            rawLayer->getVisibility() != mbgl::style::VisibilityType::Visible ||
            zoom < rawLayer->getMinZoom() || zoom >= rawLayer->getMaxZoom()) {
            continue;
        }
        auto layerID = rawLayer->getID();
        const auto* evaluatedLayer = renderer->getEvaluatedLayerProperties(layerID);
        if (!evaluatedLayer) continue;
        const auto& evaluated =
            static_cast<const mbgl::style::SymbolLayerProperties&>(*evaluatedLayer).evaluated;
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
        const mbgl::CanonicalTileID canonical{symbol.canonicalZ, symbol.canonicalX, symbol.canonicalY};
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
                [] { return mbgl::style::SymbolLayer::getDefaultTextColor().asConstant(); });
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
                [] { return mbgl::style::SymbolLayer::getDefaultTextHaloColor().asConstant(); });
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
                [] { return mbgl::style::SymbolLayer::getDefaultTextHaloWidth().asConstant(); });
            label.textOpacity = evaluatePlannedPaintProperty(
                layer.textOpacity,
                kTextOpacityDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mbgl::style::SymbolLayer::getDefaultTextOpacity().asConstant(); });
            label.haloBlur = evaluatePlannedPaintProperty(
                layer.textHaloBlur,
                kTextHaloBlurDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mbgl::style::SymbolLayer::getDefaultTextHaloBlur().asConstant(); });
            label.iconOpacity = evaluatePlannedPaintProperty(
                layer.iconOpacity,
                kIconOpacityDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mbgl::style::SymbolLayer::getDefaultIconOpacity().asConstant(); });
            const auto iconColor = evaluatePlannedPaintProperty(
                layer.iconColor,
                kIconColorDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mbgl::style::SymbolLayer::getDefaultIconColor().asConstant(); });
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
                [] { return mbgl::style::SymbolLayer::getDefaultIconHaloColor().asConstant(); });
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
                [] { return mbgl::style::SymbolLayer::getDefaultIconHaloWidth().asConstant(); });
            label.iconHaloBlur = evaluatePlannedPaintProperty(
                layer.iconHaloBlur,
                kIconHaloBlurDynamic,
                layer,
                zoom,
                feature,
                featureState,
                canonical,
                [] { return mbgl::style::SymbolLayer::getDefaultIconHaloBlur().asConstant(); });

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
