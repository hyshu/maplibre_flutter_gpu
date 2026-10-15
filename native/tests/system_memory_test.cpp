#include "memory/system_memory.hpp"

#include <cassert>
#include <cstdio>

int main() {
    using namespace maplibre_bridge::memory;
    const auto physical = physicalMemoryBytes();
    const auto available = availableMemoryBytes();
    const auto used = memoryUsageBytes();
#if defined(__APPLE__) || defined(_WIN32) || defined(__linux__)
    assert(physical > 0);
    assert(available > 0 && available <= physical);
    assert(used > 0);
#else
    assert(physical == 0 && available == 0 && used == 0);
#endif
    std::puts("Session-independent system memory queries passed");
}
