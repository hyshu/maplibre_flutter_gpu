#pragma once

#include <cstdint>
#include <chrono>
#include <optional>

// Bounds stationary repaint work after configured transition time has elapsed.
class StationaryRepaintBudget {
public:
    using Clock = std::chrono::steady_clock;
    using Milliseconds = std::chrono::duration<double, std::milli>;

    void reset() {
        frames = 0;
        transitionStarted.reset();
    }

    // An infinite duration disables expiry for transitions with unknown timing.
    void setMinimumDuration(Milliseconds duration) {
        minimumDuration = duration;
        reset();
    }

    bool expired(bool cameraMoving, bool needsRepaint,
                 Clock::time_point now = Clock::now()) {
        if (cameraMoving || !needsRepaint) {
            reset();
            return false;
        }
        if (!transitionStarted) transitionStarted = now;
        if (frames < limit) ++frames;
        return frames >= limit && now - *transitionStarted >= minimumDuration;
    }

private:
    static constexpr uint32_t limit = 30;
    uint32_t frames = 0;
    Milliseconds minimumDuration{300};
    std::optional<Clock::time_point> transitionStarted;
};
