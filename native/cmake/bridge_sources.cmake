# Shared bridge translation units compiled by every native platform target.
if(NOT DEFINED MAPLIBRE_FLUTTERGPU_NATIVE_ROOT)
    message(FATAL_ERROR "MAPLIBRE_FLUTTERGPU_NATIVE_ROOT is required")
endif()

set(
    MAPLIBRE_FLUTTERGPU_BRIDGE_SOURCES
    ${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/src/maplibre_bridge.cpp
    ${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/src/bridge_owner_thread.cpp
    ${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/src/bridge_merge.cpp
    ${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/src/bridge_features.cpp
    ${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/src/bridge_labels.cpp
    ${MAPLIBRE_FLUTTERGPU_NATIVE_ROOT}/src/bridge_style.cpp
)
