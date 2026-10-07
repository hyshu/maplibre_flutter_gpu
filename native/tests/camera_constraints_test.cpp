#include <mln/map/mode.hpp>

#include <cassert>
#include <optional>
#include <utility>

#define MAPLIBRE_API

namespace mln {
struct LatLngBounds {
    bool constrained = false;
    bool operator==(const LatLngBounds&) const = default;
};
}

struct CameraMap {
    mln::ConstrainMode mode = mln::ConstrainMode::HeightOnly;
    std::optional<mln::ConstrainMode> overrideMode;
    std::optional<mln::LatLngBounds> bounds;

    struct Bounds {
        std::optional<mln::LatLngBounds> bounds;
    };

    void setConstrainMode(mln::ConstrainMode value) { mode = value; }
    Bounds getBounds() const { return {bounds}; }
};

static CameraMap* g_map;
#define g_cameraConstrainMode g_map->overrideMode

template <typename Operation>
int runCameraMutation(const char*, Operation&& operation, bool) {
    if (!g_map) return 0;
    return std::forward<Operation>(operation)() ? 1 : 0;
}

#include "camera_constraints.inc"

int main() {
    CameraMap first;
    CameraMap second;
    g_map = &first;

    maplibre_set_constrain_mode(0);
    assert(first.mode == mln::ConstrainMode::None);
    maplibre_set_constrain_mode(1);
    assert(first.mode == mln::ConstrainMode::HeightOnly);
    maplibre_set_constrain_mode(2);
    assert(first.mode == mln::ConstrainMode::Screen);

    maplibre_set_constrain_mode(-2);
    assert(first.mode == mln::ConstrainMode::Screen);
    maplibre_set_constrain_mode(3);
    assert(first.mode == mln::ConstrainMode::Screen);

    maplibre_set_constrain_mode(-1);
    assert(first.mode == mln::ConstrainMode::HeightOnly);
    assert(!first.overrideMode);
    first.bounds = mln::LatLngBounds{true};
    maplibre_set_constrain_mode(0);
    maplibre_set_constrain_mode(-1);
    assert(first.mode == mln::ConstrainMode::Screen);
    assert(!first.overrideMode);

    g_map = &second;
    maplibre_set_constrain_mode(0);
    assert(second.mode == mln::ConstrainMode::None);
    assert(second.overrideMode == mln::ConstrainMode::None);
    assert(first.mode == mln::ConstrainMode::Screen);

    g_map = nullptr;
    maplibre_set_constrain_mode(1);
    assert(second.mode == mln::ConstrainMode::None);
}
