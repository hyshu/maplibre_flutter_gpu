#!/usr/bin/env bash

# Builds the vendored XCFramework consumed by SwiftPM and CocoaPods.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=packaging/darwin_common.sh
source "${SCRIPT_DIR}/packaging/darwin_common.sh"

require_tools xcodebuild
require_darwin_sources

"${SCRIPT_DIR}/build_ios.sh" all
"${SCRIPT_DIR}/build_macos.sh" universal

IOS_PACKAGE_ROOT="${PROJECT_ROOT}/build-ios-fluttergpu-package"
MACOS_PACKAGE_ROOT="${PROJECT_ROOT}/build-macos-fluttergpu-package"
HEADERS="${DARWIN_PACKAGE_ROOT}/Headers"
OUTPUT="${DARWIN_PACKAGE_ROOT}/Frameworks/MapLibreBridge.xcframework"

device_archive="${IOS_PACKAGE_ROOT}/iphoneos/libMapLibreBridge.a"
simulator_archive="${IOS_PACKAGE_ROOT}/iphonesimulator/libMapLibreBridge.a"
macos_archive="${MACOS_PACKAGE_ROOT}/macosx/libMapLibreBridge.a"
for archive in "${device_archive}" "${simulator_archive}" "${macos_archive}"; do
    if [[ ! -f "${archive}" ]]; then
        echo "error: expected packaged archive is missing: ${archive}" >&2
        exit 1
    fi
done

mkdir -p "$(dirname "${OUTPUT}")"
rm -rf "${OUTPUT}"
xcodebuild -create-xcframework \
    -library "${device_archive}" \
    -headers "${HEADERS}" \
    -library "${simulator_archive}" \
    -headers "${HEADERS}" \
    -library "${macos_archive}" \
    -headers "${HEADERS}" \
    -output "${OUTPUT}"

if [[ ! -f "${OUTPUT}/Info.plist" ]]; then
    echo "error: XCFramework creation did not produce Info.plist" >&2
    exit 1
fi

slice_count="$(find "${OUTPUT}" -name libMapLibreBridge.a -type f | wc -l | tr -d ' ')"
if [[ "${slice_count}" != 3 ]]; then
    echo "error: XCFramework contains ${slice_count} library slices instead of 3" >&2
    exit 1
fi

echo "Built ${OUTPUT}"
