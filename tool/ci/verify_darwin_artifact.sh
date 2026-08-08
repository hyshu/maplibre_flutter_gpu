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
DEVICE_LIBRARY="${FRAMEWORK}/ios-arm64/libMapLibreBridge.a"
SIMULATOR_LIBRARY="${FRAMEWORK}/ios-arm64_x86_64-simulator/libMapLibreBridge.a"
MACOS_LIBRARY="${FRAMEWORK}/macos-arm64_x86_64/libMapLibreBridge.a"

test -f "${INFO_PLIST}"
plutil -lint "${INFO_PLIST}"

PLIST_JSON="$(plutil -convert json -o - "${INFO_PLIST}")"
ruby -rjson -e '
  mode = ARGV.fetch(0)
  data = JSON.parse(STDIN.read)
  expected = {
    "ios-arm64" => ["ios", nil, ["arm64"]],
    "ios-arm64_x86_64-simulator" =>
      ["ios", "simulator", ["arm64", "x86_64"]]
  }
  if mode == "full"
    expected["macos-arm64_x86_64"] =
      ["macos", nil, ["arm64", "x86_64"]]
  end
  libraries = data.fetch("AvailableLibraries")
  abort "unexpected XCFramework library count" unless libraries.length == expected.length
  actual = libraries.to_h { |library|
    identifier = library.fetch("LibraryIdentifier")
    abort "unexpected XCFramework identifier: #{identifier}" unless expected.key?(identifier)
    abort "unexpected library path" unless library.fetch("LibraryPath") == "libMapLibreBridge.a"
    abort "unexpected headers path" unless library.fetch("HeadersPath") == "Headers"
    values = [
      library.fetch("SupportedPlatform"),
      library["SupportedPlatformVariant"],
      library.fetch("SupportedArchitectures").sort
    ]
    [identifier, values]
  }
  abort "unexpected XCFramework metadata" unless actual == expected
' "${MODE}" <<<"${PLIST_JSON}"

library_count="$(find "${FRAMEWORK}" -name libMapLibreBridge.a -type f | wc -l | tr -d ' ')"
if [[ "${library_count}" != "${EXPECTED_LIBRARY_COUNT}" ]]; then
    echo "error: XCFramework contains ${library_count} libraries instead of ${EXPECTED_LIBRARY_COUNT}" >&2
    exit 1
fi

check_architectures() {
    local library="$1"
    shift
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

check_architectures "${DEVICE_LIBRARY}" arm64
check_architectures "${SIMULATOR_LIBRARY}" arm64 x86_64
if [[ "${MODE}" == full ]]; then
    check_architectures "${MACOS_LIBRARY}" arm64 x86_64
fi

VERIFY_TEMP="$(mktemp -d -t maplibre-darwin-verify)"
trap 'rm -rf "${VERIFY_TEMP}"' EXIT

check_build_targets() {
    local library="$1"
    local architecture="$2"
    local expected_platform="$3"
    local label="$4"
    local target_dir="${VERIFY_TEMP}/${label}-${architecture}"
    local thin_archive="${target_dir}/libMapLibreBridge.a"
    local architectures
    local members
    local member_count=0
    local anchor_found=0
    local member
    local load_commands

    mkdir -p "${target_dir}"
    architectures="$(xcrun lipo -archs "${library}")"
    if [[ "$(wc -w <<<"${architectures}" | tr -d ' ')" -eq 1 ]]; then
        cp "${library}" "${thin_archive}"
    else
        xcrun lipo "${library}" \
            -thin "${architecture}" \
            -output "${thin_archive}"
    fi

    members="$(ar -t "${thin_archive}")"
    while IFS= read -r member; do
        [[ -z "${member}" ]] && continue
        [[ "${member##*/}" == __.SYMDEF* ]] && continue
        member_count=$((member_count + 1))
        [[ "${member##*/}" == maplibre_bridge_anchor.o ]] && anchor_found=1
    done <<<"${members}"
    if [[ "${member_count}" -eq 0 ]]; then
        echo "error: ${library} ${architecture} contains no object files" >&2
        exit 1
    fi
    if [[ "${anchor_found}" -ne 1 ]]; then
        echo "error: force-link anchor is missing from ${library}" >&2
        exit 1
    fi

    load_commands="$(xcrun otool -l "${thin_archive}")"
    ruby -e '
      expected_platform = ARGV.fetch(0)
      expected_minos = ARGV.fetch(1)
      expected_count = Integer(ARGV.fetch(2))
      label = ARGV.fetch(3)
      builds = []
      current = nil

      STDIN.each_line do |line|
        if line.match?(/^Load command /)
          current = nil
        elsif line.match?(/^\s*cmd LC_BUILD_VERSION\s*$/)
          current = {}
          builds << current
        elsif current && (match = line.match(/^\s*platform\s+(\d+)\s*$/))
          current[:platform] = match[1]
        elsif current && (match = line.match(/^\s*minos\s+(\S+)\s*$/))
          current[:minos] = match[1]
        end
      end

      abort "#{label} has #{builds.length} build targets for #{expected_count} objects" unless builds.length == expected_count
      builds.each_with_index do |build, index|
        abort "#{label} object #{index + 1} has the wrong Apple platform" unless build[:platform] == expected_platform
        valid_minos = [expected_minos, "#{expected_minos}.0"]
        abort "#{label} object #{index + 1} does not target #{expected_minos}" unless valid_minos.include?(build[:minos])
      end
    ' "${expected_platform}" 14.3 "${member_count}" \
        "${library} ${architecture}" <<<"${load_commands}"
}

check_build_targets "${DEVICE_LIBRARY}" arm64 2 ios-device
check_build_targets "${SIMULATOR_LIBRARY}" arm64 7 ios-simulator
check_build_targets "${SIMULATOR_LIBRARY}" x86_64 7 ios-simulator
if [[ "${MODE}" == full ]]; then
    check_build_targets "${MACOS_LIBRARY}" arm64 1 macos
    check_build_targets "${MACOS_LIBRARY}" x86_64 1 macos
fi

slices=(ios-arm64 ios-arm64_x86_64-simulator)
if [[ "${MODE}" == full ]]; then
    slices+=(macos-arm64_x86_64)
fi
for slice in "${slices[@]}"; do
    test -f "${FRAMEWORK}/${slice}/Headers/MapLibreBridge.h"
    test -f "${FRAMEWORK}/${slice}/Headers/module.modulemap"
done

# shellcheck source=../../native/scripts/packaging/darwin_common.sh
source "${PROJECT_ROOT}/native/scripts/packaging/darwin_common.sh"
verify_bridge_archive "${DEVICE_LIBRARY}"
verify_bridge_archive "${SIMULATOR_LIBRARY}"
if [[ "${MODE}" == full ]]; then
    verify_bridge_archive "${MACOS_LIBRARY}"
fi

du -sh "${FRAMEWORK}"
