cmake_minimum_required(VERSION 3.25 FATAL_ERROR)

project(maplibre_fluttergpu_bridge LANGUAGES C CXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
    message(FATAL_ERROR "native/platforms/linux builds the Linux bridge only")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "The Linux bridge requires a 64-bit target")
endif()

set(MAPLIBRE_TARGET_ARCHITECTURE "" CACHE STRING
    "Linux bridge architecture")
if(NOT MAPLIBRE_TARGET_ARCHITECTURE)
    string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" MAPLIBRE_SYSTEM_PROCESSOR)
    if(MAPLIBRE_SYSTEM_PROCESSOR MATCHES "^(amd64|x86_64)$")
        set(MAPLIBRE_TARGET_ARCHITECTURE "x64")
    elseif(MAPLIBRE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
        set(MAPLIBRE_TARGET_ARCHITECTURE "arm64")
    endif()
endif()
if(NOT MAPLIBRE_TARGET_ARCHITECTURE MATCHES "^(x64|arm64)$")
    message(FATAL_ERROR
        "Unsupported Linux bridge architecture: ${MAPLIBRE_TARGET_ARCHITECTURE}")
endif()

get_filename_component(
    MAPLIBRE_FLUTTERGPU_NATIVE_ROOT
    "${CMAKE_CURRENT_SOURCE_DIR}/../.."
    ABSOLUTE
)
include(${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/cmake/bridge_sources.cmake)
include(${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/cmake/maplibre_default_sources.cmake)

set(MAPLIBRE_NATIVE_SOURCE_DIR
    "${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/../vendor/maplibre-native"
    CACHE PATH
    "MapLibre Native source directory"
)
if(NOT EXISTS "${MAPLIBRE_NATIVE_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "MapLibre Native submodule is not initialized")
endif()

# Core-only mode avoids the upstream GLX platform path. The bridge supplies the
# portable platform sources needed by the Command Export backend.
set(MLN_WITH_CORE_ONLY ON CACHE BOOL "" FORCE)
set(MLN_WITH_COMMAND_EXPORT ON CACHE BOOL "" FORCE)
set(MLN_WITH_EGL OFF CACHE BOOL "" FORCE)
set(MLN_WITH_OPENGL OFF CACHE BOOL "" FORCE)
set(MLN_WITH_METAL OFF CACHE BOOL "" FORCE)
set(MLN_WITH_VULKAN OFF CACHE BOOL "" FORCE)
set(MLN_WITH_WEBGPU OFF CACHE BOOL "" FORCE)
set(MLN_WITH_GLFW OFF CACHE BOOL "" FORCE)
set(MLN_WITH_NODE OFF CACHE BOOL "" FORCE)
set(MLN_WITH_QT OFF CACHE BOOL "" FORCE)
set(MLN_USE_BUILTIN_ICU ON CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)

add_subdirectory(
    "${MAPLIBRE_NATIVE_SOURCE_DIR}"
    "${CMAKE_BINARY_DIR}/vendor/maplibre-native"
    EXCLUDE_FROM_ALL
)

find_package(CURL REQUIRED)
find_package(JPEG REQUIRED)
find_package(PNG REQUIRED)
find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)
pkg_search_module(WEBP libwebp REQUIRED)
pkg_search_module(LIBUV libuv REQUIRED)
pkg_search_module(ICUUC icu-uc)
pkg_search_module(ICUI18N icu-i18n)

set(_MLN "${MAPLIBRE_NATIVE_SOURCE_DIR}")
maplibre_fluttergpu_add_default_sources(mbgl-core "${_MLN}")
target_sources(
    mbgl-core
    PRIVATE
        ${_MLN}/platform/default/src/mbgl/util/thread.cpp
        ${_MLN}/platform/default/src/mbgl/util/thread_local.cpp
)

target_include_directories(
    mbgl-core
    PUBLIC ${_MLN}/platform/default/include
    PRIVATE
        ${CURL_INCLUDE_DIRS}
        ${JPEG_INCLUDE_DIRS}
        ${LIBUV_INCLUDE_DIRS}
        ${WEBP_INCLUDE_DIRS}
)

# Command Export selects the container implementation without publishing its
# option. The core and bridge must compile against the same container ABI.
target_compile_definitions(
    mbgl-core
    PUBLIC MLN_USE_UNORDERED_DENSE=$<BOOL:${MLN_USE_UNORDERED_DENSE}>
)

# GCC 12 emits false-positive restrict diagnostics while inlining std::string.
target_compile_options(
    mbgl-core
    PRIVATE $<$<COMPILE_LANG_AND_ID:CXX,GNU>:-Wno-error=restrict>
)

# Command Export constructors retain upstream names that shadow base members.
set_property(
    SOURCE
        ${_MLN}/src/mbgl/command_export/command_encoder.cpp
        ${_MLN}/src/mbgl/command_export/context.cpp
        ${_MLN}/src/mbgl/command_export/drawable.cpp
        ${_MLN}/src/mbgl/command_export/drawable_builder.cpp
        ${_MLN}/src/mbgl/command_export/draw_command.cpp
        ${_MLN}/src/mbgl/command_export/fill_extrusion_vertex_data.cpp
        ${_MLN}/src/mbgl/command_export/layer_group.cpp
        ${_MLN}/src/mbgl/command_export/renderer_backend.cpp
        ${_MLN}/src/mbgl/command_export/texture2d.cpp
        ${_MLN}/src/mbgl/command_export/tile_layer_group.cpp
        ${_MLN}/src/mbgl/command_export/uniform_buffer.cpp
        ${_MLN}/src/mbgl/command_export/upload_pass.cpp
        ${_MLN}/platform/default/src/mbgl/command_export/headless_backend.cpp
    TARGET_DIRECTORY mbgl-core
    APPEND PROPERTY COMPILE_OPTIONS
        $<$<COMPILE_LANG_AND_ID:CXX,GNU>:-Wno-error=shadow>
)

set_property(
    SOURCE ${_MLN}/platform/default/src/mbgl/command_export/headless_backend.cpp
    TARGET_DIRECTORY mbgl-core
    APPEND PROPERTY COMPILE_OPTIONS
        $<$<COMPILE_LANG_AND_ID:CXX,GNU>:-Wno-error=unused-parameter>
)

include(${_MLN}/vendor/nunicode.cmake)
include(${_MLN}/vendor/sqlite.cmake)

if(NOT ICUUC_FOUND OR ICUUC_VERSION VERSION_LESS 62.0 OR MLN_USE_BUILTIN_ICU)
    set(MLN_USE_BUILTIN_ICU TRUE)
    include(${_MLN}/vendor/icu.cmake)
    set_property(
        SOURCE ${_MLN}/platform/default/src/mbgl/i18n/number_format.cpp
        TARGET_DIRECTORY mbgl-core
        APPEND PROPERTY COMPILE_DEFINITIONS MBGL_USE_BUILTIN_ICU
    )
endif()

target_link_libraries(
    mbgl-core
    PRIVATE
        ${CURL_LIBRARIES}
        ${JPEG_LIBRARIES}
        ${LIBUV_LIBRARIES}
        ${WEBP_LIBRARIES}
        $<$<NOT:$<BOOL:${MLN_USE_BUILTIN_ICU}>>:${ICUUC_LIBRARIES}>
        $<$<NOT:$<BOOL:${MLN_USE_BUILTIN_ICU}>>:${ICUI18N_LIBRARIES}>
        $<$<BOOL:${MLN_USE_BUILTIN_ICU}>:mbgl-vendor-icu>
        PNG::PNG
        Threads::Threads
        mbgl-vendor-nunicode
        mbgl-vendor-sqlite
)

add_library(
    maplibre_bridge
    SHARED
        ${MAPLIBRE_FLUTTERGPU_BRIDGE_SOURCES}
)
target_compile_features(maplibre_bridge PRIVATE cxx_std_20)
target_compile_options(maplibre_bridge PRIVATE -fno-rtti)
target_compile_definitions(
    maplibre_bridge
    PRIVATE
        MLN_RENDER_BACKEND_COMMAND_EXPORT=1
        MLN_TEXT_SHAPING_HARFBUZZ=1
        MLN_USE_UNORDERED_DENSE=$<BOOL:${MLN_USE_UNORDERED_DENSE}>
        RAPIDJSON_HAS_STDSTRING=1
)
target_include_directories(
    maplibre_bridge
    PRIVATE
        ${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/src
        ${_MLN}/src
)
target_link_libraries(maplibre_bridge PRIVATE mbgl-core)
target_link_options(
    maplibre_bridge
    PRIVATE
        -Wl,--no-undefined
        -Wl,--exclude-libs,ALL
)
set_target_properties(
    maplibre_bridge
    PROPERTIES
        CXX_EXTENSIONS OFF
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN YES
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
        OUTPUT_NAME maplibre_bridge
)
