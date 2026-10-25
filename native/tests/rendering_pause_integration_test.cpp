#include "bridge_session.hpp"

#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdio>
#include <future>
#include <thread>

extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
int maplibre_init(int, int, float, const char*);
int maplibre_style_set(const char*);
int maplibre_render_frame();
void maplibre_frame_begin();
void maplibre_frame_end();
int maplibre_set_rendering_paused(int);
void maplibre_set_rendering_paused_async(int, void (*)(int));
int maplibre_camera_ease_to(double, double, double, double, double, int, int);
int maplibre_process_events();
void maplibre_set_render_request_callback(void (*)());
void maplibre_destroy();
void maplibre_shutdown_all();
}

static constexpr const char* style = R"({"version":8,"sources":{},"layers":[]})";
static std::atomic<int> renderWakes{0};
static std::promise<int>* pauseCompletion = nullptr;
static std::promise<int>* resumeCompletion = nullptr;

static void renderRequested() {
    ++renderWakes;
}

static void renderingPauseCompleted(int result) {
    pauseCompletion->set_value(result);
}

static void renderingResumeCompleted(int result) {
    resumeCompletion->set_value(result);
}

static void checkSupersededPause(void* target, void* busyMap, bool newCamera) {
    maplibre_session_select(target);
    assert(maplibre_camera_ease_to(10, 10, 3, 0, 0, 10000, 0) == 1);
    assert(g_cameraMoving);
    maplibre_session_select(busyMap);
    std::promise<void> started;
    std::promise<void> release;
    auto released = release.get_future().share();
    assert(bridge_runOnOwnerAsync([&] {
        started.set_value();
        released.wait();
    }));
    started.get_future().wait();
    maplibre_session_select(target);
    std::promise<int> paused;
    std::promise<int> resumed;
    pauseCompletion = &paused;
    resumeCompletion = &resumed;
    maplibre_set_rendering_paused_async(1, renderingPauseCompleted);
    std::future<int> camera;
    if (newCamera) {
        const auto oldGeneration = g_cameraCommandGeneration.load();
        camera = std::async(std::launch::async, [target] {
            maplibre_session_select(target);
            return maplibre_camera_ease_to(20, 20, 5, 0, 0, 10000, 0);
        });
        while (g_cameraCommandGeneration == oldGeneration) std::this_thread::yield();
    }
    maplibre_set_rendering_paused_async(0, renderingResumeCompleted);
    release.set_value();
    assert(paused.get_future().get() == 0);
    assert(resumed.get_future().get() == 1);
    if (newCamera) assert(camera.get() == 1);
    assert(!g_renderingPaused);
    assert(g_cameraMoving == newCamera);
}

static void checkAsyncBarrier(void* target, void* busyMap, bool paused) {
    maplibre_session_select(busyMap);
    std::promise<void> started;
    std::promise<void> release;
    auto released = release.get_future().share();
    assert(bridge_runOnOwnerAsync([&] {
        started.set_value();
        released.wait();
    }));
    started.get_future().wait();
    std::promise<int> completed;
    pauseCompletion = &completed;
    auto completion = completed.get_future();
    auto requested = std::async(std::launch::async, [target, paused] {
        maplibre_session_select(target);
        maplibre_set_rendering_paused_async(paused ? 1 : 0, renderingPauseCompleted);
    });
    const auto returned = requested.wait_for(std::chrono::milliseconds(250));
    const auto beforeBarrier = completion.wait_for(std::chrono::milliseconds(0));
    maplibre_session_select(target);
    assert(g_renderingPaused);
    release.set_value();
    requested.get();
    assert(completion.get() == 1);
    assert(returned == std::future_status::ready);
    assert(beforeBarrier == std::future_status::timeout);
    assert(g_renderingPaused == paused);
}

int main() {
    auto* first = maplibre_session_create();
    auto* second = maplibre_session_create();
    maplibre_session_select(first);
    assert(maplibre_init(256, 256, 1, style) == 0);
    assert(maplibre_render_frame() == 0);
    maplibre_session_select(second);
    assert(maplibre_init(256, 256, 1, style) == 0);
    assert(maplibre_render_frame() == 0);

    // The pause call cannot complete while earlier owner-thread work runs.
    maplibre_session_select(first);
    maplibre_set_render_request_callback(renderRequested);
    std::promise<void> started;
    std::promise<void> release;
    auto released = release.get_future().share();
    assert(bridge_runOnOwnerAsync([&] {
        started.set_value();
        released.wait();
    }));
    started.get_future().wait();
    std::atomic<bool> completed{false};
    std::thread pauser([&] {
        maplibre_session_select(first);
        assert(maplibre_set_rendering_paused(1) == 1);
        completed = true;
    });
    while (!g_renderingPaused.load()) std::this_thread::yield();
    assert(!completed);
    release.set_value();
    pauser.join();
    assert(completed);

    const auto wakesBeforeChanges = renderWakes.load();
    assert(maplibre_style_set(style) == 1);
    for (int index = 0; index < 100; ++index) {
        maplibre_frame_begin();
        assert(maplibre_render_frame() == -3);
        maplibre_frame_end();
        assert(maplibre_process_events() == 0);
    }
    assert(g_renderDirty);
    assert(renderWakes == wakesBeforeChanges);

    maplibre_session_select(second);
    assert(!g_renderingPaused);
    assert(maplibre_render_frame() == 0);

    // Resuming only opens an atomic gate. Another map's owner work must not
    // block the UI thread before the caller can schedule its next frame.
    std::promise<void> otherMapStarted;
    std::promise<void> releaseOtherMap;
    auto otherMapReleased = releaseOtherMap.get_future().share();
    assert(bridge_runOnOwnerAsync([&] {
        otherMapStarted.set_value();
        otherMapReleased.wait();
    }));
    otherMapStarted.get_future().wait();
    auto resumed = std::async(std::launch::async, [first] {
        maplibre_session_select(first);
        return maplibre_set_rendering_paused(0);
    });
    const auto resumeStatus = resumed.wait_for(std::chrono::milliseconds(250));
    releaseOtherMap.set_value();
    assert(resumed.get() == 1);
    assert(resumeStatus == std::future_status::ready);

    maplibre_session_select(first);
    assert(maplibre_set_rendering_paused(0) == 1);
    checkAsyncBarrier(first, second, true);
    checkAsyncBarrier(first, second, false);
    checkSupersededPause(first, second, false);
    checkSupersededPause(first, second, true);
    maplibre_frame_begin();
    assert(maplibre_render_frame() == 0);
    maplibre_frame_end();
    std::promise<int> disposedPause;
    pauseCompletion = &disposedPause;
    auto disposedCompletion = disposedPause.get_future();
    maplibre_set_rendering_paused_async(1, renderingPauseCompleted);
    maplibre_destroy();
    assert(disposedCompletion.wait_for(std::chrono::milliseconds(250)) ==
           std::future_status::ready);
    const auto disposedResult = disposedCompletion.get();
    assert(disposedResult == 0 || disposedResult == 1);
    assert(!g_renderingPaused);
    maplibre_session_release(first);

    maplibre_session_select(second);
    maplibre_destroy();
    maplibre_session_release(second);
    maplibre_shutdown_all();
    std::puts("Native per-session rendering pause passed");
}
