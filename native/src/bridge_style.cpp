// Runtime style inspection and mutation exposed to Dart.
#include "bridge_state.hpp"

#include <mbgl/style/conversion/filter.hpp>
#include <mbgl/style/conversion/json.hpp>
#include <mbgl/style/conversion/layer.hpp>
#include <mbgl/style/conversion/stringify.hpp>
#include <mbgl/style/filter.hpp>
#include <mbgl/style/layer.hpp>
#include <mbgl/style/source.hpp>
#include <mbgl/style/style.hpp>

#include <rapidjson/stringbuffer.h>
#include <rapidjson/writer.h>

#include <cstdio>
#include <cstring>
#include <exception>
#include <map>
#include <stdexcept>
#include <string>
#include <utility>

namespace {

struct StyleSessionState {
    std::string result;
    char error[1024]{};
};

std::map<void*, StyleSessionState> g_styleSessions;
StyleSessionState& styleSession() {
    return g_styleSessions[bridge_currentSession()];
}

#define g_styleResult styleSession().result
#define g_styleError styleSession().error

void setStyleError(const char *operation, const std::string &message) noexcept {
    std::snprintf(g_styleError, sizeof(g_styleError), "%s: %s", operation, message.c_str());
}

void clearStyleError() noexcept { g_styleError[0] = '\0'; }

bool isFilterLayer(const mbgl::style::Layer &layer) noexcept {
    const auto *typeInfo = layer.getTypeInfo();
    const auto *type = typeInfo ? typeInfo->type : nullptr;
    return type && (std::strcmp(type, "circle") == 0 || std::strcmp(type, "fill-extrusion") == 0 ||
                    std::strcmp(type, "fill") == 0 || std::strcmp(type, "heatmap") == 0 ||
                    std::strcmp(type, "line") == 0 || std::strcmp(type, "symbol") == 0);
}

bool ensureStyleAvailable(const char *name, bool requireLoaded) noexcept {
    if (!g_map) {
        setStyleError(name, "map is not initialized");
        return false;
    }
    if (requireLoaded && !bridge_isStyleLoaded()) {
        setStyleError(name, "style is not fully loaded");
        return false;
    }
    return true;
}

template <typename Operation>
int runStyleOperation(const char *name, Operation &&operation, bool requireLoaded = true) noexcept {
    try {
        return bridge_runOnOwnerSync([&]() -> int {
            if (!ensureStyleAvailable(name, requireLoaded))
                return 0;
            if (!bridge_prepareSynchronousMutation()) {
                setStyleError(name, "frame snapshot is currently acquired");
                return 0;
            }
            if (!operation())
                return 0;
            clearStyleError();
            return 1;
        });
    } catch (const std::exception &error) {
        setStyleError(name, error.what());
    } catch (...) {
        setStyleError(name, "unknown exception");
    }
    return 0;
}

template <typename Operation>
const char *readStyleValue(const char *name, Operation &&operation,
                           bool requireLoaded = true) noexcept {
    try {
        return bridge_runOnOwnerSync([&]() -> const char * {
            if (!ensureStyleAvailable(name, requireLoaded))
                return nullptr;
            g_styleResult = operation();
            clearStyleError();
            return g_styleResult.c_str();
        });
    } catch (const std::exception &error) {
        setStyleError(name, error.what());
    } catch (...) {
        setStyleError(name, "unknown exception");
    }
    return nullptr;
}

template <typename Values> std::string stringArrayJSON(const Values &values) {
    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    writer.StartArray();
    for (const auto *value : values) {
        const auto id = value->getID();
        writer.String(id.c_str(), static_cast<rapidjson::SizeType>(id.size()));
    }
    writer.EndArray();
    return {buffer.GetString(), buffer.GetSize()};
}

std::string sourceAttributionsJSON(const mbgl::style::Style &style) {
    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    writer.StartArray();
    for (const auto *source : style.getSources()) {
        const auto attribution = source->getAttribution();
        if (attribution && !attribution->empty()) {
            writer.String(attribution->c_str(),
                          static_cast<rapidjson::SizeType>(attribution->size()));
        }
    }
    writer.EndArray();
    return {buffer.GetString(), buffer.GetSize()};
}

std::string filterJSON(const mbgl::style::Filter &filter) {
    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    mbgl::style::conversion::stringify(writer, filter.serialize());
    return {buffer.GetString(), buffer.GetSize()};
}

} // namespace

void bridge_releaseStyleSession(void* session) {
    g_styleSessions.erase(session);
}

extern "C" {

MAPLIBRE_API const char *maplibre_style_last_error(void) {
    thread_local char result[sizeof(g_styleError)] = {};
    try {
        // Capture the caller's storage, since TLS resolves on the executing thread.
        char* destination = result;
        bridge_runOnOwnerSync([destination] {
            std::memcpy(destination, g_styleError, sizeof(g_styleError));
            destination[sizeof(g_styleError) - 1] = '\0';
        });
    } catch (...) {
        result[0] = '\0';
    }
    return result;
}

MAPLIBRE_API int maplibre_style_set(const char *style_value) {
    return runStyleOperation(
        "set style",
        [&] {
            if (!style_value)
                throw std::invalid_argument("style is null");
            const std::string styleValue(style_value);
            const auto firstContent = styleValue.find_first_not_of(" \t\r\n");
            if (firstContent == std::string::npos) {
                throw std::invalid_argument("style is empty");
            }
            bridge_markStyleLoading();
            if (styleValue[firstContent] == '{') {
                g_map->getStyle().loadJSON(styleValue);
            } else {
                g_map->getStyle().loadURL(styleValue);
            }
            return true;
        },
        false);
}

MAPLIBRE_API const char *maplibre_style_get_json(void) {
    return readStyleValue("get style", [] {
        const auto &map = static_cast<const mbgl::Map &>(*g_map);
        return map.getStyle().getJSON();
    });
}

MAPLIBRE_API const char *maplibre_style_get_layer_ids(void) {
    return readStyleValue("get layer ids", [] {
        const auto &map = static_cast<const mbgl::Map &>(*g_map);
        return stringArrayJSON(map.getStyle().getLayers());
    });
}

MAPLIBRE_API const char *maplibre_style_get_source_ids(void) {
    return readStyleValue("get source ids", [] {
        const auto &map = static_cast<const mbgl::Map &>(*g_map);
        return stringArrayJSON(map.getStyle().getSources());
    });
}

MAPLIBRE_API const char *maplibre_style_get_source_attributions(void) {
    return readStyleValue("get source attributions", [] {
        const auto &map = static_cast<const mbgl::Map &>(*g_map);
        return sourceAttributionsJSON(map.getStyle());
    });
}

MAPLIBRE_API int maplibre_style_set_layer_visibility(const char *layer_id, int visible) {
    return runStyleOperation("set layer visibility", [&] {
        if (!layer_id)
            throw std::invalid_argument("layer id is null");
        auto *layer = g_map->getStyle().getLayer(layer_id);
        if (!layer) {
            setStyleError("set layer visibility", std::string("layer not found: ") + layer_id);
            return false;
        }
        layer->setVisibility(visible ? mbgl::style::VisibilityType::Visible
                                     : mbgl::style::VisibilityType::None);
        return true;
    });
}

MAPLIBRE_API int maplibre_style_get_layer_visibility(const char *layer_id, int *out_visible) {
    constexpr const char *operation = "get layer visibility";
    try {
        return bridge_runOnOwnerSync([&]() -> int {
            if (!ensureStyleAvailable(operation, true))
                return -1;
            if (!layer_id || !out_visible) {
                throw std::invalid_argument("invalid argument");
            }
            const auto &map = static_cast<const mbgl::Map &>(*g_map);
            const auto *layer = map.getStyle().getLayer(layer_id);
            if (!layer) {
                clearStyleError();
                return 0;
            }
            *out_visible =
                layer->getVisibility() == mbgl::style::VisibilityType::Visible
                    ? 1
                    : 0;
            clearStyleError();
            return 1;
        });
    } catch (const std::exception &error) {
        setStyleError(operation, error.what());
    } catch (...) {
        setStyleError(operation, "unknown exception");
    }
    return -1;
}

MAPLIBRE_API int maplibre_style_set_filter(const char *layer_id, const char *filter_json) {
    return runStyleOperation("set filter", [&] {
        if (!layer_id || !filter_json) {
            throw std::invalid_argument("invalid argument");
        }
        auto *layer = g_map->getStyle().getLayer(layer_id);
        if (!layer) {
            setStyleError("set filter", std::string("layer not found: ") + layer_id);
            return false;
        }
        if (!isFilterLayer(*layer)) {
            setStyleError("set filter",
                          std::string("layer does not support filtering: ") + layer_id);
            return false;
        }

        if (std::strcmp(filter_json, "null") == 0) {
            layer->setFilter(mbgl::style::Filter{});
            return true;
        }

        mbgl::style::conversion::Error error;
        auto filter = mbgl::style::conversion::convertJSON<mbgl::style::Filter>(filter_json, error);
        if (!filter) {
            setStyleError("set filter", error.message);
            return false;
        }
        layer->setFilter(*filter);
        return true;
    });
}

MAPLIBRE_API const char *maplibre_style_get_filter(const char *layer_id) {
    return readStyleValue("get filter", [&] {
        if (!layer_id)
            throw std::invalid_argument("layer id is null");
        const auto &map = static_cast<const mbgl::Map &>(*g_map);
        const auto *layer = map.getStyle().getLayer(layer_id);
        if (!layer) {
            throw std::runtime_error(std::string("layer not found: ") + layer_id);
        }
        if (!isFilterLayer(*layer)) {
            throw std::runtime_error(std::string("layer does not support filtering: ") + layer_id);
        }
        return filterJSON(layer->getFilter());
    });
}

MAPLIBRE_API int maplibre_style_add_layer(const char *layer_json,
                                          const char *before_layer_id) {
    return runStyleOperation("add layer", [&] {
        if (!layer_json)
            throw std::invalid_argument("layer json is null");
        mbgl::style::conversion::Error error;
        auto layer = mbgl::style::conversion::convertJSON<std::unique_ptr<mbgl::style::Layer>>(
            layer_json, error);
        if (!layer) {
            setStyleError("add layer", error.message);
            return false;
        }
        std::optional<std::string> before;
        if (before_layer_id && before_layer_id[0] != '\0')
            before = before_layer_id;
        g_map->getStyle().addLayer(std::move(*layer), before);
        return true;
    });
}

MAPLIBRE_API int maplibre_style_set_layer_properties(
    const char *layer_id, const char *properties_json) {
    return runStyleOperation("set layer properties", [&] {
        if (!layer_id || !properties_json)
            throw std::invalid_argument("invalid argument");
        auto *layer = g_map->getStyle().getLayer(layer_id);
        if (!layer) {
            setStyleError("set layer properties",
                          std::string("layer not found: ") + layer_id);
            return false;
        }
        mbgl::JSDocument properties;
        properties.Parse<0>(properties_json);
        if (properties.HasParseError()) {
            setStyleError("set layer properties",
                          mbgl::formatJSONParseError(properties));
            return false;
        }
        mbgl::style::conversion::Convertible convertible(
            static_cast<const mbgl::JSValue *>(&properties));
        if (!isObject(convertible)) {
            setStyleError("set layer properties", "properties must be an object");
            return false;
        }
        auto propertyError = eachMember(
            convertible,
            [&](const std::string &name,
                const mbgl::style::conversion::Convertible &value) {
                return layer->setProperty(name, value);
            });
        if (propertyError) {
            setStyleError("set layer properties", propertyError->message);
            return false;
        }
        return true;
    });
}

MAPLIBRE_API int maplibre_style_remove_layer(const char *layer_id) {
    return runStyleOperation("remove layer", [&] {
        if (!layer_id)
            throw std::invalid_argument("layer id is null");
        if (!g_map->getStyle().getLayer(layer_id)) {
            setStyleError("remove layer", std::string("layer not found: ") + layer_id);
            return false;
        }
        g_map->getStyle().removeLayer(layer_id);
        return true;
    });
}

} // extern "C"
