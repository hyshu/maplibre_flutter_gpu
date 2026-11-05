# MapLibre Native's OpenGL and Metal backend modules publish this definition
# to mbgl-core, but the Command Export module currently does not. Keep container
# aliases ABI-compatible between mbgl-core and the standalone FFI bridge.
add_compile_definitions(
    MLN_USE_UNORDERED_DENSE=$<BOOL:${MLN_USE_UNORDERED_DENSE}>
)

# CMake includes this file after every project() call, including the vendored
# sub-projects. Register the deferred rename once, in the directory that creates
# mbgl-core, so the call cannot run before that target exists.
if(APPLE AND CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
    include(${CMAKE_CURRENT_LIST_DIR}/darwin_objc_class_names.cmake)
    cmake_language(DEFER CALL maplibre_apply_darwin_objc_class_renames mbgl-core)
endif()
