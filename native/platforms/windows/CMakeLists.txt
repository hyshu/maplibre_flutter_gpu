cmake_minimum_required(VERSION 3.25 FATAL_ERROR)

project(maplibre_fluttergpu_bridge_windows LANGUAGES C CXX)

if(NOT WIN32)
    message(FATAL_ERROR "native/platforms/windows builds the Windows bridge only")
endif()

set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

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
set(MLN_USE_BUILTIN_ICU OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)

add_subdirectory(
    "${MAPLIBRE_NATIVE_SOURCE_DIR}"
    "${CMAKE_BINARY_DIR}/vendor/maplibre-native"
    EXCLUDE_FROM_ALL
)

find_package(CURL CONFIG REQUIRED)
find_package(ICU REQUIRED COMPONENTS data i18n uc)
find_package(JPEG REQUIRED)
find_package(PNG REQUIRED)
find_package(WebP CONFIG REQUIRED)
find_path(LIBUV_INCLUDE_DIR NAMES uv.h REQUIRED)
find_library(LIBUV_LIBRARY NAMES uv_a uv libuv REQUIRED)

set(_MLN "${MAPLIBRE_NATIVE_SOURCE_DIR}")
maplibre_fluttergpu_add_default_sources(mbgl-core "${_MLN}")
target_sources(
    mbgl-core
    PRIVATE
        ${_MLN}/platform/windows/src/thread.cpp
        ${_MLN}/platform/windows/src/thread_local.cpp
)

target_include_directories(
    mbgl-core
    PUBLIC ${_MLN}/platform/default/include
    PRIVATE
        ${_MLN}/platform/windows/include
        ${JPEG_INCLUDE_DIRS}
        ${LIBUV_INCLUDE_DIR}
)
target_compile_definitions(
    mbgl-core
    PUBLIC MLN_USE_UNORDERED_DENSE=$<BOOL:${MLN_USE_UNORDERED_DENSE}>
    PRIVATE
        CURL_STATICLIB
        U_STATIC_IMPLEMENTATION
        NOMINMAX
        USE_STD_FILESYSTEM
        WIN32
        GHC_WIN_DISABLE_WSTRING_STORAGE_TYPE
)

include(${_MLN}/vendor/nunicode.cmake)
include(${_MLN}/vendor/sqlite.cmake)

target_link_libraries(
    mbgl-core
    PRIVATE
        CURL::libcurl
        ICU::data
        ICU::i18n
        ICU::uc
        JPEG::JPEG
        PNG::PNG
        WebP::webp
        mbgl-vendor-nunicode
        mbgl-vendor-sqlite
        ${LIBUV_LIBRARY}
        dbghelp
        psapi
        userenv
)

add_library(
    maplibre_bridge
    SHARED
        ${MAPLIBRE_FLUTTERGPU_BRIDGE_SOURCES}
)
target_compile_features(maplibre_bridge PRIVATE cxx_std_20)
target_compile_options(maplibre_bridge PRIVATE /GR-)
target_compile_definitions(
    maplibre_bridge
    PRIVATE
        _USE_MATH_DEFINES
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
set_target_properties(
    maplibre_bridge
    PROPERTIES
        CXX_EXTENSIONS OFF
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out"
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out"
        ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out"
        OUTPUT_NAME maplibre_bridge
)
