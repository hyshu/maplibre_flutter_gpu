// Evaluated paint values borrowed during one label extraction.
#pragma once

#if MLN_RENDER_BACKEND_COMMAND_EXPORT

#include <array>
#include <cstdint>
#include <limits>
#include <string>

#include <mln/renderer/possibly_evaluated_property_value.hpp>
#include <mln/style/types.hpp>

namespace maplibre_bridge::labels {

template <typename T>
struct PaintPropertyPlan {
    const mln::style::PropertyExpression<T>* dynamic = nullptr;
    T constant{};
};

struct LayerPaintPlan {
    // Pointer members borrow storage that remains valid for the current extraction.
    const std::string* layer = nullptr;
    int32_t layerIndex = std::numeric_limits<int32_t>::max();
    uint64_t layerHash = 0;
    uint16_t dynamicMask = 0;
    uint16_t featureStateMask = 0;
    PaintPropertyPlan<mln::Color> textColor;
    PaintPropertyPlan<mln::Color> textHaloColor;
    PaintPropertyPlan<float> textHaloWidth;
    PaintPropertyPlan<float> textOpacity;
    PaintPropertyPlan<float> textHaloBlur;
    PaintPropertyPlan<float> iconOpacity;
    PaintPropertyPlan<mln::Color> iconColor;
    PaintPropertyPlan<mln::Color> iconHaloColor;
    PaintPropertyPlan<float> iconHaloWidth;
    PaintPropertyPlan<float> iconHaloBlur;
    std::array<float, 2> textTranslate{};
    mln::style::TranslateAnchorType textTranslateAnchor = mln::style::TranslateAnchorType::Map;
    std::array<float, 2> iconTranslate{};
    mln::style::TranslateAnchorType iconTranslateAnchor = mln::style::TranslateAnchorType::Map;
};

} // namespace maplibre_bridge::labels

#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT
