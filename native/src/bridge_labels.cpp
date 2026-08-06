// Label extraction from placed symbol data, exported to Dart via FFI.
#if MLN_RENDER_BACKEND_COMMAND_EXPORT

#include "bridge_state.hpp"

#include <mbgl/renderer/renderer.hpp>
#include <mbgl/style/style.hpp>
#include <mbgl/style/layer.hpp>
#include <mbgl/style/layers/symbol_layer.hpp>

#include <map>
#include <mbgl/map/transform_state.hpp>

#include <cstring>
#include <string>
#include <vector>

// ── LabelExport: stable symbol data passed to Dart ───────────────────
// One entry per placed symbol. The geographic anchor follows the map while
// collision-center offsets remain in screen pixels, matching native symbols
// during zoom.
struct LabelExport {
    double lat;        //   0: text geographic anchor latitude
    double lon;        //   8: text geographic anchor longitude
    double iconLat;    //  16: icon geographic anchor latitude
    double iconLon;    //  24: icon geographic anchor longitude
    float fontSize;    //  32: feature/zoom-evaluated size used by MapLibre placement
    float textR;       //  36: text-color R (premultiplied)
    float textG;       //  40
    float textB;       //  44
    float textA;       //  48
    float haloR;       //  52: text-halo-color R
    float haloG;       //  56
    float haloB;       //  60
    float haloA;       //  64
    float haloWidth;   //  68: text-halo-width (pixels)
    float textW;       //  72: text collision box width (px, sans padding)
    float textH;       //  76: text collision box height
    float iconW;       //  80: icon collision box width (px, sans padding)
    float iconH;       //  84: icon collision box height
    float iconSize;    //  88: feature/zoom-evaluated size used by MapLibre placement
    float iconOpacity; //  92: evaluated icon-opacity
    float iconR;       //  96: icon-color (for SDF icons)
    float iconG;       // 100
    float iconB;       // 104
    float iconA;       // 108
    uint32_t flags;       // 112: bit0 = textPlaced, bit1 = iconPlaced, bit2 = alongLine
    float textAngle;      // 116: label angle in radians (line placement only)
    uint32_t crossTileID; // 120: stable MapLibre symbol identity
    char text[128];       // 124: UTF-8 text, null-terminated
    char layer[64];       // 252: layer ID, null-terminated
    char icon[64];        // 316: icon-image ID, null-terminated
    float textOffsetX;    // 380: text center offset from map anchor (screen px)
    float textOffsetY;    // 384
    float iconOffsetX;    // 388: icon center offset from map anchor (screen px)
    float iconOffsetY;    // 392
    float textOpacity;    // 396: evaluated text-opacity
    float haloBlur;       // 400: evaluated text-halo-blur (pixels)
    float letterSpacing;  // 404: evaluated text-letter-spacing (ems)
    float lineHeight;     // 408: evaluated text-line-height (ems)
    float maxWidth;       // 412: evaluated text-max-width (ems)
    char textFont[68];    // 416: first evaluated text-font stack entry
};
static_assert(sizeof(LabelExport) == 488, "LabelExport size must be stable for FFI");

// ABI offset locks — see draw_command.hpp. tool/gen_abi.dart parses these
// to generate the Dart-side offsets. Regenerate: dart run tool/gen_abi.dart
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
COMMAND_EXPORT_ABI_OFFSET(LabelExport, text, 124);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, layer, 252);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, icon, 316);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textOffsetX, 380);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textOffsetY, 384);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconOffsetX, 388);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, iconOffsetY, 392);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textOpacity, 396);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, haloBlur, 400);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, letterSpacing, 404);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, lineHeight, 408);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, maxWidth, 412);
COMMAND_EXPORT_ABI_OFFSET(LabelExport, textFont, 416);

// Evaluate PropertyValue<T> at zoom (feature-constant expressions only).
template <typename T>
static T evalPropAtZoom(const mbgl::style::PropertyValue<T>& prop, float zoom, T defaultVal) {
    if (prop.isUndefined()) return defaultVal;
    if (prop.isConstant()) return prop.asConstant();
    const auto& expr = prop.asExpression();
    if (expr.isFeatureConstant()) {
        return expr.evaluate(mbgl::style::expression::EvaluationContext(zoom), defaultVal);
    }
    return defaultVal;
}

struct LabelSessionState {
    std::vector<LabelExport> labels;
    uint32_t version = 0;
};

static std::map<void*, LabelSessionState> g_labelSessions;
static LabelSessionState& labelSession() {
    return g_labelSessions[bridge_currentSession()];
}

void bridge_releaseLabelSession(void* session) {
    g_labelSessions.erase(session);
}

#define g_labels labelSession().labels
#define g_labelsVersion labelSession().version

void bridge_resetLabels() {
    g_labels.clear();
    g_labelsVersion++;
}

void bridge_extractLabels(const mbgl::TransformState* renderedState) {
    bridge_resetLabels();
    if (!g_frontend || !g_labelCollectionEnabled) return;
    auto* renderer = g_frontend->getRenderer();
    if (!renderer) return;

    const auto& symbols = renderer->getPlacedSymbolsData();
    for (const auto& sym : symbols) {
        if (!g_map) break;
        const bool hasText = sym.textPlaced && sym.textCollisionBox;
        const bool hasIcon = sym.iconPlaced && sym.iconCollisionBox && !sym.icon.empty();
        if (!hasText && !hasIcon) continue;

        LabelExport label{};
        const float pad = sym.viewportPadding;
        const float anchorX = sym.anchorPoint.x - pad;
        const float anchorY = sym.anchorPoint.y - pad;
        const auto anchorLatLng = renderedState
            ? renderedState->screenCoordinateToLatLng(
                  mbgl::ScreenCoordinate{
                      anchorX,
                      renderedState->getSize().height - anchorY},
                  mbgl::LatLng::Wrapped)
            : g_map->latLngForPixel(
                  mbgl::ScreenCoordinate{anchorX, anchorY});

        float textW = 0, textH = 0;
        if (hasText) {
            const auto& box = *sym.textCollisionBox;
            textW = box.max.x - box.min.x;
            textH = box.max.y - box.min.y;
            const float screenX = (box.min.x + box.max.x) * 0.5f - pad;
            const float screenY = (box.min.y + box.max.y) * 0.5f - pad;
            label.lat = anchorLatLng.latitude();
            label.lon = anchorLatLng.longitude();
            label.textOffsetX = screenX - anchorX;
            label.textOffsetY = screenY - anchorY;
        }
        float iconW = 0, iconH = 0;
        if (hasIcon) {
            const auto& box = *sym.iconCollisionBox;
            iconW = box.max.x - box.min.x;
            iconH = box.max.y - box.min.y;
            const float screenX = (box.min.x + box.max.x) * 0.5f - pad;
            const float screenY = (box.min.y + box.max.y) * 0.5f - pad;
            label.iconLat = anchorLatLng.latitude();
            label.iconLon = anchorLatLng.longitude();
            label.iconOffsetX = screenX - anchorX;
            label.iconOffsetY = screenY - anchorY;
        }

        // Skip fully degenerate symbols
        const bool textOk = hasText && textW > 0 && textH > 0;
        const bool iconOk = hasIcon && iconW > 0 && iconH > 0;
        if (!textOk && !iconOk) continue;
        label.textW = textW;
        label.textH = textH;
        label.iconW = iconW;
        label.iconH = iconH;
        label.flags = (textOk ? 1u : 0u) | (iconOk ? 2u : 0u) | (sym.alongLine ? 4u : 0u);
        label.textAngle = sym.textAngle;
        label.crossTileID = sym.crossTileID;
        label.fontSize = sym.textSize;
        label.iconSize = sym.iconSize;

        // Size comes from the placed symbol because that preserves source and
        // composite function evaluation. Paint properties are still evaluated
        // from the style layer when they are feature-constant.
        // No RTTI: use getTypeInfo() to safely check layer type before static_cast
        const float zoom = renderedState
            ? static_cast<float>(renderedState->getZoom())
            : static_cast<float>(
                  g_map->getCameraOptions().zoom.value_or(13.0));
        const auto* rawLayer = g_map->getStyle().getLayer(sym.layer);
        const mbgl::style::SymbolLayer* styleLayer = nullptr;
        if (rawLayer && rawLayer->getTypeInfo() &&
            std::strcmp(rawLayer->getTypeInfo()->type, "symbol") == 0) {
            styleLayer = static_cast<const mbgl::style::SymbolLayer*>(rawLayer);
        }

        // Keep fallback values tied to MapLibre's style-spec defaults instead
        // of maintaining a second (and previously divergent) set here.
        const auto defaultTextColor = mbgl::style::SymbolLayer::getDefaultTextColor().asConstant();
        const auto defaultHaloColor = mbgl::style::SymbolLayer::getDefaultTextHaloColor().asConstant();
        const float defaultHaloWidth = mbgl::style::SymbolLayer::getDefaultTextHaloWidth().asConstant();
        const float defaultTextOpacity = mbgl::style::SymbolLayer::getDefaultTextOpacity().asConstant();
        const float defaultHaloBlur = mbgl::style::SymbolLayer::getDefaultTextHaloBlur().asConstant();
        const auto defaultTextFont = mbgl::style::SymbolLayer::getDefaultTextFont().asConstant();
        const float defaultLetterSpacing =
            mbgl::style::SymbolLayer::getDefaultTextLetterSpacing().asConstant();
        const float defaultLineHeight =
            mbgl::style::SymbolLayer::getDefaultTextLineHeight().asConstant();
        const float defaultMaxWidth =
            mbgl::style::SymbolLayer::getDefaultTextMaxWidth().asConstant();
        const float defaultIconOpacity = mbgl::style::SymbolLayer::getDefaultIconOpacity().asConstant();
        const auto defaultIconColor = mbgl::style::SymbolLayer::getDefaultIconColor().asConstant();
        std::vector<std::string> textFont = defaultTextFont;
        if (styleLayer) {
            auto tc = evalPropAtZoom(styleLayer->getTextColor(), zoom, defaultTextColor);
            label.textR = tc.r; label.textG = tc.g; label.textB = tc.b; label.textA = tc.a;
            auto hc = evalPropAtZoom(styleLayer->getTextHaloColor(), zoom, defaultHaloColor);
            label.haloR = hc.r; label.haloG = hc.g; label.haloB = hc.b; label.haloA = hc.a;
            label.haloWidth = evalPropAtZoom(styleLayer->getTextHaloWidth(), zoom, defaultHaloWidth);
            label.textOpacity =
                evalPropAtZoom(styleLayer->getTextOpacity(), zoom, defaultTextOpacity);
            label.haloBlur =
                evalPropAtZoom(styleLayer->getTextHaloBlur(), zoom, defaultHaloBlur);
            textFont = evalPropAtZoom(styleLayer->getTextFont(), zoom, defaultTextFont);
            label.letterSpacing = evalPropAtZoom(
                styleLayer->getTextLetterSpacing(), zoom, defaultLetterSpacing);
            label.lineHeight =
                evalPropAtZoom(styleLayer->getTextLineHeight(), zoom, defaultLineHeight);
            label.maxWidth =
                evalPropAtZoom(styleLayer->getTextMaxWidth(), zoom, defaultMaxWidth);
            label.iconOpacity = evalPropAtZoom(styleLayer->getIconOpacity(), zoom, defaultIconOpacity);
            auto ic = evalPropAtZoom(styleLayer->getIconColor(), zoom, defaultIconColor);
            label.iconR = ic.r; label.iconG = ic.g; label.iconB = ic.b; label.iconA = ic.a;
        } else {
            label.textR = defaultTextColor.r; label.textG = defaultTextColor.g;
            label.textB = defaultTextColor.b; label.textA = defaultTextColor.a;
            label.haloR = defaultHaloColor.r; label.haloG = defaultHaloColor.g;
            label.haloB = defaultHaloColor.b; label.haloA = defaultHaloColor.a;
            label.haloWidth = defaultHaloWidth;
            label.textOpacity = defaultTextOpacity;
            label.haloBlur = defaultHaloBlur;
            label.letterSpacing = defaultLetterSpacing;
            label.lineHeight = defaultLineHeight;
            label.maxWidth = defaultMaxWidth;
            label.iconOpacity = defaultIconOpacity;
            label.iconR = defaultIconColor.r; label.iconG = defaultIconColor.g;
            label.iconB = defaultIconColor.b; label.iconA = defaultIconColor.a;
        }
        if (!textFont.empty()) {
            strncpy(label.textFont, textFont.front().c_str(), sizeof(label.textFont) - 1);
            label.textFont[sizeof(label.textFont) - 1] = '\0';
        }

        // Export MapLibre's own balanced line breaks. Fall back to the raw key
        // for symbols created by a renderer path that did not retain shaping.
        const auto& exportedText =
            sym.lineBrokenText.empty() ? sym.key : sym.lineBrokenText;

        // Convert u16string to UTF-8, decoding surrogate pairs
        // (emoji, supplementary CJK like U+29E3D need 4-byte sequences)
        std::string utf8;
        utf8.reserve(exportedText.size() * 4);
        for (size_t i = 0; i < exportedText.size(); i++) {
            char32_t cp = exportedText[i];
            if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < exportedText.size()) {
                const char16_t lo = exportedText[i + 1];
                if (lo >= 0xDC00 && lo <= 0xDFFF) {
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                    i++;
                }
            }
            if (cp >= 0xD800 && cp <= 0xDFFF) cp = 0xFFFD; // unpaired surrogate
            if (cp < 0x80) {
                utf8 += static_cast<char>(cp);
            } else if (cp < 0x800) {
                utf8 += static_cast<char>(0xC0 | (cp >> 6));
                utf8 += static_cast<char>(0x80 | (cp & 0x3F));
            } else if (cp < 0x10000) {
                utf8 += static_cast<char>(0xE0 | (cp >> 12));
                utf8 += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                utf8 += static_cast<char>(0x80 | (cp & 0x3F));
            } else {
                utf8 += static_cast<char>(0xF0 | (cp >> 18));
                utf8 += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
                utf8 += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                utf8 += static_cast<char>(0x80 | (cp & 0x3F));
            }
        }
        strncpy(label.text, utf8.c_str(), sizeof(label.text) - 1);
        label.text[sizeof(label.text) - 1] = '\0';
        if (utf8.size() > sizeof(label.text) - 1) {
            // Truncated: drop a trailing partial UTF-8 sequence
            size_t end = sizeof(label.text) - 1;
            while (end > 0 && (label.text[end - 1] & 0xC0) == 0x80) end--;
            if (end > 0 && static_cast<unsigned char>(label.text[end - 1]) >= 0xC0) end--;
            label.text[end] = '\0';
        }
        strncpy(label.layer, sym.layer.c_str(), sizeof(label.layer) - 1);
        label.layer[sizeof(label.layer) - 1] = '\0';
        strncpy(label.icon, sym.icon.c_str(), sizeof(label.icon) - 1);
        label.icon[sizeof(label.icon) - 1] = '\0';

        g_labels.push_back(label);
    }
}

extern "C" {

MAPLIBRE_API int maplibre_get_label_count(void) {
    return static_cast<int>(g_labels.size());
}

MAPLIBRE_API const void* maplibre_get_labels(void) {
    if (g_labels.empty()) return nullptr;
    return g_labels.data();
}

MAPLIBRE_API int maplibre_get_label_stride(void) {
    return static_cast<int>(sizeof(LabelExport));
}

// Reproject all cached labels to screen coords in one shot (1 FFI call vs N).
// out_xs / out_ys must be pre-allocated by caller with at least g_labels.size() floats.
MAPLIBRE_API void maplibre_reproject_labels(float* out_xs, float* out_ys) {
    if (!out_xs || !out_ys) return;
    if (g_labels.empty()) return;
    if (bridge_projectPublishedCoordinates(
            &g_labels.front().lat,
            sizeof(LabelExport),
            &g_labels.front().lon,
            sizeof(LabelExport),
            out_xs,
            out_ys,
            static_cast<int>(g_labels.size()))) {
        return;
    }
    try {
        bridge_runOnOwnerSync([&] {
            if (!g_map) return;
            for (int i = 0; i < static_cast<int>(g_labels.size()); i++) {
                const auto pixel = g_map->pixelForLatLng(
                    mbgl::LatLng{g_labels[i].lat, g_labels[i].lon});
                out_xs[i] = static_cast<float>(pixel.x);
                out_ys[i] = static_cast<float>(pixel.y);
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
