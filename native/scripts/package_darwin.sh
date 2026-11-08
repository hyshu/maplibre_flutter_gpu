#!/usr/bin/env bash

# Builds the vendored XCFramework consumed by SwiftPM and CocoaPods. Each
# slice is a dynamic MapLibreBridge.framework linked from the monolithic static
# bridge archive that build_ios.sh or build_macos.sh produces.
#
# The ios mode creates an iOS-only staging artifact. The macos mode completes
# that artifact with the macOS slice. The default all mode builds every slice.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=packaging/darwin_common.sh
source "${SCRIPT_DIR}/packaging/darwin_common.sh"

require_tools xcodebuild xcrun nm plutil ruby
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
            "${BRIDGE_SOURCE_PATHS[@]}" \
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
OUTPUT="${DARWIN_PACKAGE_ROOT}/Frameworks/MapLibreBridge.xcframework"
FRAMEWORK_SLICE="${BRIDGE_FRAMEWORK_NAME}.framework"

staging_root="$(mktemp -d -t maplibre-darwin-frameworks)"
trap 'rm -rf "${staging_root}"' EXIT
device_framework="${staging_root}/iphoneos/${FRAMEWORK_SLICE}"
simulator_framework="${staging_root}/iphonesimulator/${FRAMEWORK_SLICE}"
macos_framework="${staging_root}/macosx/${FRAMEWORK_SLICE}"

# The macos mode completes an iOS-only artifact from an earlier run. Its iOS
# slices are copied unchanged after a structural check. They need not export
# every symbol in the current source tree, which only a fresh iOS build can do.
reuse_ios_framework() {
    local platform="$1"
    local slice="$2"
    local destination="$3"
    shift 3
    local existing="${OUTPUT}/${slice}/${FRAMEWORK_SLICE}"
    if [[ ! -d "${existing}" ]]; then
        echo "error: existing iOS slice is missing: ${existing}" >&2
        exit 1
    fi
    verify_bridge_framework_layout "${platform}" "${existing}" "$@"
    mkdir -p "$(dirname "${destination}")"
    cp -R "${existing}" "${destination}"
}

if [[ "${MODE}" == all || "${MODE}" == ios ]]; then
    "${SCRIPT_DIR}/build_ios.sh" all
    link_bridge_framework iphoneos \
        "${IOS_PACKAGE_ROOT}/iphoneos/libMapLibreBridge.a" \
        "${device_framework}"
    link_bridge_framework iphonesimulator \
        "${IOS_PACKAGE_ROOT}/iphonesimulator/libMapLibreBridge.a" \
        "${simulator_framework}"
else
    reuse_ios_framework iphoneos ios-arm64 "${device_framework}" arm64
    reuse_ios_framework iphonesimulator ios-arm64_x86_64-simulator \
        "${simulator_framework}" arm64 x86_64
fi

if [[ "${MODE}" == all || "${MODE}" == macos ]]; then
    "${SCRIPT_DIR}/build_macos.sh" universal
    link_bridge_framework macosx \
        "${MACOS_PACKAGE_ROOT}/macosx/libMapLibreBridge.a" \
        "${macos_framework}"
fi

mkdir -p "$(dirname "${OUTPUT}")"
rm -rf "${OUTPUT}"
xcframework_args=(
    -create-xcframework
    -framework "${device_framework}"
    -framework "${simulator_framework}"
)
expected_slice_count=2
if [[ "${MODE}" != ios ]]; then
    xcframework_args+=(-framework "${macos_framework}")
    expected_slice_count=3
fi
xcodebuild "${xcframework_args[@]}" -output "${OUTPUT}"

if [[ ! -f "${OUTPUT}/Info.plist" ]]; then
    echo "error: XCFramework creation did not produce Info.plist" >&2
    exit 1
fi

slice_count="$(
    find "${OUTPUT}" -mindepth 2 -maxdepth 2 -name "${FRAMEWORK_SLICE}" -type d |
        wc -l | tr -d ' '
)"
if [[ "${slice_count}" != "${expected_slice_count}" ]]; then
    echo "error: XCFramework contains ${slice_count} framework slices instead of ${expected_slice_count}" >&2
    exit 1
fi

# The binary target stays at one local path. Touching the package manifest after
# replacing the XCFramework forces Xcode/SwiftPM to reevaluate that local package
# instead of reusing a previously resolved binary artifact.
touch "${DARWIN_PACKAGE_ROOT}/Package.swift"

echo "Built ${OUTPUT}"
