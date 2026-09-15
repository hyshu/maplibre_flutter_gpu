// Coordinate conversions use the published frame while its lease is valid.
#include "bridge_session.hpp"
#include "bridge_camera_operation.hpp"

#include <cmath>
#include <cstring>

#include <mln/util/constants.hpp>
#include <mln/util/projection.hpp>

bool bridge_getPublishedCamera(mln::CameraOptions& camera) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    if ((!g_asyncFrame.ready && !g_asyncFrame.acquired) ||
        !g_snapshotCamera) {
        return false;
    }
    camera = *g_snapshotCamera;
    return true;
#else
    (void)camera;
    return false;
#endif
}

bool bridge_projectPublishedCoordinates(
    const double* latitudes,
    std::size_t latitudeStride,
    const double* longitudes,
    std::size_t longitudeStride,
    float* outX,
    float* outY,
    int count) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    if (!latitudes || !longitudes || !outX || !outY || count <= 0) {
        return false;
    }
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    if ((!g_asyncFrame.ready && !g_asyncFrame.acquired) ||
        !g_snapshotTransform) {
        return false;
    }
    const auto* latitudeBytes =
        reinterpret_cast<const uint8_t*>(latitudes);
    const auto* longitudeBytes =
        reinterpret_cast<const uint8_t*>(longitudes);
    for (int index = 0; index < count; ++index) {
        const auto latitude = *reinterpret_cast<const double*>(
            latitudeBytes + static_cast<std::size_t>(index) * latitudeStride);
        const auto longitude = *reinterpret_cast<const double*>(
            longitudeBytes + static_cast<std::size_t>(index) * longitudeStride);
        auto projectedLatLng =
            mln::LatLng{latitude, longitude}.wrapped();
        projectedLatLng.unwrapForShortestPath(
            g_snapshotTransform->getLatLng(mln::LatLng::Wrapped));
        const auto screen =
            g_snapshotTransform->latLngToScreenCoordinate(
                projectedLatLng);
        outX[index] = static_cast<float>(screen.x);
        outY[index] = static_cast<float>(
            g_snapshotTransform->getSize().height - screen.y);
    }
    return true;
#else
    (void)latitudes;
    (void)latitudeStride;
    (void)longitudes;
    (void)longitudeStride;
    (void)outX;
    (void)outY;
    (void)count;
    return false;
#endif
}

bool bridge_projectPublishedWrappedCoordinates(
    const double* latitudes,
    const double* longitudes,
    const int32_t* tileWraps,
    float* outX,
    float* outY,
    int count) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    if (!latitudes || !longitudes || !tileWraps || !outX || !outY ||
        count <= 0) {
        return false;
    }
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    if ((!g_asyncFrame.ready && !g_asyncFrame.acquired) ||
        !g_snapshotTransform) {
        return false;
    }
    for (int index = 0; index < count; ++index) {
        const mln::LatLng coordinate{
            latitudes[index],
            longitudes[index] +
                static_cast<double>(tileWraps[index]) *
                    mln::util::DEGREES_MAX};
        const auto screen =
            g_snapshotTransform->latLngToScreenCoordinate(coordinate);
        outX[index] = static_cast<float>(screen.x);
        outY[index] = static_cast<float>(
            g_snapshotTransform->getSize().height - screen.y);
    }
    return true;
#else
    (void)latitudes;
    (void)longitudes;
    (void)tileWraps;
    (void)outX;
    (void)outY;
    (void)count;
    return false;
#endif
}

bool bridge_unprojectPublishedCoordinate(
    double x,
    double y,
    double& latitude,
    double& longitude) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    if ((!g_asyncFrame.ready && !g_asyncFrame.acquired) ||
        !g_snapshotTransform) {
        return false;
    }
    const auto latLng = g_snapshotTransform->screenCoordinateToLatLng(
        mln::ScreenCoordinate{
            x,
            g_snapshotTransform->getSize().height - y},
        mln::LatLng::Wrapped);
    latitude = latLng.latitude();
    longitude = latLng.longitude();
    return true;
#else
    (void)x;
    (void)y;
    (void)latitude;
    (void)longitude;
    return false;
#endif
}

bool bridge_getPublishedVisibleRegion(
    double& south,
    double& west,
    double& north,
    double& east) {
#if defined(__ANDROID__) && MLN_RENDER_BACKEND_COMMAND_EXPORT
    std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
    if ((!g_asyncFrame.ready && !g_asyncFrame.acquired) ||
        !g_snapshotVisibleRegion || !g_snapshotVisibleRegion->valid()) {
        return false;
    }
    south = g_snapshotVisibleRegion->south();
    west = g_snapshotVisibleRegion->west();
    north = g_snapshotVisibleRegion->north();
    east = g_snapshotVisibleRegion->east();
    return true;
#else
    (void)south;
    (void)west;
    (void)north;
    (void)east;
    return false;
#endif
}

extern "C" {

MAPLIBRE_API int maplibre_get_visible_region(
    double* out_south,
    double* out_west,
    double* out_north,
    double* out_east) {
    if (!out_south || !out_west || !out_north || !out_east) return 0;
    if (bridge_getPublishedVisibleRegion(
            *out_south,
            *out_west,
            *out_north,
            *out_east)) {
        return 1;
    }
    return runCameraOperation("visible region query", [&] {
        const auto bounds = g_map->latLngBoundsForCameraUnwrapped(g_map->getCameraOptions());
        if (!bounds.valid()) return false;
        *out_south = bounds.south();
        *out_west = bounds.west();
        *out_north = bounds.north();
        *out_east = bounds.east();
        return true;
    });
}

MAPLIBRE_API double maplibre_get_meters_per_pixel_at_latitude(double latitude) {
    mln::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return mln::Projection::getMetersPerPixelAtLatitude(
            latitude,
            publishedCamera.zoom.value_or(0.0));
    }
    try {
        return bridge_runOnOwnerSync([=] {
            if (!g_map) return 0.0;
            const auto camera = g_map->getCameraOptions();
            return mln::Projection::getMetersPerPixelAtLatitude(
                latitude,
                camera.zoom.value_or(0.0));
        });
    } catch (...) {
        return 0.0;
    }
}

MAPLIBRE_API void maplibre_lat_lon_to_screen(double lat, double lon, double* out_x, double* out_y) {
    if (!out_x || !out_y) return;
    float projectedX = 0.0f;
    float projectedY = 0.0f;
    if (bridge_projectPublishedCoordinates(
            &lat,
            sizeof(double),
            &lon,
            sizeof(double),
            &projectedX,
            &projectedY,
            1)) {
        *out_x = projectedX;
        *out_y = projectedY;
        return;
    }
    runCameraOperation("project coordinate", [&] {
        const auto screen = g_map->pixelForLatLng(mln::LatLng{lat, lon});
        *out_x = screen.x;
        *out_y = screen.y;
        return true;
    });
}

MAPLIBRE_API void maplibre_project_coordinates(
    const double* latitudes,
    const double* longitudes,
    float* out_x,
    float* out_y,
    int count) {
    if (!latitudes || !longitudes || !out_x || !out_y || count <= 0) return;
    if (bridge_projectPublishedCoordinates(
            latitudes,
            sizeof(double),
            longitudes,
            sizeof(double),
            out_x,
            out_y,
            count)) {
        return;
    }
    runCameraOperation("project coordinates", [&] {
        for (int index = 0; index < count; index++) {
            const auto screen = g_map->pixelForLatLng(
                mln::LatLng{latitudes[index], longitudes[index]});
            out_x[index] = static_cast<float>(screen.x);
            out_y[index] = static_cast<float>(screen.y);
        }
        return true;
    });
}

MAPLIBRE_API void maplibre_project_wrapped_coordinates(
    const double* latitudes,
    const double* longitudes,
    const int32_t* tile_wraps,
    float* out_x,
    float* out_y,
    int count) {
    if (!latitudes || !longitudes || !tile_wraps || !out_x || !out_y ||
        count <= 0) {
        return;
    }
    if (bridge_projectPublishedWrappedCoordinates(
            latitudes,
            longitudes,
            tile_wraps,
            out_x,
            out_y,
            count)) {
        return;
    }
    runCameraOperation("project wrapped coordinates", [&] {
        const auto state = g_map->getTransfromState();
        for (int index = 0; index < count; ++index) {
            const mln::LatLng coordinate{
                latitudes[index],
                longitudes[index] +
                    static_cast<double>(tile_wraps[index]) *
                        mln::util::DEGREES_MAX};
            const auto screen = state.latLngToScreenCoordinate(coordinate);
            out_x[index] = static_cast<float>(screen.x);
            out_y[index] = static_cast<float>(state.getSize().height - screen.y);
        }
        return true;
    });
}

MAPLIBRE_API void maplibre_screen_to_lat_lon(double x, double y, double* out_lat, double* out_lon) {
    if (!out_lat || !out_lon) return;
    if (bridge_unprojectPublishedCoordinate(
            x,
            y,
            *out_lat,
            *out_lon)) {
        return;
    }
    runCameraOperation("unproject coordinate", [&] {
        const auto latLng =
            g_map->latLngForPixel(mln::ScreenCoordinate{x, y});
        *out_lat = latLng.latitude();
        *out_lon = latLng.longitude();
        return true;
    });
}


} // extern "C"
