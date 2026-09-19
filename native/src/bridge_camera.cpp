// Camera mutation, animation, and viewport constraints.
#include "camera/camera_dispatch.hpp"

#include <algorithm>
#include <chrono>

#include <mln/util/constants.hpp>

using maplibre_bridge::camera::runCameraMutation;

static mln::AnimationOptions cameraAnimationOptions(int durationMs, int easing) {
    mln::AnimationOptions animation;
    animation.duration = std::chrono::milliseconds(std::max(0, durationMs));
    switch (easing) {
        case 0:
            animation.easing.emplace(0.0, 0.0, 1.0, 1.0);
            break;
        case 1:
            animation.easing.emplace(0.42, 0.0, 0.58, 1.0);
            break;
        case 2:
            animation.easing.emplace(0.0, 0.0, 0.58, 1.0);
            break;
        case 3:
            animation.easing.emplace(0.4, 0.0, 1.0, 1.0);
            break;
        default:
            break;
    }
    return animation;
}

extern "C" {

MAPLIBRE_API void maplibre_set_camera(double lat, double lon, double zoom) {
    runCameraMutation("set camera", [=] {
        mln::CameraOptions camera;
        camera.center = mln::LatLng{lat, lon};
        camera.zoom = zoom;
        g_map->jumpTo(camera);
        return true;
    });
}

MAPLIBRE_API void maplibre_set_camera_full(
    double lat,
    double lon,
    double zoom,
    double bearing,
    double pitch) {
    runCameraMutation("set camera", [=] {
        mln::CameraOptions camera;
        camera.center = mln::LatLng{lat, lon};
        camera.zoom = zoom;
        camera.bearing = bearing;
        camera.pitch = pitch;
        g_map->jumpTo(camera);
        return true;
    });
}

MAPLIBRE_API void maplibre_set_max_pitch(double pitch) {
    runCameraMutation("set max pitch", [=] {
        mln::BoundOptions options;
        options.maxPitch = pitch;
        g_map->setBounds(options);
        return true;
    }, false);
}

MAPLIBRE_API void maplibre_set_min_pitch(double pitch) {
    runCameraMutation("set min pitch", [=] {
        mln::BoundOptions options;
        options.minPitch = pitch;
        g_map->setBounds(options);
        return true;
    }, false);
}

MAPLIBRE_API int maplibre_camera_ease_to(
    double lat,
    double lon,
    double zoom,
    double bearing,
    double pitch,
    int duration_ms,
    int easing) {
    return runCameraMutation("camera ease", [=] {
        mln::CameraOptions camera;
        camera.center = mln::LatLng{lat, lon};
        camera.zoom = zoom;
        camera.bearing = bearing;
        camera.pitch = pitch;
        g_map->easeTo(camera, cameraAnimationOptions(duration_ms, easing));
        return true;
    });
}

MAPLIBRE_API int maplibre_camera_fly_to(
    double lat,
    double lon,
    double zoom,
    double bearing,
    double pitch,
    int duration_ms,
    int easing) {
    return runCameraMutation("camera flight", [=] {
        mln::CameraOptions camera;
        camera.center = mln::LatLng{lat, lon};
        camera.zoom = zoom;
        camera.bearing = bearing;
        camera.pitch = pitch;
        g_map->flyTo(camera, cameraAnimationOptions(duration_ms, easing));
        return true;
    });
}

MAPLIBRE_API int maplibre_camera_move_by_animated(
    double dx,
    double dy,
    int duration_ms,
    int easing) {
    return runCameraMutation("animated camera move", [=] {
        g_map->moveBy(
            mln::ScreenCoordinate{dx, dy},
            cameraAnimationOptions(duration_ms, easing));
        return true;
    });
}

MAPLIBRE_API int maplibre_camera_scale_by_animated(
    double scale,
    int has_anchor,
    double x,
    double y,
    int duration_ms,
    int easing) {
    return runCameraMutation("animated camera scale", [=] {
        const std::optional<mln::ScreenCoordinate> anchor = has_anchor
            ? std::optional<mln::ScreenCoordinate>{mln::ScreenCoordinate{x, y}}
            : std::nullopt;
        g_map->scaleBy(
            scale,
            anchor,
            cameraAnimationOptions(duration_ms, easing));
        return true;
    });
}

MAPLIBRE_API int maplibre_camera_fit_bounds(
    double south,
    double west,
    double north,
    double east,
    double left,
    double top,
    double right,
    double bottom,
    int duration_ms,
    int easing,
    int fly_to) {
    if (south > north) return 0;
    if (east < west) east += 360.0;
    return runCameraMutation("camera bounds fit", [=] {
        const auto bounds = mln::LatLngBounds::hull(
            mln::LatLng{south, west},
            mln::LatLng{north, east});
        const mln::EdgeInsets padding{top, left, bottom, right};
        auto camera = g_map->cameraForLatLngBounds(bounds, padding, 0.0, 0.0);
        if (!camera.center || !camera.zoom) return false;
        if (duration_ms > 0 && fly_to) {
            g_map->flyTo(camera, cameraAnimationOptions(duration_ms, easing));
        } else if (duration_ms > 0) {
            g_map->easeTo(camera, cameraAnimationOptions(duration_ms, easing));
        } else {
            g_map->jumpTo(camera);
        }
        return true;
    });
}

MAPLIBRE_API int maplibre_cancel_camera_transitions(void) {
    const auto result = runCameraMutation("cancel camera transitions", [] {
        g_map->cancelTransitions();
        return true;
    });
    if (result) g_cameraMoving.store(false, std::memory_order_relaxed);
    return result;
}

MAPLIBRE_API int maplibre_set_content_insets(
    double top,
    double left,
    double bottom,
    double right,
    int animated) {
    return runCameraMutation("content insets", [=] {
        mln::CameraOptions camera;
        camera.padding = mln::EdgeInsets{top, left, bottom, right};
        if (animated) {
            g_map->easeTo(camera, cameraAnimationOptions(300, -1));
        } else {
            g_map->jumpTo(camera);
        }
        return true;
    });
}

MAPLIBRE_API int maplibre_set_content_insets_with_duration(
    double top,
    double left,
    double bottom,
    double right,
    int animated,
    int duration_ms) {
    return runCameraMutation("content insets", [=] {
        mln::CameraOptions camera;
        camera.padding = mln::EdgeInsets{top, left, bottom, right};
        if (animated) {
            g_map->easeTo(camera, cameraAnimationOptions(duration_ms, -1));
        } else {
            g_map->jumpTo(camera);
        }
        return true;
    });
}

MAPLIBRE_API void maplibre_set_bounds(
    int has_bounds,
    double south,
    double west,
    double north,
    double east,
    int has_min_zoom,
    double min_zoom,
    int has_max_zoom,
    double max_zoom) {
    runCameraMutation("set bounds", [=] {
        mln::BoundOptions options;
        auto adjustedEast = east;
        if (has_bounds) {
            // Preserve antimeridian-crossing bounds as an unwrapped interval.
            if (adjustedEast < west) adjustedEast += 360.0;
            options.bounds = mln::LatLngBounds::hull(
                mln::LatLng{south, west},
                mln::LatLng{north, adjustedEast});
            g_map->setConstrainMode(mln::ConstrainMode::Screen);
        } else {
            options.bounds = mln::LatLngBounds{};
            g_map->setConstrainMode(mln::ConstrainMode::HeightOnly);
        }
        options.minZoom = has_min_zoom ? min_zoom : mln::util::MIN_ZOOM;
        options.maxZoom = has_max_zoom ? max_zoom : mln::util::MAX_ZOOM;
        g_map->setBounds(options);
        return true;
    }, false);
}

MAPLIBRE_API void maplibre_set_size(int width, int height) {
    runCameraMutation("set size", [=] {
        if (!g_frontend) return false;
        const mln::Size newSize{
            static_cast<uint32_t>(width),
            static_cast<uint32_t>(height)};
        g_frontend->setSize(newSize);
        g_map->setSize(newSize);
        return true;
    }, false);
}

} // extern "C"
