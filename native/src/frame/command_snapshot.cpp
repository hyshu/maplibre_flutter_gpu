#include "command_frame.hpp"

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
#include <algorithm>

#include <mln/renderer/renderer.hpp>
#include <mln/util/mat4.hpp>
#include <mln/util/projection.hpp>

static void captureMapTransform(const mln::TransformState& state) {
    g_mapTransformMetadata.valid = 0u;
    const auto size = state.getSize();
    if (size.isEmpty()) return;

    mln::mat4 matrix;
    // Match MapLibre's near-clipped projection for fill extrusion depth.
    const auto nearZ =
        static_cast<uint16_t>(0.1 * state.getCameraToCenterDistance());
    state.getProjMatrix(matrix, nearZ);

    const double worldSize = mln::Projection::worldSize(state.getScale());
    const double originX = 0.5 * worldSize - state.getX();
    const double originY = 0.5 * worldSize - state.getY();
    mln::matrix::translate(matrix, matrix, originX, originY, 0.0);
    for (std::size_t index = 0; index < matrix.size(); ++index) {
        g_mapTransformMetadata.viewProjectionMatrix[index] =
            static_cast<float>(matrix[index]);
    }
    g_mapTransformMetadata.worldSize = worldSize;
    g_mapTransformMetadata.originX = originX;
    g_mapTransformMetadata.originY = originY;
    g_mapTransformMetadata.zoom = state.getZoom();
    g_mapTransformMetadata.valid = 1u;
}

#ifdef __ANDROID__
static mln::LatLngBounds visibleRegionForTransform(
    const mln::TransformState& state) {
    const auto size = state.getSize();
    const auto unproject = [&](double apiX, double apiY) {
        return state.screenCoordinateToLatLng({
            apiX,
            static_cast<double>(size.height) - apiY});
    };
    auto northWest = unproject(0.0, 0.0);
    auto southEast = unproject(
        static_cast<double>(size.width),
        static_cast<double>(size.height));
    auto northEast =
        unproject(static_cast<double>(size.width), 0.0);
    auto southWest =
        unproject(0.0, static_cast<double>(size.height));
    const auto center = unproject(
        static_cast<double>(size.width) / 2.0,
        static_cast<double>(size.height) / 2.0);
    northWest.unwrapForShortestPath(center);
    southEast.unwrapForShortestPath(center);
    northEast.unwrapForShortestPath(center);
    southWest.unwrapForShortestPath(center);
    auto bounds = mln::LatLngBounds::hull(northWest, southEast);
    bounds.extend(northEast);
    bounds.extend(southWest);
    bounds.extend(center);
    return bounds;
}
#endif

bool beginCommandFrameOnOwner(bool asynchronous) {
#ifdef __ANDROID__
    {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        if (g_asyncFrame.acquired ||
            (!asynchronous &&
             (g_asyncFrame.renderTaskQueued || g_asyncFrame.rendering ||
              g_asyncFrame.syncFrameOpen))) {
            return false;
        }
        // Synchronous startup rendering may supersede an unconsumed snapshot.
        // It runs on Dart's calling isolate, so an acquired lease cannot exist
        // concurrently with this legacy bracket.
        if (!g_asyncFrame.acquired) g_asyncFrame.ready = false;
        if (!asynchronous) g_asyncFrame.syncFrameOpen = true;
    }
#endif
    mln::command_export::getFrameData().clear();
    if (!g_labelCollectionEnabled) {
        auto* renderer = g_frontend ? g_frontend->getRenderer() : nullptr;
        if (renderer) {
            renderer->collectPlacedSymbolData(true);
            g_labelCollectionEnabled = true;
        }
    }
    return true;
}

bool endCommandFrameOnOwner(
    const mln::TransformState* renderedState) {
    auto& fd = mln::command_export::getFrameData();
    if (!g_map || !g_frontend) {
        fd.clear();
        g_snapshot.clear();
        g_snapshotClearColor.reset();
        bridge_resetMergeStorage();
        g_mapTransformMetadata.valid = 0u;
#ifdef __ANDROID__
        g_snapshotTransform.reset();
        g_snapshotCamera.reset();
        g_snapshotVisibleRegion.reset();
#endif
        return false;
    }

    bridge_mergeCommands(fd);
    g_snapshot.swap(fd.commands);
    g_snapshotClearColor = fd.clearColor;
    // Paint expressions, feature state, transforms, and layer order can change
    // without triggering placement. The exporter publishes only when bytes differ.
    bridge_extractLabels(renderedState);
#ifdef __ANDROID__
    if (renderedState) {
        g_snapshotTransform = *renderedState;
        g_snapshotCamera =
            renderedState->getCameraOptions(std::nullopt);
        g_snapshotVisibleRegion =
            visibleRegionForTransform(*renderedState);
    } else {
        g_snapshotTransform.reset();
        g_snapshotCamera.reset();
        g_snapshotVisibleRegion.reset();
    }
#endif
    if (renderedState) {
        captureMapTransform(*renderedState);
    } else {
        captureMapTransform(g_map->getTransfromState());
    }
    return true;
}

extern "C" {
MAPLIBRE_API void maplibre_request_label_extraction(void) {
    // Frame publication performs label extraction, so this request has no effect.
}

MAPLIBRE_API int maplibre_frame_get_command_count(void) {
    return static_cast<int>(g_snapshot.size());
}

MAPLIBRE_API const void* maplibre_frame_get_commands(void) {
    if (g_snapshot.empty()) return nullptr;
    return g_snapshot.data();
}

MAPLIBRE_API int maplibre_frame_get_command_stride(void) {
    return static_cast<int>(sizeof(mln::command_export::DrawCommand));
}

MAPLIBRE_API const float* maplibre_frame_get_clear_color(void) {
    return g_snapshotClearColor ? g_snapshotClearColor->data() : nullptr;
}

MAPLIBRE_API const FrameMetadata* maplibre_frame_get_metadata(void) {
    g_frameMetadata.commands = g_snapshot.empty() ? nullptr : g_snapshot.data();
    g_frameMetadata.commandCount = static_cast<int32_t>(g_snapshot.size());
    g_frameMetadata.commandStride =
        static_cast<int32_t>(sizeof(mln::command_export::DrawCommand));
    g_frameMetadata.hasClearColor = g_snapshotClearColor ? 1u : 0u;
    if (g_snapshotClearColor) {
        std::copy(
            g_snapshotClearColor->begin(),
            g_snapshotClearColor->end(),
            g_frameMetadata.clearColor);
    } else {
        std::fill(
            std::begin(g_frameMetadata.clearColor),
            std::end(g_frameMetadata.clearColor),
            0.0f);
    }
    return &g_frameMetadata;
}

MAPLIBRE_API const MapTransformMetadata* maplibre_frame_get_map_transform(void) {
#ifndef __ANDROID__
    try {
        bridge_runOnOwnerSync([] {
            if (g_map) captureMapTransform(g_map->getTransfromState());
        });
    } catch (...) {
        g_mapTransformMetadata.valid = 0u;
    }
#endif
    return &g_mapTransformMetadata;
}

} // extern "C"
#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT
