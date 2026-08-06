#ifndef MAPLIBRE_FLUTTER_GPU_MAPLIBRE_BRIDGE_H_
#define MAPLIBRE_FLUTTER_GPU_MAPLIBRE_BRIDGE_H_

#ifdef __cplusplus
extern "C" {
#endif

// Returns the retained FFI symbol table so static linkers keep every entry point.
__attribute__((visibility("default")))
const void* maplibre_flutter_gpu_force_link(void);

#ifdef __cplusplus
}
#endif

#endif  // MAPLIBRE_FLUTTER_GPU_MAPLIBRE_BRIDGE_H_
