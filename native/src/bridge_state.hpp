// Shared state and interfaces between the bridge translation units.
#pragma once

#include <cstddef>
#include <functional>
#include <future>
#include <memory>
#include <stdexcept>
#include <type_traits>
#include <utility>
#include <vector>

#include <mbgl/gfx/headless_frontend.hpp>
#include <mbgl/map/map.hpp>

namespace mbgl {
class TransformState;
namespace util {
class RunLoop;
}
}

// Opaque native session selected for the current bridge call/thread.
void* bridge_currentSession();
void bridge_selectSession(void* session);

class BridgeSessionActivation {
public:
    explicit BridgeSessionActivation(void* session)
        : previous(bridge_currentSession()) {
        bridge_selectSession(session);
    }
    ~BridgeSessionActivation() { bridge_selectSession(previous); }
    BridgeSessionActivation(const BridgeSessionActivation&) = delete;
    BridgeSessionActivation& operator=(const BridgeSessionActivation&) = delete;

private:
    void* previous;
};

// Ensure FFI entry points survive hidden visibility and dead-code stripping.
#if defined(_WIN32)
#define MAPLIBRE_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define MAPLIBRE_API __attribute__((used, visibility("default")))
#else
#define MAPLIBRE_API
#endif

// Selected-session storage owned by maplibre_bridge.cpp.
std::unique_ptr<mbgl::HeadlessFrontend>& bridge_frontendStorage();
std::unique_ptr<mbgl::Map>& bridge_mapStorage();
std::unique_ptr<mbgl::util::RunLoop>& bridge_runLoopStorage();

#define g_frontend bridge_frontendStorage()
#define g_map bridge_mapStorage()
#define g_run_loop bridge_runLoopStorage()

// MapLibre's RunLoop, Map, and HeadlessFrontend have thread affinity. A single
// process-wide runtime thread owns the RunLoop and serializes every session.
// Individual tasks reactivate their explicit session before touching map state.
bool bridge_startOwnerThread();
void bridge_stopOwnerThread();
bool bridge_ownerThreadRunning();
bool bridge_isOwnerThread();
bool bridge_postOwnerTask(std::function<void()> task);
void bridge_handleOwnerThreadExit() noexcept;

template <typename Operation>
auto bridge_runOnOwnerSync(Operation&& operation)
    -> std::invoke_result_t<Operation> {
    using Result = std::invoke_result_t<Operation>;
    void* session = bridge_currentSession();
    if (bridge_isOwnerThread()) {
        BridgeSessionActivation activation(session);
        if constexpr (std::is_void_v<Result>) {
            std::forward<Operation>(operation)();
            return;
        } else {
            return std::forward<Operation>(operation)();
        }
    }
    if (!bridge_ownerThreadRunning()) {
        throw std::runtime_error("MapLibre owner thread is unavailable");
    }

    auto task = std::make_shared<std::packaged_task<Result()>>(
        [session, operation = std::forward<Operation>(operation)]() mutable -> Result {
            BridgeSessionActivation activation(session);
            if constexpr (std::is_void_v<Result>) {
                operation();
                return;
            } else {
                return operation();
            }
        });
    auto result = task->get_future();
    if (!bridge_postOwnerTask([task] { (*task)(); })) {
        throw std::runtime_error("MapLibre owner thread is unavailable");
    }
    // The queued closure must be the sole packaged_task owner while waiting.
    // If an abnormal RunLoop exit drops its queue, destroying that closure
    // then completes the future with broken_promise instead of hanging FFI.
    task.reset();
    if constexpr (std::is_void_v<Result>) {
        result.get();
        return;
    } else {
        return result.get();
    }
}

template <typename Operation>
bool bridge_runOnOwnerAsync(Operation&& operation) {
    if (!bridge_ownerThreadRunning()) return false;
    void* session = bridge_currentSession();
    return bridge_postOwnerTask([session, operation = std::forward<Operation>(operation)]() mutable {
        BridgeSessionActivation activation(session);
        operation();
    });
}

// Resets observer-owned state before a runtime style reload begins.
void bridge_markStyleLoading();
void bridge_releaseStyleSession(void* session);

// Invalidates an unacquired Android frame before a synchronous style mutation.
// Dart releases an acquired generation before entering style mutation APIs.
bool bridge_prepareSynchronousMutation();

// True after MapLibre reports that the current style has finished loading.
bool bridge_isStyleLoaded();

// Reads projection/camera state captured from the currently published Android
// command generation. False means no snapshot is ready/acquired and callers
// should query the live owner-thread Map instead.
bool bridge_getPublishedCamera(mbgl::CameraOptions& camera);
bool bridge_projectPublishedCoordinates(
    const double* latitudes,
    std::size_t latitudeStride,
    const double* longitudes,
    std::size_t longitudeStride,
    float* outX,
    float* outY,
    int count);
bool bridge_unprojectPublishedCoordinate(
    double x,
    double y,
    double& latitude,
    double& longitude);
bool bridge_getPublishedVisibleRegion(
    double& south,
    double& west,
    double& north,
    double& east);

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
#include <mbgl/command_export/draw_command.hpp>

// Frozen copy of the merged frame commands, read by Dart via FFI.
// Owned by maplibre_bridge.cpp (maplibre_frame_end).
std::vector<mbgl::command_export::DrawCommand>& bridge_snapshotStorage();

// Set once placed-symbol collection has been enabled on the renderer.
bool& bridge_labelCollectionEnabledStorage();

#define g_snapshot bridge_snapshotStorage()
#define g_labelCollectionEnabled bridge_labelCollectionEnabledStorage()

// bridge_merge.cpp: cross-tile merge of fill/background draw commands
void bridge_mergeCommands(mbgl::command_export::FrameData& fd);
void bridge_resetMergeStorage();
void bridge_releaseMergeSession(void* session);

// bridge_labels.cpp: label extraction from placed symbol data
void bridge_extractLabels(const mbgl::TransformState* renderedState = nullptr);
void bridge_resetLabels();
void bridge_releaseLabelSession(void* session);
#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT
