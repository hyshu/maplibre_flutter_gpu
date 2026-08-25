#!/usr/bin/env bash

# Builds the vendored XCFramework consumed by SwiftPM and CocoaPods.
#
# The ios mode creates an iOS-only staging artifact. The macos mode completes
# that artifact with the macOS slice. The default all mode builds every slice.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=packaging/darwin_common.sh
source "${SCRIPT_DIR}/packaging/darwin_common.sh"

require_tools xcodebuild xcrun
require_darwin_sources

MODE="${1:-all}"
case "${MODE}" in
    all|ios|macos)
        ;;
    *)
        echo "Usage: $0 [all|ios|macos]" >&2
        exit 64
        ;;
esac

verify_fill_extrusion_transport() {
    local bridge_source="${NATIVE_ROOT}/src/bridge_merge.cpp"
    local draw_flags="${PROJECT_ROOT}/lib/src/frame/draw_flags.dart"
    local pipeline_key="${PROJECT_ROOT}/lib/src/frame/pipeline_key.dart"
    local shader_manifest="${PROJECT_ROOT}/shaders/MapShaders.shaderbundle.json"
    local packed_color_shader="${PROJECT_ROOT}/shaders/fill_extrusion_dd_packed_color.vert"

    local forbidden_markers=(
        'kFillExtrusionPackedColorGpuStride'
        'kFillExtrusionPackedColorGpuReadyFlag'
        '[GpuNativeFE]'
        'fillExtrusionPackedColorGpuReady'
        'fillExtrusionPackedColorDataDriven'
        'FillExtrusionDDPackedColorVertex'
    )
    local marker
    for marker in "${forbidden_markers[@]}"; do
        if grep -Fq "${marker}" \
            "${bridge_source}" \
            "${draw_flags}" \
            "${pipeline_key}" \
            "${shader_manifest}"; then
            echo "error: deprecated 36-byte fill-extrusion transport is still present: ${marker}" >&2
            echo "Restore the 44-byte packed fill-extrusion transport before packaging." >&2
            exit 1
        fi
    done

    if [[ -e "${packed_color_shader}" ]]; then
        echo "error: deprecated packed-color fill-extrusion shader is still present: ${packed_color_shader}" >&2
        exit 1
    fi
}

verify_fill_extrusion_transport

IOS_PACKAGE_ROOT="${PROJECT_ROOT}/build-ios-fluttergpu-package"
MACOS_PACKAGE_ROOT="${PROJECT_ROOT}/build-macos-fluttergpu-package"
HEADERS="${DARWIN_PACKAGE_ROOT}/Headers"
OUTPUT="${DARWIN_PACKAGE_ROOT}/Frameworks/MapLibreBridge.xcframework"

verify_reusable_ios_slice() {
    local library="$1"
    local headers="$2"
    shift 2
    if [[ ! -f "${library}" ]]; then
        echo "error: existing iOS slice is missing: ${library}" >&2
        exit 1
    fi
    if [[ ! -f "${headers}/MapLibreBridge.h" || ! -f "${headers}/module.modulemap" ]]; then
        echo "error: existing iOS headers are incomplete: ${headers}" >&2
        exit 1
    fi

    local architectures
    architectures="$(xcrun lipo -archs "${library}")"
    if [[ "$(wc -w <<<"${architectures}" | tr -d ' ')" -ne "$#" ]]; then
        echo "error: unexpected architectures in ${library}: ${architectures}" >&2
        exit 1
    fi

    local expected
    for expected in "$@"; do
        if ! grep -qw "${expected}" <<<"${architectures}"; then
            echo "error: ${library} is missing ${expected}" >&2
            exit 1
        fi
    done
}

if [[ "${MODE}" == all || "${MODE}" == ios ]]; then
    "${SCRIPT_DIR}/build_ios.sh" all
    device_archive="${IOS_PACKAGE_ROOT}/iphoneos/libMapLibreBridge.a"
    simulator_archive="${IOS_PACKAGE_ROOT}/iphonesimulator/libMapLibreBridge.a"
    device_headers="${HEADERS}"
    simulator_headers="${HEADERS}"
else
    existing_device_archive="${OUTPUT}/ios-arm64/libMapLibreBridge.a"
    existing_simulator_archive="${OUTPUT}/ios-arm64_x86_64-simulator/libMapLibreBridge.a"
    existing_device_headers="${OUTPUT}/ios-arm64/Headers"
    existing_simulator_headers="${OUTPUT}/ios-arm64_x86_64-simulator/Headers"
    verify_reusable_ios_slice \
        "${existing_device_archive}" \
        "${existing_device_headers}" \
        arm64
    verify_reusable_ios_slice \
        "${existing_simulator_archive}" \
        "${existing_simulator_headers}" \
        arm64 x86_64

    ios_staging_root="$(mktemp -d -t maplibre-darwin-ios)"
    trap 'rm -rf "${ios_staging_root}"' EXIT
    device_archive="${ios_staging_root}/iphoneos/libMapLibreBridge.a"
    simulator_archive="${ios_staging_root}/iphonesimulator/libMapLibreBridge.a"
    device_headers="${ios_staging_root}/iphoneos/Headers"
    simulator_headers="${ios_staging_root}/iphonesimulator/Headers"
    mkdir -p \
        "$(dirname "${device_archive}")" \
        "$(dirname "${simulator_archive}")"
    cp "${existing_device_archive}" "${device_archive}"
    cp "${existing_simulator_archive}" "${simulator_archive}"
    cp -R "${existing_device_headers}" "${device_headers}"
    cp -R "${existing_simulator_headers}" "${simulator_headers}"
fi

if [[ "${MODE}" == all || "${MODE}" == macos ]]; then
    "${SCRIPT_DIR}/build_macos.sh" universal
fi

macos_archive="${MACOS_PACKAGE_ROOT}/macosx/libMapLibreBridge.a"
archives=("${device_archive}" "${simulator_archive}")
if [[ "${MODE}" != ios ]]; then
    archives+=("${macos_archive}")
fi
for archive in "${archives[@]}"; do
    if [[ ! -f "${archive}" ]]; then
        echo "error: expected packaged archive is missing: ${archive}" >&2
        exit 1
    fi
done

mkdir -p "$(dirname "${OUTPUT}")"
rm -rf "${OUTPUT}"
xcframework_args=(
    -create-xcframework
    -library "${device_archive}"
    -headers "${device_headers}"
    -library "${simulator_archive}"
    -headers "${simulator_headers}"
)
expected_slice_count=2
if [[ "${MODE}" != ios ]]; then
    xcframework_args+=(
        -library "${macos_archive}"
        -headers "${HEADERS}"
    )
    expected_slice_count=3
fi
xcodebuild "${xcframework_args[@]}" -output "${OUTPUT}"

if [[ ! -f "${OUTPUT}/Info.plist" ]]; then
    echo "error: XCFramework creation did not produce Info.plist" >&2
    exit 1
fi

slice_count="$(find "${OUTPUT}" -name libMapLibreBridge.a -type f | wc -l | tr -d ' ')"
if [[ "${slice_count}" != "${expected_slice_count}" ]]; then
    echo "error: XCFramework contains ${slice_count} library slices instead of ${expected_slice_count}" >&2
    exit 1
fi

# The binary target stays at one local path. Touching the package manifest after
# replacing the XCFramework forces Xcode/SwiftPM to reevaluate that local package
# instead of reusing a previously resolved binary artifact.
touch "${DARWIN_PACKAGE_ROOT}/Package.swift"

echo "Built ${OUTPUT}"