# Flutter loads the prebuilt bridge through Dart FFI. This CMake target only
# places the x64 library next to the application executable.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "maplibre_flutter_gpu")
project(${PROJECT_NAME} LANGUAGES CXX)

string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" MAPLIBRE_SYSTEM_PROCESSOR)
if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8 OR
   NOT MAPLIBRE_SYSTEM_PROCESSOR MATCHES "^(amd64|x86_64)$")
  message(FATAL_ERROR "maplibre_flutter_gpu currently supports Windows x64 only")
endif()

set(MAPLIBRE_BRIDGE
  "${CMAKE_CURRENT_SOURCE_DIR}/x64/maplibre_bridge.dll")
if(NOT EXISTS "${MAPLIBRE_BRIDGE}")
  message(FATAL_ERROR
    "MapLibre bridge not found at ${MAPLIBRE_BRIDGE}. Install the x64 native artifact.")
endif()

set(maplibre_flutter_gpu_bundled_libraries
  "${MAPLIBRE_BRIDGE}"
  PARENT_SCOPE
)
