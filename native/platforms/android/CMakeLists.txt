cmake_minimum_required(VERSION 3.25 FATAL_ERROR)

project(maplibre_fluttergpu_android LANGUAGES C CXX)

if(NOT ANDROID)
    message(FATAL_ERROR "This build is only supported with the Android NDK toolchain")
endif()

get_filename_component(
    MAPLIBRE_FLUTTERGPU_NATIVE_ROOT
    "${CMAKE_CURRENT_SOURCE_DIR}/../.."
    ABSOLUTE
)
include(${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/cmake/bridge_sources.cmake)

set(MAPLIBRE_NATIVE_SOURCE_DIR
    "${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/../vendor/maplibre-native"
    CACHE PATH
    "MapLibre Native source directory"
)
if(NOT EXISTS "${MAPLIBRE_NATIVE_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "MapLibre Native submodule is not initialized")
endif()

set(MLN_WITH_CORE_ONLY OFF CACHE BOOL "" FORCE)
set(MLN_WITH_COMMAND_EXPORT ON CACHE BOOL "" FORCE)
set(MLN_WITH_EGL OFF CACHE BOOL "" FORCE)
set(MLN_WITH_OPENGL OFF CACHE BOOL "" FORCE)
set(MLN_WITH_METAL OFF CACHE BOOL "" FORCE)
set(MLN_WITH_VULKAN OFF CACHE BOOL "" FORCE)
set(MLN_WITH_WEBGPU OFF CACHE BOOL "" FORCE)
set(MLN_WITH_GLFW OFF CACHE BOOL "" FORCE)
set(MLN_WITH_NODE OFF CACHE BOOL "" FORCE)
set(MLN_WITH_QT OFF CACHE BOOL "" FORCE)
set(MLN_WITH_WERROR OFF CACHE BOOL "" FORCE)
set(MLN_USE_UNORDERED_DENSE ON CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)

add_subdirectory(
    "${MAPLIBRE_NATIVE_SOURCE_DIR}"
    "${CMAKE_BINARY_DIR}/vendor/maplibre-native"
    EXCLUDE_FROM_ALL
)

set(_MLN "${MAPLIBRE_NATIVE_SOURCE_DIR}")

# android.cmake supplies the platform RunLoop, image decoder, storage stack,
# and common headless frontend. The Command Export backend and these portable
# implementations are not part of the regular Android MapLibre SDK target.
target_sources(
    mbgl-core
    PRIVATE
        ${_MLN}/platform/default/src/mbgl/command_export/headless_backend.cpp
        ${_MLN}/platform/default/src/mbgl/i18n/collator.cpp
        ${_MLN}/platform/default/src/mbgl/i18n/number_format.cpp
        ${_MLN}/platform/default/src/mbgl/text/local_glyph_rasterizer.cpp
        ${_MLN}/platform/default/src/mbgl/util/logging_stderr.cpp
)

include(${_MLN}/vendor/nunicode.cmake)
target_link_libraries(mbgl-core PRIVATE mbgl-vendor-nunicode)

set_property(
    SOURCE ${_MLN}/platform/default/src/mbgl/i18n/number_format.cpp
    TARGET_DIRECTORY mbgl-core
    APPEND PROPERTY COMPILE_DEFINITIONS MBGL_USE_BUILTIN_ICU
)

add_library(
    maplibre_bridge
    SHARED
        ${MAPLIBRE_FLUTTERGPU_BRIDGE_SOURCES}
        ${CMAKE_CURRENT_SOURCE_DIR}/android_jni.cpp
        ${_MLN}/platform/android/MapLibreAndroid/src/cpp/http_file_source.cpp
)

target_compile_features(maplibre_bridge PRIVATE cxx_std_20)
target_compile_options(maplibre_bridge PRIVATE -fno-rtti)
target_compile_definitions(
    maplibre_bridge
    PRIVATE
        MLN_RENDER_BACKEND_COMMAND_EXPORT=1
        MLN_TEXT_SHAPING_HARFBUZZ=1
        MLN_USE_UNORDERED_DENSE=1
        RAPIDJSON_HAS_STDSTRING=1
)
target_include_directories(
    maplibre_bridge
    PRIVATE
        ${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/src
        ${_MLN}/src
        ${_MLN}/include
        ${_MLN}/platform/default/include
        ${_MLN}/platform/android/src
        ${_MLN}/platform/android/MapLibreAndroid/src/cpp
)
target_link_libraries(
    maplibre_bridge
    PRIVATE
        mbgl-core
        MapLibreNative::Base::jni.hpp
)
target_link_options(
    maplibre_bridge
    PRIVATE
        # Each active Android map uses a separately loaded image. Keep its
        # internal references bound to that image's own native state.
        -Wl,-Bsymbolic
        -Wl,--no-undefined
        -Wl,--exclude-libs,ALL
        -Wl,-z,max-page-size=16384
)
set_target_properties(
    maplibre_bridge
    PROPERTIES
        CXX_EXTENSIONS OFF
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN YES
        OUTPUT_NAME maplibre_bridge
)
