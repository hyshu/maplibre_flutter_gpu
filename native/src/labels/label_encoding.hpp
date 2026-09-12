// Encoding of session-owned label records and their variable-size blobs.
#pragma once

#if MLN_RENDER_BACKEND_COMMAND_EXPORT

#include "label_export.hpp"

#include <cstddef>
#include <string>
#include <vector>

#include <mbgl/renderer/renderer.hpp>

namespace maplibre_bridge::labels {

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

void alignBlob(std::vector<uint8_t>& blob, std::size_t alignment);

// Path coordinates are relative to the supplied viewport origin.
uint32_t appendPath(std::vector<uint8_t>& blob,
                    const std::vector<mbgl::Point<float>>& path,
                    float originX,
                    float originY);

const std::u16string& visualText(const mbgl::PlacedSymbolData& symbol);
const std::u16string& logicalText(const mbgl::PlacedSymbolData& symbol);

StaticContentRefs appendStaticContent(std::vector<uint8_t>& blob,
                                      const mbgl::PlacedSymbolData& symbol,
                                      std::string& utf8,
                                      std::vector<LabelStringRefExport>& fontRefs,
                                      std::vector<LabelTextSectionExport>& sectionRecords);
void applyStaticContent(LabelStaticExport& record,
                        std::vector<uint8_t>& blob,
                        const std::string& layer,
                        const StaticContentRefs& refs);

// Splits scalar style and frame geometry before blob references are assigned.
LabelStaticExport staticRecord(const LabelExport& label);
void copyContentRefs(LabelStaticExport& target, const LabelStaticExport& source);
LabelDynamicExport dynamicRecord(const LabelExport& label, uint32_t staticIndex);
LabelExport legacyRecord(const LabelStaticExport& statik, const LabelDynamicExport& dynamic);

} // namespace maplibre_bridge::labels

#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT
