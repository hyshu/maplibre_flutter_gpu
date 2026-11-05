#pragma once

#include <cstdio>
#include <cstdlib>

[[noreturn]] inline void maplibreTestCheckFailed(const char* expression, const char* file, int line) {
    std::fprintf(stderr, "%s:%d: check failed: %s\n", file, line, expression);
    std::abort();
}

// Checks remain active without changing the core headers' build configuration.
#define MAPLIBRE_TEST_CHECK(condition) \
    do { \
        if (!(condition)) maplibreTestCheckFailed(#condition, __FILE__, __LINE__); \
    } while (false)
