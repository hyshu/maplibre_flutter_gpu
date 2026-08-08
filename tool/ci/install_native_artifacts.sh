#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    echo "Usage: $0 <artifact-directory> [all|android|ios|darwin]" >&2
    exit 64
fi

ARTIFACT_DIRECTORY="$(cd "$1" && pwd)"
MODE="${2:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DARWIN_FRAMEWORK="${PROJECT_ROOT}/darwin/maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework"

case "${MODE}" in
    all)
        archives=(
            native-android-arm64-v8a.tar.gz
            native-android-x86_64.tar.gz
            native-darwin.tar.gz
        )
        ;;
    android)
        archives=(
            native-android-arm64-v8a.tar.gz
            native-android-x86_64.tar.gz
        )
        ;;
    ios)
        archives=(native-darwin-ios.tar.gz)
        ;;
    darwin)
        archives=(native-darwin.tar.gz)
        ;;
    *)
        echo "Usage: $0 <artifact-directory> [all|android|ios|darwin]" >&2
        exit 64
        ;;
esac

archive_prefix() {
    case "$1" in
        native-android-arm64-v8a.tar.gz)
            echo 'android/src/main/jniLibs/arm64-v8a/libmaplibre_bridge.so'
            ;;
        native-android-x86_64.tar.gz)
            echo 'android/src/main/jniLibs/x86_64/libmaplibre_bridge.so'
            ;;
        native-darwin-ios.tar.gz|native-darwin.tar.gz)
            echo 'darwin/maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework'
            ;;
        *)
            echo "error: unsupported native archive: $1" >&2
            exit 64
            ;;
    esac
}

validate_entries() {
    local archive="$1"
    local prefix="$2"
    local entry
    local entry_count=0
    local entries
    local verbose_entries

    if ! entries="$(tar -tzf "${archive}")"; then
        echo "error: cannot list native artifact: ${archive}" >&2
        exit 1
    fi
    if ! verbose_entries="$(tar -tvzf "${archive}")"; then
        echo "error: cannot inspect native artifact: ${archive}" >&2
        exit 1
    fi

    while IFS= read -r entry; do
        entry_count=$((entry_count + 1))
        if [[ "${entry}" == /* || "/${entry}/" == *'/../'* ]]; then
            echo "error: unsafe path in ${archive}: ${entry}" >&2
            exit 1
        fi
        case "${entry}" in
            "${prefix}"|"${prefix}/"*)
                ;;
            *)
                echo "error: unexpected path in ${archive}: ${entry}" >&2
                exit 1
                ;;
        esac
    done <<<"${entries}"

    if [[ "${entry_count}" -eq 0 ]]; then
        echo "error: empty native artifact: ${archive}" >&2
        exit 1
    fi

    local verbose_entry
    local mode
    local member_type
    while IFS= read -r verbose_entry; do
        mode="${verbose_entry%% *}"
        member_type="${mode:0:1}"
        case "${member_type}" in
            -|d)
                ;;
            *)
                echo "error: links and special files are forbidden in ${archive}" >&2
                exit 1
                ;;
        esac
    done <<<"${verbose_entries}"
}

for archive in "${archives[@]}"; do
    test -f "${ARTIFACT_DIRECTORY}/${archive}"
    test -f "${ARTIFACT_DIRECTORY}/${archive}.sha256"

    checksum_file="${ARTIFACT_DIRECTORY}/${archive}.sha256"
    checksum_lines="$(awk 'NF { count++ } END { print count + 0 }' "${checksum_file}")"
    checksum_fields="$(awk 'NF { print NF }' "${checksum_file}")"
    expected_checksum="$(awk 'NF { print $1 }' "${checksum_file}")"
    checksum_name="$(awk 'NF { print $2 }' "${checksum_file}")"
    if [[ "${checksum_lines}" != 1 || "${checksum_fields}" != 2 ]]; then
        echo "error: malformed checksum file: ${checksum_file}" >&2
        exit 1
    fi
    if [[ "${checksum_name}" != "${archive}" ]]; then
        echo "error: checksum file does not name ${archive}" >&2
        exit 1
    fi

    actual_checksum="$(shasum -a 256 "${ARTIFACT_DIRECTORY}/${archive}" | awk '{ print $1 }')"
    if [[ "${actual_checksum}" != "${expected_checksum}" ]]; then
        echo "error: checksum mismatch for ${archive}" >&2
        exit 1
    fi
    echo "${archive}: OK"

    validate_entries \
        "${ARTIFACT_DIRECTORY}/${archive}" \
        "$(archive_prefix "${archive}")"
done

if [[ "${MODE}" == all || "${MODE}" == ios || "${MODE}" == darwin ]]; then
    rm -rf "${DARWIN_FRAMEWORK}"
fi

for archive in "${archives[@]}"; do
    tar -xzf "${ARTIFACT_DIRECTORY}/${archive}" -C "${PROJECT_ROOT}"
done

if [[ "${MODE}" == all || "${MODE}" == android ]]; then
    "${SCRIPT_DIR}/verify_android_artifact.sh" arm64-v8a
    "${SCRIPT_DIR}/verify_android_artifact.sh" x86_64
    git -C "${PROJECT_ROOT}" check-ignore -q \
        android/src/main/jniLibs/arm64-v8a/libmaplibre_bridge.so
    git -C "${PROJECT_ROOT}" check-ignore -q \
        android/src/main/jniLibs/x86_64/libmaplibre_bridge.so
fi

if [[ "${MODE}" == all || "${MODE}" == darwin ]]; then
    "${SCRIPT_DIR}/verify_darwin_artifact.sh" full
    git -C "${PROJECT_ROOT}" check-ignore -q \
        darwin/maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework/Info.plist
elif [[ "${MODE}" == ios ]]; then
    "${SCRIPT_DIR}/verify_darwin_artifact.sh" ios
    git -C "${PROJECT_ROOT}" check-ignore -q \
        darwin/maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework/Info.plist
fi
