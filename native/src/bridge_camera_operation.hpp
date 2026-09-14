#pragma once

#include "bridge_state.hpp"

#include <cstdio>

// Returns zero when the selected map is unavailable or the operation fails.
template <typename Operation>
int runCameraOperation(const char* name, Operation&& operation) noexcept {
    try {
        return bridge_runOnOwnerSync([&]() -> int {
            if (!g_map) return 0;
            return operation() ? 1 : 0;
        });
    } catch (const std::exception& error) {
        printf("[MapLibre] %s failed: %s\n", name, error.what());
    } catch (...) {
        printf("[MapLibre] %s failed: unknown exception\n", name);
    }
    fflush(stdout);
    return 0;
}
