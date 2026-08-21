#include "bridge_state.hpp"

#include <cstdint>
#include <cstdio>

namespace {

constexpr std::uint32_t kFillExtrusionGpuReady = 1u << 0;
constexpr std::uint32_t kBridgeFeatureFlags = kFillExtrusionGpuReady;
constexpr const char* kBridgeBuildMarker = "fe-gpu-ready-v1";

#if defined(__GNUC__) || defined(__clang__)
__attribute__((constructor)) void logBridgeFeatures() {
    std::fprintf(
        stderr,
        "[MapLibre] bridge features=0x%08x build=%s\n",
        static_cast<unsigned int>(kBridgeFeatureFlags),
        kBridgeBuildMarker);
    std::fflush(stderr);
}
#endif

} // namespace

extern "C" MAPLIBRE_API std::uint32_t maplibre_bridge_feature_flags() {
    return kBridgeFeatureFlags;
}
