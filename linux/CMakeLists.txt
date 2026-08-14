# Flutter loads the prebuilt bridge through Dart FFI. This CMake target only
# places the architecture-specific library in the application bundle.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "maplibre_flutter_gpu")
project(${PROJECT_NAME} LANGUAGES CXX)

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR
    "maplibre_flutter_gpu requires a 64-bit Linux target")
endif()

if(DEFINED FLUTTER_TARGET_PLATFORM)
  if(FLUTTER_TARGET_PLATFORM STREQUAL "linux-x64")
    set(MAPLIBRE_ARCHITECTURE_DIR "x64")
  elseif(FLUTTER_TARGET_PLATFORM STREQUAL "linux-arm64")
    set(MAPLIBRE_ARCHITECTURE_DIR "arm64")
  else()
    message(FATAL_ERROR
      "maplibre_flutter_gpu does not provide a bridge for ${FLUTTER_TARGET_PLATFORM}")
  endif()
else()
  string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" MAPLIBRE_SYSTEM_PROCESSOR)
  if(MAPLIBRE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64)$")
    set(MAPLIBRE_ARCHITECTURE_DIR "x64")
  elseif(MAPLIBRE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
    set(MAPLIBRE_ARCHITECTURE_DIR "arm64")
  else()
    message(FATAL_ERROR
      "maplibre_flutter_gpu does not provide a Linux bridge for ${CMAKE_SYSTEM_PROCESSOR}")
  endif()
endif()

set(MAPLIBRE_BRIDGE
  "${CMAKE_CURRENT_SOURCE_DIR}/${MAPLIBRE_ARCHITECTURE_DIR}/libmaplibre_bridge.so")
if(NOT EXISTS "${MAPLIBRE_BRIDGE}")
  message(FATAL_ERROR
    "MapLibre bridge not found at ${MAPLIBRE_BRIDGE}. Install the matching native artifact.")
endif()

set(maplibre_flutter_gpu_bundled_libraries
  "${MAPLIBRE_BRIDGE}"
  PARENT_SCOPE
)
