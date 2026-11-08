#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -gt 1 ]]; then
    echo "Usage: $0 [full|ios]" >&2
    exit 64
fi

MODE="${1:-full}"
case "${MODE}" in
    full)
        EXPECTED_LIBRARY_COUNT=3
        ;;
    ios)
        EXPECTED_LIBRARY_COUNT=2
        ;;
    *)
        echo "Usage: $0 [full|ios]" >&2
        exit 64
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FRAMEWORK="${PROJECT_ROOT}/darwin/maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework"

INFO_PLIST="${FRAMEWORK}/Info.plist"

# shellcheck source=../../native/scripts/packaging/darwin_common.sh
source "${PROJECT_ROOT}/native/scripts/packaging/darwin_common.sh"

test -f "${INFO_PLIST}"
plutil -lint "${INFO_PLIST}"

PLIST_JSON="$(plutil -convert json -o - "${INFO_PLIST}")"
ruby -rjson -e '
  mode = ARGV.fetch(0)
  data = JSON.parse(STDIN.read)
  flat_binary = "MapLibreBridge.framework/MapLibreBridge"
  expected = {
    "ios-arm64" => ["ios", nil, ["arm64"], flat_binary],
    "ios-arm64_x86_64-simulator" =>
      ["ios", "simulator", ["arm64", "x86_64"], flat_binary]
  }
  if mode == "full"
    expected["macos-arm64_x86_64"] = [
      "macos", nil, ["arm64", "x86_64"],
      "MapLibreBridge.framework/Versions/A/MapLibreBridge"
    ]
  end
  libraries = data.fetch("AvailableLibraries")
  abort "unexpected XCFramework library count" unless libraries.length == expected.length
  actual = libraries.to_h { |library|
    identifier = library.fetch("LibraryIdentifier")
    abort "unexpected XCFramework identifier: #{identifier}" unless expected.key?(identifier)
    abort "unexpected library path" unless library.fetch("LibraryPath") == "MapLibreBridge.framework"
    abort "#{identifier} must ship a framework, not loose headers" if library.key?("HeadersPath")
    values = [
      library.fetch("SupportedPlatform"),
      library["SupportedPlatformVariant"],
      library.fetch("SupportedArchitectures").sort,
      library.fetch("BinaryPath")
    ]
    [identifier, values]
  }
  abort "unexpected XCFramework metadata" unless actual == expected
' "${MODE}" <<<"${PLIST_JSON}"

library_count="$(
    find "${FRAMEWORK}" -mindepth 2 -maxdepth 2 -name MapLibreBridge.framework -type d |
        wc -l | tr -d ' '
)"
if [[ "${library_count}" != "${EXPECTED_LIBRARY_COUNT}" ]]; then
    echo "error: XCFramework contains ${library_count} frameworks instead of ${EXPECTED_LIBRARY_COUNT}" >&2
    exit 1
fi
if find "${FRAMEWORK}" -name '*.a' -print -quit | grep -q .; then
    echo "error: XCFramework still contains a static archive" >&2
    exit 1
fi

verify_bridge_framework iphoneos \
    "${FRAMEWORK}/ios-arm64/MapLibreBridge.framework" arm64
verify_bridge_framework iphonesimulator \
    "${FRAMEWORK}/ios-arm64_x86_64-simulator/MapLibreBridge.framework" arm64 x86_64
if [[ "${MODE}" == full ]]; then
    verify_bridge_framework macosx \
        "${FRAMEWORK}/macos-arm64_x86_64/MapLibreBridge.framework" arm64 x86_64
fi

du -sh "${FRAMEWORK}"
