#include "repaint_budget.hpp"
#include <cassert>

int main() {
    StationaryRepaintBudget budget;
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
}
