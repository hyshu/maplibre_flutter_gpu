// Renderer drawable diagnostics exported through the bridge.
#include "bridge_session.hpp"

#include <cstring>
#include <map>

#include <mbgl/renderer/renderer.hpp>

extern "C" {

MAPLIBRE_API int maplibre_get_drawable_count(void) {
    try {
        return bridge_runOnOwnerSync([] {
            if (!g_frontend) return 0;
            auto* renderer = g_frontend->getRenderer();
            if (!renderer) return 0;

            g_drawables.clear();
            renderer->visitDrawables([](
                                         const std::string& name,
                                         const mbgl::gfx::Drawable::ExportedData&) {
                DrawableInfo info;
                strncpy(info.name, name.c_str(), sizeof(info.name) - 1);
                info.name[sizeof(info.name) - 1] = '\0';
                g_drawables.push_back(info);
            });

            return static_cast<int>(g_drawables.size());
        });
    } catch (...) {
        return 0;
    }
}

MAPLIBRE_API const char* maplibre_get_drawable_name(int index) {
    if (index < 0 || static_cast<std::size_t>(index) >= g_drawables.size()) return "";
    return g_drawables[index].name;
}

// Get a summary string of drawable types and counts

MAPLIBRE_API const char* maplibre_get_drawable_summary(void) {
    try {
        return bridge_runOnOwnerSync([]() -> const char* {
            if (!g_frontend) return "";
            auto* renderer = g_frontend->getRenderer();
            if (!renderer) return "";

            struct Stats {
                int count = 0;
                size_t verts = 0;
                size_t idxs = 0;
            };
            std::map<std::string, Stats> counts;
            renderer->visitDrawables(
                [&](const std::string& name,
                    const mbgl::gfx::Drawable::ExportedData& data) {
                    auto& stats = counts[name];
                    stats.count++;
                    stats.verts += data.vertexBytes;
                    stats.idxs += data.indexCount;
                });

            std::string result;
            for (const auto& [name, stats] : counts) {
                if (!result.empty()) result += "\n";
                result += name + ": " + std::to_string(stats.count) +
                          " v:" + std::to_string(stats.verts / 1024) + "K" +
                          " i:" + std::to_string(stats.idxs);
            }
            strncpy(
                g_drawable_summary,
                result.c_str(),
                sizeof(g_drawable_summary) - 1);
            g_drawable_summary[sizeof(g_drawable_summary) - 1] = '\0';
            return g_drawable_summary;
        });
    } catch (...) {
        return "";
    }
}


} // extern "C"
