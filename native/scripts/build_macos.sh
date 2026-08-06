#!/usr/bin/env bash

# Builds a monolithic static bridge archive for macOS.
#
# Run build_macos.sh with universal, arm64, or x86_64.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=packaging/darwin_common.sh
source "${SCRIPT_DIR}/packaging/darwin_common.sh"

MODE="${1:-universal}"
case "${MODE}" in
    universal)
        ARCHITECTURES=(arm64 x86_64)
        ;;
    arm64|x86_64)
        ARCHITECTURES=("${MODE}")
        ;;
    *)
        echo "Usage: $0 [universal|arm64|x86_64]" >&2
        exit 64
        ;;
esac

require_tools bazel cmake ninja xcrun nm
require_darwin_sources

SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"
CLANG="$(xcrun --sdk macosx --find clang++)"
LIBTOOL="$(xcrun --sdk macosx --find libtool)"
LIPO="$(xcrun --sdk macosx --find lipo)"
PACKAGE_ROOT="${PROJECT_ROOT}/build-macos-fluttergpu-package"

build_architecture() {
    local architecture="$1"
    local build_dir="${PROJECT_ROOT}/build-macos-fluttergpu-${architecture}"

    echo "Configuring MapLibre Native for macOS ${architecture}..." >&2
    cmake \
        -S "${MAPLIBRE_SRC}" \
        -B "${build_dir}" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PROJECT_INCLUDE="${NATIVE_ROOT}/cmake/command_export_compile_definitions.cmake" \
        -DCMAKE_OSX_ARCHITECTURES="${architecture}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
        -DMLN_WITH_CORE_ONLY=OFF \
        -DMLN_WITH_COMMAND_EXPORT=ON \
        -DMLN_WITH_OPENGL=OFF \
        -DMLN_WITH_METAL=OFF \
        -DMLN_WITH_VULKAN=OFF \
        -DMLN_WITH_WEBGPU=OFF \
        -DMLN_WITH_GLFW=OFF \
        -DMLN_WITH_NODE=OFF \
        -DMLN_DARWIN_USE_LIBUV=OFF \
        -DMLN_WITH_WERROR=OFF \
        -DMLN_USE_UNORDERED_DENSE=ON \
        -DBUILD_TESTING=OFF >&2

    echo "Building MapLibre Native for macOS ${architecture}..." >&2
    cmake --build "${build_dir}" --target mbgl-core --parallel >&2

    local core_archives=(
        "${build_dir}/libmbgl-core.a"
        "${build_dir}/libmbgl-freetype.a"
        "${build_dir}/libmbgl-harfbuzz.a"
        "${build_dir}/libmbgl-vendor-csscolorparser.a"
        "${build_dir}/libmbgl-vendor-icu.a"
        "${build_dir}/libmbgl-vendor-parsedate.a"
        "${build_dir}/vendor/maplibre-tile-spec/cpp/libmlt-cpp.a"
        "${build_dir}/vendor/maplibre-tile-spec/cpp/libfastpfor-lib.a"
    )

    echo "Building the Flutter GPU bridge for macOS ${architecture}..." >&2
    compile_bridge_objects \
        macosx \
        "${architecture}-apple-macos${DEPLOYMENT_TARGET}" \
        "${build_dir}"

    local output="${build_dir}/packaging/libMapLibreBridge.a"
    create_monolithic_archive "${output}" "${core_archives[@]}"
    echo "${output}"
}

architecture_archives=()
for architecture in "${ARCHITECTURES[@]}"; do
    architecture_archives+=("$(build_architecture "${architecture}")")
done

output="${PACKAGE_ROOT}/macosx/libMapLibreBridge.a"
mkdir -p "$(dirname "${output}")"
rm -f "${output}"
if [[ "${#architecture_archives[@]}" -eq 1 ]]; then
    install -m 0644 "${architecture_archives[0]}" "${output}"
else
    "${LIPO}" -create "${architecture_archives[@]}" -output "${output}"
fi
verify_bridge_archive "${output}"

echo "Built ${output} with $("${LIPO}" -archs "${output}")"
