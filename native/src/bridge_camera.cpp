// Camera mutation, animation, queries, and gesture dispatch.
#include "bridge_session.hpp"
#include "bridge_camera_operation.hpp"

#include <algorithm>
#include <chrono>
#include <cstdio>

#include <mln/util/constants.hpp>

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

struct PendingCameraMutation {
    ~PendingCameraMutation() { complete(); }

    void complete() noexcept {
        if (!active.exchange(false, std::memory_order_acq_rel)) return;
        auto pending =
            g_pendingCameraMutations.load(std::memory_order_acquire);
        while (pending != 0 &&
               !g_pendingCameraMutations.compare_exchange_weak(
                   pending,
                   pending - 1,
                   std::memory_order_acq_rel,
                   std::memory_order_acquire)) {
        }
    }

    std::atomic<bool> active{true};
};

using PendingCameraMutationToken =
    std::shared_ptr<PendingCameraMutation>;

static PendingCameraMutationToken beginPendingCameraMutation(
    bool tracked) {
    if (!tracked) return {};
    auto token = std::make_shared<PendingCameraMutation>();
    g_pendingCameraMutations.fetch_add(1, std::memory_order_acq_rel);
    return token;
}

static void completePendingCameraMutation(
    const PendingCameraMutationToken& token) noexcept {
    if (token) token->complete();
}

template <typename Operation>
static int runCameraMutation(
    const char* name,
    Operation&& operation,
    bool tracksCameraFrame = true) noexcept {
#ifdef __ANDROID__
    using StoredOperation = std::decay_t<Operation>;
    auto storedOperation = std::make_shared<StoredOperation>(
        std::forward<Operation>(operation));
    const auto operationName = std::string(name);
    const auto pendingToken =
        beginPendingCameraMutation(tracksCameraFrame);
    const auto performOperation =
        [storedOperation, operationName, pendingToken]() -> bool {
            bool result = false;
            try {
                if (g_map) result = (*storedOperation)();
            } catch (const std::exception& error) {
                std::printf(
                    "[MapLibre] %s failed: %s\n",
                    operationName.c_str(),
                    error.what());
                std::fflush(stdout);
            } catch (...) {
                std::printf(
                    "[MapLibre] %s failed: unknown exception\n",
                    operationName.c_str());
                std::fflush(stdout);
            }
            completePendingCameraMutation(pendingToken);
            return result;
        };
    std::function<void()> deferredTask = [performOperation] {
        (void)performOperation();
    };

    const auto deferIfBlocked = [&](const std::function<void()>& task) {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        discardUnacquiredFrameLocked();
        if (!g_asyncFrame.acquired &&
            !g_asyncFrame.rendering && !g_asyncFrame.syncFrameOpen) {
            return false;
        }
        g_mapIdle.store(false, std::memory_order_relaxed);
        g_renderDirty.store(true, std::memory_order_release);
        g_asyncFrame.renderDeferred = true;
        g_asyncFrame.deferredMutations.push_back(task);
        return true;
    };

    // A queued render holds no lease. Keep mutations in owner queue order so
    // subsequent camera queries observe them before another frame is drawn.
    if (deferIfBlocked(deferredTask)) return 1;
    try {
        const int result = bridge_runOnOwnerSync([&]() -> int {
            // A render can publish a snapshot while this task waits in the
            // owner queue.
            if (deferIfBlocked(deferredTask)) return 2;
            return performOperation() ? 1 : 0;
        });
        return result != 0 ? 1 : 0;
    } catch (const std::exception& error) {
        std::printf("[MapLibre] %s failed: %s\n", name, error.what());
    } catch (...) {
        std::printf("[MapLibre] %s failed: unknown exception\n", name);
    }
    completePendingCameraMutation(pendingToken);
    std::fflush(stdout);
    return 0;
#else
    (void)tracksCameraFrame;
    return runCameraOperation(name, std::forward<Operation>(operation));
#endif
}

template <typename Operation>
static void postGestureOperation(const char* name, Operation&& operation) noexcept {
#ifdef __ANDROID__
    g_mapIdle.store(false, std::memory_order_relaxed);
    g_renderDirty.store(true, std::memory_order_release);
    const auto pendingToken = beginPendingCameraMutation(true);
    std::function<void()> task =
        [operation = std::forward<Operation>(operation),
         operationName = std::string(name),
         pendingToken]() mutable {
            try {
                if (g_map) operation();
            } catch (const std::exception& error) {
                std::printf(
                    "[MapLibre] %s failed: %s\n",
                    operationName.c_str(),
                    error.what());
                std::fflush(stdout);
            } catch (...) {
                std::printf(
                    "[MapLibre] %s failed: unknown exception\n",
                    operationName.c_str());
                std::fflush(stdout);
            }
            completePendingCameraMutation(pendingToken);
        };

    {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        discardUnacquiredFrameLocked();
        if (g_asyncFrame.acquired || g_asyncFrame.rendering ||
            g_asyncFrame.syncFrameOpen) {
            g_asyncFrame.deferredMutations.push_back(std::move(task));
            g_asyncFrame.renderDeferred = true;
            return;
        }
    }

    const bool posted = bridge_runOnOwnerAsync(
        [task = std::move(task)]() mutable {
            {
                std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
                discardUnacquiredFrameLocked();
                if (g_asyncFrame.acquired ||
                    g_asyncFrame.rendering || g_asyncFrame.syncFrameOpen) {
                    g_asyncFrame.deferredMutations.push_back(std::move(task));
                    g_asyncFrame.renderDeferred = true;
                    return;
                }
            }
            task();
        });
    if (!posted) {
        completePendingCameraMutation(pendingToken);
        std::printf("[MapLibre] %s rejected: owner thread unavailable\n", name);
        std::fflush(stdout);
    }
#else
    try {
        bridge_runOnOwnerSync(
            [operation = std::forward<Operation>(operation)]() mutable {
                if (g_map) operation();
            });
    } catch (...) {
    }
#endif
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

// ── Camera query ─────────────────────────────────────────────────────

MAPLIBRE_API int maplibre_get_camera(double* output) {
    if (!output) return 0;
    mln::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        output[0] = publishedCamera.center
            ? publishedCamera.center->latitude()
            : 0.0;
        output[1] = publishedCamera.center
            ? publishedCamera.center->longitude()
            : 0.0;
        output[2] = publishedCamera.zoom.value_or(0.0);
        output[3] = publishedCamera.bearing.value_or(0.0);
        output[4] = publishedCamera.pitch.value_or(0.0);
        return 1;
    }
    return runCameraOperation("get camera", [&] {
        const auto camera = g_map->getCameraOptions();
        output[0] = camera.center ? camera.center->latitude() : 0.0;
        output[1] = camera.center ? camera.center->longitude() : 0.0;
        output[2] = camera.zoom.value_or(0.0);
        output[3] = camera.bearing.value_or(0.0);
        output[4] = camera.pitch.value_or(0.0);
        return true;
    });
}

MAPLIBRE_API double maplibre_get_camera_lat(void) {
    mln::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return publishedCamera.center
            ? publishedCamera.center->latitude()
            : 0.0;
    }
    try {
        return bridge_runOnOwnerSync([] {
            if (!g_map) return 0.0;
            const auto camera = g_map->getCameraOptions();
            return camera.center ? camera.center->latitude() : 0.0;
        });
    } catch (...) {
        return 0.0;
    }
}

MAPLIBRE_API double maplibre_get_camera_lon(void) {
    mln::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return publishedCamera.center
            ? publishedCamera.center->longitude()
            : 0.0;
    }
    try {
        return bridge_runOnOwnerSync([] {
            if (!g_map) return 0.0;
            const auto camera = g_map->getCameraOptions();
            return camera.center ? camera.center->longitude() : 0.0;
        });
    } catch (...) {
        return 0.0;
    }
}

MAPLIBRE_API double maplibre_get_camera_zoom(void) {
    mln::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return publishedCamera.zoom.value_or(0.0);
    }
    try {
        return bridge_runOnOwnerSync([] {
            if (!g_map) return 0.0;
            return g_map->getCameraOptions().zoom.value_or(0.0);
        });
    } catch (...) {
        return 0.0;
    }
}

MAPLIBRE_API double maplibre_get_camera_bearing(void) {
    mln::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return publishedCamera.bearing.value_or(0.0);
    }
    try {
        return bridge_runOnOwnerSync([] {
            if (!g_map) return 0.0;
            return g_map->getCameraOptions().bearing.value_or(0.0);
        });
    } catch (...) {
        return 0.0;
    }
}

MAPLIBRE_API double maplibre_get_camera_pitch(void) {
    mln::CameraOptions publishedCamera;
    if (bridge_getPublishedCamera(publishedCamera)) {
        return publishedCamera.pitch.value_or(0.0);
    }
    try {
        return bridge_runOnOwnerSync([] {
            if (!g_map) return 0.0;
            return g_map->getCameraOptions().pitch.value_or(0.0);
        });
    } catch (...) {
        return 0.0;
    }
}

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
