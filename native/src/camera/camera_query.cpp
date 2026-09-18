// Camera reads prefer the transform from the frame published to Dart.
#include "../bridge_session.hpp"
#include "../bridge_camera_operation.hpp"

static void writeCameraOutput(const mln::CameraOptions& camera, double* output) {
    output[0] = camera.center ? camera.center->latitude() : 0.0;
    output[1] = camera.center ? camera.center->longitude() : 0.0;
    output[2] = camera.zoom.value_or(0.0);
    output[3] = camera.bearing.value_or(0.0);
    output[4] = camera.pitch.value_or(0.0);
}

template <typename ReadValue>
static double readCameraValue(ReadValue readValue) {
    mln::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return readValue(publishedCamera);
    }
    try {
        return bridge_runOnOwnerSync([readValue] {
            if (!g_map) return 0.0;
            return readValue(g_map->getCameraOptions());
        });
    } catch (...) {
        return 0.0;
    }
}

extern "C" {

MAPLIBRE_API int maplibre_is_camera_moving(void) {
#ifdef __ANDROID__
    const bool awaitingPresentedCamera =
        g_pendingCameraMutations.load(std::memory_order_acquire) != 0 ||
        g_cameraStateRevision.load(std::memory_order_acquire) !=
            g_cameraPresentedRevision.load(std::memory_order_acquire);
#else
    const bool awaitingPresentedCamera = false;
#endif
    return (g_cameraMoving.load(std::memory_order_relaxed) ||
            awaitingPresentedCamera)
               ? 1
               : 0;
}

MAPLIBRE_API int maplibre_get_camera(double* output) {
    if (!output) return 0;
    mln::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        writeCameraOutput(publishedCamera, output);
        return 1;
    }
    return runCameraOperation("get camera", [&] {
        writeCameraOutput(g_map->getCameraOptions(), output);
        return true;
    });
}

MAPLIBRE_API double maplibre_get_camera_lat(void) {
    return readCameraValue([](const mln::CameraOptions& camera) {
        return camera.center ? camera.center->latitude() : 0.0;
    });
}

MAPLIBRE_API double maplibre_get_camera_lon(void) {
    return readCameraValue([](const mln::CameraOptions& camera) {
        return camera.center ? camera.center->longitude() : 0.0;
    });
}

MAPLIBRE_API double maplibre_get_camera_zoom(void) {
    return readCameraValue([](const mln::CameraOptions& camera) {
        return camera.zoom.value_or(0.0);
    });
}

MAPLIBRE_API double maplibre_get_camera_bearing(void) {
    return readCameraValue([](const mln::CameraOptions& camera) {
        return camera.bearing.value_or(0.0);
    });
}

MAPLIBRE_API double maplibre_get_camera_pitch(void) {
    return readCameraValue([](const mln::CameraOptions& camera) {
        return camera.pitch.value_or(0.0);
    });
}

} // extern "C"
