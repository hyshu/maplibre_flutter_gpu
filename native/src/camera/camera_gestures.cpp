// Immediate gesture operations dispatched on the map owner thread.
#include "camera_dispatch.hpp"

using maplibre_bridge::camera::postGestureOperation;

extern "C" {

MAPLIBRE_API void maplibre_move_by(double dx, double dy) {
    postGestureOperation("camera move", [=] {
        g_map->moveBy(mln::ScreenCoordinate{dx, dy});
    });
}

MAPLIBRE_API void maplibre_scale_by(double scale, double cx, double cy) {
    postGestureOperation("camera scale", [=] {
        g_map->scaleBy(scale, mln::ScreenCoordinate{cx, cy});
    });
}

MAPLIBRE_API void maplibre_rotate_by(double degrees) {
    postGestureOperation("camera rotate", [=] {
        auto camera = g_map->getCameraOptions();
        camera.bearing = camera.bearing.value_or(0.0) + degrees;
        g_map->jumpTo(camera);
    });
}

MAPLIBRE_API void maplibre_pitch_by(double degrees) {
    postGestureOperation("camera pitch", [=] {
        auto camera = g_map->getCameraOptions();
        camera.pitch = camera.pitch.value_or(0.0) + degrees;
        g_map->jumpTo(camera);
    });
}

} // extern "C"
