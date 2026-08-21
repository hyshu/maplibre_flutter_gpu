#!/usr/bin/env bash

# Shared build helpers for the vendored Darwin XCFramework.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "error: darwin_common.sh must be sourced" >&2
    exit 64
fi

PACKAGING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${PACKAGING_DIR}/.." && pwd)"
NATIVE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${NATIVE_ROOT}/.." && pwd)"
MAPLIBRE_SRC="${PROJECT_ROOT}/vendor/maplibre-native"
DARWIN_PACKAGE_ROOT="${PROJECT_ROOT}/darwin/maplibre_flutter_gpu"
ANCHOR_SOURCE="${DARWIN_PACKAGE_ROOT}/Packaging/maplibre_bridge_anchor.cpp"
DEPLOYMENT_TARGET="${MAPLIBRE_DARWIN_DEPLOYMENT_TARGET:-14.3}"

BRIDGE_SOURCE_PATHS=(
    "${NATIVE_ROOT}/src/maplibre_bridge.cpp"
    "${NATIVE_ROOT}/src/bridge_owner_thread.cpp"
    "${NATIVE_ROOT}/src/bridge_merge.cpp"
    "${NATIVE_ROOT}/src/bridge_features.cpp"
    "${NATIVE_ROOT}/src/bridge_labels.cpp"
    "${NATIVE_ROOT}/src/bridge_style.cpp"
    "${ANCHOR_SOURCE}"
)

BRIDGE_INCLUDE_ARGS=(
    -I"${MAPLIBRE_SRC}/src"
    -I"${MAPLIBRE_SRC}/include"
    -I"${MAPLIBRE_SRC}/platform/default/include"
    -I"${MAPLIBRE_SRC}/platform/darwin/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/variant/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/geometry.hpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/geojson.hpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/jni.hpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/shelf-pack-cpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/geojson-vt-cpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/cheap-ruler-cpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/pixelmatch-cpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/expected-lite/include"
    -isystem "${MAPLIBRE_SRC}/vendor/rapidjson/include"
    -isystem "${MAPLIBRE_SRC}/vendor/boost/include"
    -isystem "${MAPLIBRE_SRC}/vendor/unordered_dense/include"
    -isystem "${MAPLIBRE_SRC}/vendor/eternal/include"
    -isystem "${MAPLIBRE_SRC}/vendor/nunicode/include"
    -isystem "${MAPLIBRE_SRC}/vendor/sqlite/include"
    -isystem "${MAPLIBRE_SRC}/vendor/protozero/include"
    -isystem "${MAPLIBRE_SRC}/vendor/vector-tile/include"
    -isystem "${MAPLIBRE_SRC}/vendor/wagyu/include"
    -isystem "${MAPLIBRE_SRC}/vendor/earcut.hpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/kdbush.hpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/polylabel/include"
    -isystem "${MAPLIBRE_SRC}/vendor/supercluster/include"
    -isystem "${MAPLIBRE_SRC}/vendor/unique_resource"
    -isystem "${MAPLIBRE_SRC}/vendor/freetype/include"
    -isystem "${MAPLIBRE_SRC}/vendor/harfbuzz/src"
    -isystem "${MAPLIBRE_SRC}/vendor/csscolorparser"
    -isystem "${MAPLIBRE_SRC}/vendor/parsedate"
    -isystem "${MAPLIBRE_SRC}/vendor/PMTiles/cpp"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-tile-spec/cpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/filesystem/include"
)

require_tools() {
    local tool
    for tool in "$@"; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            echo "error: ${tool} is required" >&2
            exit 1
        fi
    done
}

require_darwin_sources() {
    if [[ ! -f "${MAPLIBRE_SRC}/CMakeLists.txt" ]]; then
        echo "error: MapLibre Native submodule is missing" >&2
        echo "Run git submodule update --init --recursive." >&2
        exit 1
    fi
    if [[ ! -f "${ANCHOR_SOURCE}" ]]; then
        echo "error: force-link anchor is missing at ${ANCHOR_SOURCE}" >&2
        exit 1
    fi
}

compile_bridge_objects() {
    local sdk="$1"
    local target="$2"
    local build_dir="$3"
    local object_dir="${build_dir}/bridge-objects"

    rm -rf "${object_dir}"
    mkdir -p "${object_dir}"
    BRIDGE_OBJECTS=()

    local source
    for source in "${BRIDGE_SOURCE_PATHS[@]}"; do
        local object="${object_dir}/$(basename "${source%.*}").o"
        BRIDGE_OBJECTS+=("${object}")
        "${CLANG}" \
            -c \
            -std=c++20 \
            -O2 \
            -DNDEBUG \
            -target "${target}" \
            -isysroot "${SYSROOT}" \
            -fPIC \
            -fno-rtti \
            -fvisibility=hidden \
            -fvisibility-inlines-hidden \
            -DMLN_RENDER_BACKEND_COMMAND_EXPORT=1 \
            -DMLN_TEXT_SHAPING_HARFBUZZ=1 \
            -DMLN_USE_UNORDERED_DENSE=1 \
            -DRAPIDJSON_HAS_STDSTRING=1 \
            "${BRIDGE_INCLUDE_ARGS[@]}" \
            -o "${object}" \
            "${source}"
    done
}

create_monolithic_archive() {
    local output="$1"
    shift

    local archive
    for archive in "$@"; do
        if [[ ! -f "${archive}" ]]; then
            echo "error: expected native archive was not built: ${archive}" >&2
            exit 1
        fi
    done

    mkdir -p "$(dirname "${output}")"
    rm -f "${output}"
    "${LIBTOOL}" -static -o "${output}" "${BRIDGE_OBJECTS[@]}" "$@" >&2
    verify_bridge_archive "${output}"
}

verify_bridge_archive() {
    local archive="$1"
    local exported_symbols
    exported_symbols="$(nm -gU "${archive}" | awk '{print $NF}')"

    local expected_symbols
    expected_symbols="$({
        sed -En 's/^[[:space:]]*X\(([a-zA-Z0-9_]+)\).*/\1/p' "${ANCHOR_SOURCE}"
        echo maplibre_flutter_gpu_force_link
    } | sort -u)"

    local symbol
    while IFS= read -r symbol; do
        [[ -z "${symbol}" ]] && continue
        if ! grep -Fqx "_${symbol}" <<<"${exported_symbols}"; then
            echo "error: Darwin bridge does not export ${symbol}" >&2
            exit 1
        fi
    done <<<"${expected_symbols}"

    while IFS= read -r symbol; do
        [[ -z "${symbol}" ]] && continue
        if ! grep -Fqx "${symbol}" <<<"${expected_symbols}"; then
            echo "error: ${symbol} is exported but missing from the force-link anchor" >&2
            exit 1
        fi
    done < <(
        sed -En 's/^_((maplibre_)[a-zA-Z0-9_]+)$/\1/p' <<<"${exported_symbols}" | sort -u
    )
}
