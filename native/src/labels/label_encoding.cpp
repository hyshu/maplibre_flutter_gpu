#include "label_encoding.hpp"

#if MLN_RENDER_BACKEND_COMMAND_EXPORT

#include <cstring>

namespace maplibre_bridge::labels {

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
                     const mln::FontStack& fonts,
                     std::vector<LabelStringRefExport>& refs) {
    refs.clear();
    refs.reserve(fonts.size());
    for (const auto& font : fonts) refs.push_back(appendString(blob, font));
    return appendRecords(blob, refs);
}

uint32_t appendSections(std::vector<uint8_t>& blob,
                        const std::vector<mln::ShapingTextSection>& sections,
                        const mln::FontStack& fallbackFonts,
                        std::size_t fallbackLength,
                        std::vector<LabelStringRefExport>& fontRefs,
                        std::vector<LabelTextSectionExport>& records) {
    records.clear();
    const std::size_t count = sections.empty() && fallbackLength > 0 ? 1 : sections.size();
    records.reserve(count);
    const auto appendSection = [&](uint32_t start,
                                   uint32_t end,
                                   double scale,
                                   const mln::FontStack& fonts,
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
                          static_cast<const mln::Color*>(nullptr),
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
                    const std::vector<mln::Point<float>>& path,
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

const std::u16string& visualText(const mln::PlacedSymbolData& symbol) {
    return symbol.lineBrokenText.empty() ? symbol.key : symbol.lineBrokenText;
}

const std::u16string& logicalText(const mln::PlacedSymbolData& symbol) {
    const auto& visual = visualText(symbol);
    return symbol.logicalLineBrokenText.empty() ? visual : symbol.logicalLineBrokenText;
}

StaticContentRefs appendStaticContent(std::vector<uint8_t>& blob,
                                      const mln::PlacedSymbolData& symbol,
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

} // namespace maplibre_bridge::labels

#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT
