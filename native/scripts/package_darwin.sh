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

IOS_PACKAGE_ROOT="${PROJECT_ROOT}/build-ios-fluttergpu-package"
MACOS_PACKAGE_ROOT="${PROJECT_ROOT}/build-macos-fluttergpu-package"
HEADERS="${DARWIN_PACKAGE_ROOT}/Headers"
OUTPUT="${DARWIN_PACKAGE_ROOT}/Frameworks/MapLibreBridge.xcframework"

verify_reusable_ios_library() {
    local library="$1"
    shift
    if [[ ! -f "${library}" ]]; then
        echo "error: existing iOS slice is missing: ${library}" >&2
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
else
    existing_device_archive="${OUTPUT}/ios-arm64/libMapLibreBridge.a"
    existing_simulator_archive="${OUTPUT}/ios-arm64_x86_64-simulator/libMapLibreBridge.a"
    verify_reusable_ios_library "${existing_device_archive}" arm64
    verify_reusable_ios_library "${existing_simulator_archive}" arm64 x86_64

    ios_staging_root="$(mktemp -d -t maplibre-darwin-ios)"
    trap 'rm -rf "${ios_staging_root}"' EXIT
    device_archive="${ios_staging_root}/iphoneos/libMapLibreBridge.a"
    simulator_archive="${ios_staging_root}/iphonesimulator/libMapLibreBridge.a"
    mkdir -p \
        "$(dirname "${device_archive}")" \
        "$(dirname "${simulator_archive}")"
    cp "${existing_device_archive}" "${device_archive}"
    cp "${existing_simulator_archive}" "${simulator_archive}"
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
    -headers "${HEADERS}"
    -library "${simulator_archive}"
    -headers "${HEADERS}"
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

echo "Built ${OUTPUT}"
