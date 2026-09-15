#include "repaint_budget.hpp"
#include <cassert>
#include <limits>

int main() {
    StationaryRepaintBudget budget;
    using Clock = StationaryRepaintBudget::Clock;
    using Milliseconds = StationaryRepaintBudget::Milliseconds;
    const auto start = Clock::time_point{};
    budget.setMinimumDuration(Milliseconds(0));
    for (int i = 0; i < 1000; ++i) assert(!budget.expired(false, false));
    for (int i = 0; i < 29; ++i) assert(!budget.expired(false, true));
    assert(budget.expired(false, true));
    assert(budget.expired(false, true));
    budget.reset();
    for (int i = 0; i < 29; ++i) assert(!budget.expired(false, true));
    assert(budget.expired(false, true));
    assert(!budget.expired(true, true));
    assert(!budget.expired(false, true));
    assert(!budget.expired(false, false));
    assert(!budget.expired(false, true));

    budget.setMinimumDuration(Milliseconds(2000));
    for (int i = 0; i < 1000; ++i) {
        assert(!budget.expired(false, true, start + std::chrono::milliseconds(i)));
    }
    assert(!budget.expired(false, true, start + std::chrono::milliseconds(1999)));
    assert(budget.expired(false, true, start + std::chrono::milliseconds(2000)));

    budget.reset();
    const auto delayedFirstFrame = start + std::chrono::hours(1);
    for (int i = 0; i < 30; ++i) {
        assert(!budget.expired(false, true, delayedFirstFrame));
    }
    assert(!budget.expired(false, true, delayedFirstFrame + std::chrono::milliseconds(1999)));
    assert(budget.expired(false, true, delayedFirstFrame + std::chrono::milliseconds(2000)));

    budget.setMinimumDuration(Milliseconds(std::numeric_limits<double>::infinity()));
    for (int i = 0; i < 1000; ++i) {
        assert(!budget.expired(false, true, start + std::chrono::hours(i)));
    }
}
