#include <array>
#include <cassert>
#include <cstdio>
#include <future>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <thread>
#include <utility>

#define MAPLIBRE_API

static bool ownerAvailable = true;
static unsigned ownerCalls = 0;
static std::thread::id ownerThread;

struct Coordinate {
    double lat;
    double lon;

    double latitude() const {
#if !FRAME_CAMERA_TEST_ANDROID
        assert(std::this_thread::get_id() == ownerThread);
#endif
        return lat;
    }

    double longitude() const { return lon; }
};

struct Camera {
    std::optional<Coordinate> center;
    std::optional<double> zoom;
    std::optional<double> bearing;
    std::optional<double> pitch;
};

static std::optional<Camera> g_snapshotCamera;
static struct {
    std::mutex mutex;
    bool ready = false;
    bool acquired = false;
} g_asyncFrame;

template <typename Operation>
int bridge_runOnOwnerSync(Operation operation) {
    ++ownerCalls;
    if (!ownerAvailable) throw std::runtime_error("owner unavailable");
    std::packaged_task<int()> task([operation = std::move(operation)] {
        ownerThread = std::this_thread::get_id();
        return operation();
    });
    auto result = task.get_future();
    std::thread owner(std::move(task));
    owner.join();
    return result.get();
}

#if FRAME_CAMERA_TEST_ANDROID
#define __ANDROID__
#endif
#include "frame_camera.inc"

using Values = std::array<double, 5>;
static constexpr Values sentinel{1, 2, 3, 4, 5};

static void assertUnavailable() {
    auto output = sentinel;
    assert(maplibre_frame_get_camera(output.data()) == 0);
    assert(output == sentinel);
}

static void assertCamera(const Values& expected) {
    auto output = sentinel;
    assert(maplibre_frame_get_camera(output.data()) == 1);
    assert(output == expected);
}

int main() {
    assert(maplibre_frame_get_camera(nullptr) == 0);
    assert(ownerCalls == 0);
    assertUnavailable();

    g_snapshotCamera = Camera{{Coordinate{35, 139}}, 12, 17, 25};
    g_asyncFrame.ready = true;
    assertCamera({35, 139, 12, 17, 25});
    const auto callsBeforeNull = ownerCalls;
    assert(maplibre_frame_get_camera(nullptr) == 0);
    assert(ownerCalls == callsBeforeNull);
    assertCamera({35, 139, 12, 17, 25});

    g_asyncFrame.ready = false;
    g_asyncFrame.acquired = true;
    g_snapshotCamera = Camera{{Coordinate{36, 140}}, 10, 41, 7};
    assertCamera({36, 140, 10, 41, 7});

    // Releasing a lease can leave the previous snapshot in storage.
    g_asyncFrame.acquired = false;
#if FRAME_CAMERA_TEST_ANDROID
    assertUnavailable();
    assert(ownerCalls == 0);
#else
    assertCamera({36, 140, 10, 41, 7});
    assert(ownerCalls > 0);
    ownerAvailable = false;
    assertUnavailable();
    ownerAvailable = true;
#endif

    g_asyncFrame.acquired = true;
    g_snapshotCamera.reset();
    assertUnavailable();
    g_asyncFrame.acquired = false;
    g_asyncFrame.ready = true;
    assertUnavailable();

    g_snapshotCamera = Camera{};
    assertCamera({0, 0, 0, 0, 0});
    std::puts(FRAME_CAMERA_TEST_ANDROID
        ? "Android frame camera lease guards passed"
        : "Synchronous frame camera owner guards passed");
}
