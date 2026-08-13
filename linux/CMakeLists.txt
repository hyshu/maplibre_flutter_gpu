# Flutter loads the prebuilt bridge through Dart FFI. This CMake target only
# places the architecture-specific library in the application bundle.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "maplibre_flutter_gpu")
project(${PROJECT_NAME} LANGUAGES CXX)

string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" MAPLIBRE_SYSTEM_PROCESSOR)
if(NOT MAPLIBRE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64)$")
  message(FATAL_ERROR
    "maplibre_flutter_gpu does not provide a Linux bridge for ${CMAKE_SYSTEM_PROCESSOR}")
endif()

set(MAPLIBRE_BRIDGE
  "${CMAKE_CURRENT_SOURCE_DIR}/x64/libmaplibre_bridge.so")
if(NOT EXISTS "${MAPLIBRE_BRIDGE}")
  message(FATAL_ERROR
    "MapLibre bridge not found at ${MAPLIBRE_BRIDGE}. Install the matching native artifact.")
endif()

set(maplibre_flutter_gpu_bundled_libraries
  "${MAPLIBRE_BRIDGE}"
  PARENT_SCOPE
)
