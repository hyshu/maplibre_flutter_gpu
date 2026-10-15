#pragma once

#include <cstdint>

namespace maplibre_bridge::memory {

// These queries are session-independent. All values are bytes and zero means
// the operating system could not provide the measurement.
uint64_t physicalMemoryBytes() noexcept;

// Available memory includes reclaimable pages when the platform reports them.
// On iOS it is also limited by the current process's allocation headroom.
uint64_t availableMemoryBytes() noexcept;

// Apple reports physical footprint. Linux and Windows report resident memory.
uint64_t memoryUsageBytes() noexcept;

} // namespace maplibre_bridge::memory
