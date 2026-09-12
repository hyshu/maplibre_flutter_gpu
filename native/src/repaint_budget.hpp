#pragma once

#include <cstdint>

// Bounds consecutive stationary transition frames between external updates.
class StationaryRepaintBudget {
public:
    void reset() { frames = 0; }

    bool expired(bool cameraMoving, bool needsRepaint) {
        if (cameraMoving || !needsRepaint) {
            reset();
            return false;
        }
        if (frames < limit) ++frames;
        return frames >= limit;
    }

private:
    static constexpr uint32_t limit = 30;
    uint32_t frames = 0;
};
