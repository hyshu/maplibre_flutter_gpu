#!/usr/bin/env bash

# Builds monolithic static bridge archives for iOS device and simulator slices.
#
# Run build_ios.sh with all, device, or sim. The default is all.
#
# MAPLIBRE_IOS_SIM_ARCHS may contain a space-separated simulator architecture
# list. The default includes Apple Silicon and Intel hosts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=packaging/darwin_common.sh
source "${SCRIPT_DIR}/packaging/darwin_common.sh"

MODE="${1:-all}"
case "${MODE}" in
    all|device|sim)
        ;;
    *)
        echo "Usage: $0 [all|device|sim]" >&2
        exit 64
        ;;
esac

require_tools cmake xcodebuild xcrun nm
require_darwin_sources

PACKAGE_ROOT="${PROJECT_ROOT}/build-ios-fluttergpu-package"
SYSROOT=""
CLANG=""
LIBTOOL=""
LIPO="$(xcrun --find lipo)"

build_architecture() {
    local mode="$1"
    local architecture="$2"
    local sdk target build_dir configuration_dir

    case "${mode}" in
        device)
            sdk=iphoneos
            target="${architecture}-apple-ios${DEPLOYMENT_TARGET}"
            ;;
        sim)
            sdk=iphonesimulator
            target="${architecture}-apple-ios${DEPLOYMENT_TARGET}-simulator"
            ;;
    esac

    build_dir="${PROJECT_ROOT}/build-ios-fluttergpu-${mode}-${architecture}"
    configuration_dir="${build_dir}/Release-${sdk}"
    SYSROOT="$(xcrun --sdk "${sdk}" --show-sdk-path)"
    CLANG="$(xcrun --sdk "${sdk}" --find clang++)"
    LIBTOOL="$(xcrun --sdk "${sdk}" --find libtool)"

    echo "Configuring MapLibre Native for iOS ${mode} ${architecture}..." >&2
    cmake \
        -S "${MAPLIBRE_SRC}" \
        -B "${build_dir}" \
        -G Xcode \
        -DCMAKE_TOOLCHAIN_FILE="${MAPLIBRE_SRC}/platform/ios/ios.toolchain.cmake" \
        -DCMAKE_PROJECT_INCLUDE="${NATIVE_ROOT}/cmake/command_export_compile_definitions.cmake" \
        -DCMAKE_OSX_SYSROOT="${sdk}" \
        -DCMAKE_OSX_ARCHITECTURES="${architecture}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
        -DMLT_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
        -DMLN_WITH_COMMAND_EXPORT=ON \
        -DMLN_WITH_WERROR=OFF \
        -DMLN_WITH_GLFW=OFF \
        -DMLN_USE_UNORDERED_DENSE=ON \
        -DBUILD_TESTING=OFF \
        -DDEVELOPMENT_TEAM_ID= >&2

    echo "Building MapLibre Native for iOS ${mode} ${architecture}..." >&2
    cmake --build "${build_dir}" \
        --config Release \
        --target mbgl-core \
        --parallel \
        -- \
        -sdk "${sdk}" \
        -arch "${architecture}" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO >&2

    local core_archives=(
        "${configuration_dir}/libmbgl-core.a"
        "${configuration_dir}/libmbgl-freetype.a"
        "${configuration_dir}/libmbgl-harfbuzz.a"
        "${configuration_dir}/libmbgl-vendor-csscolorparser.a"
        "${configuration_dir}/libmbgl-vendor-icu.a"
        "${configuration_dir}/libmbgl-vendor-parsedate.a"
        "${build_dir}/vendor/maplibre-tile-spec/cpp/Release-${sdk}/libmlt-cpp.a"
        "${build_dir}/vendor/maplibre-tile-spec/cpp/Release-${sdk}/libfastpfor-lib.a"
    )

    echo "Building the Flutter GPU bridge for ${target}..." >&2
    compile_bridge_objects "${sdk}" "${target}" "${build_dir}"

    local output="${build_dir}/packaging/libMapLibreBridge.a"
    create_monolithic_archive "${output}" "${core_archives[@]}"
    echo "${output}"
}

combine_architectures() {
    local output="$1"
    shift

    mkdir -p "$(dirname "${output}")"
    rm -f "${output}"
    if [[ "$#" -eq 1 ]]; then
        install -m 0644 "$1" "${output}"
    else
        "${LIPO}" -create "$@" -output "${output}"
    fi
    verify_bridge_archive "${output}"
    echo "Built ${output} with $("${LIPO}" -archs "${output}")"
}

if [[ "${MODE}" == all || "${MODE}" == device ]]; then
    device_archive="$(build_architecture device arm64)"
    combine_architectures \
        "${PACKAGE_ROOT}/iphoneos/libMapLibreBridge.a" \
        "${device_archive}"
fi

if [[ "${MODE}" == all || "${MODE}" == sim ]]; then
    read -r -a simulator_architectures \
        <<<"${MAPLIBRE_IOS_SIM_ARCHS:-arm64 x86_64}"
    if [[ "${#simulator_architectures[@]}" -eq 0 ]]; then
        echo "error: MAPLIBRE_IOS_SIM_ARCHS must contain an architecture" >&2
        exit 64
    fi

    simulator_archives=()
    for architecture in "${simulator_architectures[@]}"; do
        case "${architecture}" in
            arm64|x86_64)
                ;;
            *)
                echo "error: unsupported iOS simulator architecture: ${architecture}" >&2
                exit 64
                ;;
        esac
        simulator_archives+=("$(build_architecture sim "${architecture}")")
    done
    combine_architectures \
        "${PACKAGE_ROOT}/iphonesimulator/libMapLibreBridge.a" \
        "${simulator_archives[@]}"
fi
