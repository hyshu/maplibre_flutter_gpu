# MapLibre Native's OpenGL and Metal backend modules publish this definition
# to mbgl-core, but the Command Export module currently does not. Keep container
# aliases ABI-compatible between mbgl-core and the standalone FFI bridge.
add_compile_definitions(
    MLN_USE_UNORDERED_DENSE=$<BOOL:${MLN_USE_UNORDERED_DENSE}>
)
