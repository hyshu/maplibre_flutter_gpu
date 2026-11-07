#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    echo "Usage: $0 <artifact-directory> [all|android|ios|darwin|desktop|linux|linux-x64|linux-arm64|windows|windows-x64|windows-arm64]" >&2
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
            native-linux-x64.tar.gz
            native-linux-arm64.tar.gz
            native-windows-x64.tar.gz
            native-windows-arm64.tar.gz
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
    desktop)
        archives=(
            native-linux-x64.tar.gz
            native-linux-arm64.tar.gz
            native-windows-x64.tar.gz
            native-windows-arm64.tar.gz
        )
        ;;
    linux)
        archives=(
            native-linux-x64.tar.gz
            native-linux-arm64.tar.gz
        )
        ;;
    linux-x64)
        archives=(native-linux-x64.tar.gz)
        ;;
    linux-arm64)
        archives=(native-linux-arm64.tar.gz)
        ;;
    windows)
        archives=(
            native-windows-x64.tar.gz
            native-windows-arm64.tar.gz
        )
        ;;
    windows-x64)
        archives=(native-windows-x64.tar.gz)
        ;;
    windows-arm64)
        archives=(native-windows-arm64.tar.gz)
        ;;
    *)
        echo "Usage: $0 <artifact-directory> [all|android|ios|darwin|desktop|linux|linux-x64|linux-arm64|windows|windows-x64|windows-arm64]" >&2
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
        native-linux-x64.tar.gz)
            echo 'linux/x64/libmaplibre_bridge.so'
            ;;
        native-linux-arm64.tar.gz)
            echo 'linux/arm64/libmaplibre_bridge.so'
            ;;
        native-windows-x64.tar.gz)
            echo 'windows/x64/maplibre_bridge.dll'
            ;;
        native-windows-arm64.tar.gz)
            echo 'windows/arm64/maplibre_bridge.dll'
            ;;
        *)
            echo "error: unsupported native archive: $1" >&2
            exit 64
            ;;
    esac
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{ print $1 }'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{ print $1 }'
    else
        echo 'error: sha256sum or shasum is required' >&2
        exit 1
    fi
}

# Prints the only target allowed for a symbolic link at the given archive path.
# Fails when the archive must not contain a link there. The macOS slice of the
# Darwin archive uses the versioned framework layout, which links the top-level
# entries to Versions/Current and Versions/Current to Versions/A. Every other
# native archive holds regular files and directories only.
allowed_link_target() {
    local archive_name="$1"
    local entry="$2"
    local framework='darwin/maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework/macos-arm64_x86_64/MapLibreBridge.framework'

    if [[ "${archive_name}" != native-darwin.tar.gz ]]; then
        return 1
    fi
    case "${entry}" in
        "${framework}/Versions/Current")
            echo 'A'
            ;;
        "${framework}/MapLibreBridge"|"${framework}/Headers"|"${framework}/Modules"|"${framework}/Resources")
            echo "Versions/Current/${entry##*/}"
            ;;
        *)
            return 1
            ;;
    esac
}

line_count() {
    printf '%s\n' "$1" | awk 'END { print NR }'
}

validate_entries() {
    local archive="$1"
    local prefix="$2"
    local archive_name
    local entry
    local entry_count=0
    local entries
    local verbose_entries

    archive_name="$(basename "${archive}")"
    if ! entries="$(tar -tzf "${archive}")"; then
        echo "error: cannot list native artifact: ${archive}" >&2
        exit 1
    fi
    if ! verbose_entries="$(tar -tvzf "${archive}")"; then
        echo "error: cannot inspect native artifact: ${archive}" >&2
        exit 1
    fi
    if [[ "$(line_count "${entries}")" != "$(line_count "${verbose_entries}")" ]]; then
        echo "error: inconsistent listing of native artifact: ${archive}" >&2
        exit 1
    fi

    # Both listings report members in archive order, so line N of each
    # describes the same member.
    local verbose_entry
    local member_type
    local link_target
    while IFS= read -r entry <&3 && IFS= read -r verbose_entry <&4; do
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

        member_type="${verbose_entry:0:1}"
        case "${member_type}" in
            -|d)
                ;;
            l)
                if ! link_target="$(allowed_link_target "${archive_name}" "${entry}")" \
                    || [[ "${verbose_entry}" != *" ${entry} -> ${link_target}" ]]; then
                    echo "error: unexpected link in ${archive}: ${verbose_entry}" >&2
                    exit 1
                fi
                ;;
            *)
                echo "error: special files are forbidden in ${archive}: ${entry}" >&2
                exit 1
                ;;
        esac
    done 3<<<"${entries}" 4<<<"${verbose_entries}"

    if [[ "${entry_count}" -eq 0 ]]; then
        echo "error: empty native artifact: ${archive}" >&2
        exit 1
    fi
}

for archive in "${archives[@]}"; do
    test -f "${ARTIFACT_DIRECTORY}/${archive}"
    test -f "${ARTIFACT_DIRECTORY}/${archive}.sha256"

    checksum_file="${ARTIFACT_DIRECTORY}/${archive}.sha256"
    checksum_lines="$(awk 'NF { count++ } END { print count + 0 }' "${checksum_file}")"
    checksum_fields="$(awk 'NF { print NF }' "${checksum_file}")"
    expected_checksum="$(awk 'NF { print $1 }' "${checksum_file}")"
    checksum_name="$(awk 'NF { print $2 }' "${checksum_file}")"
    checksum_name="${checksum_name#\*}"
    if [[ "${checksum_lines}" != 1 || "${checksum_fields}" != 2 ]]; then
        echo "error: malformed checksum file: ${checksum_file}" >&2
        exit 1
    fi
    if [[ "${checksum_name}" != "${archive}" ]]; then
        echo "error: checksum file does not name ${archive}" >&2
        exit 1
    fi

    actual_checksum="$(sha256_file "${ARTIFACT_DIRECTORY}/${archive}")"
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
if [[ "${MODE}" == all || "${MODE}" == desktop || "${MODE}" == linux ]]; then
    rm -f "${PROJECT_ROOT}/linux/x64/libmaplibre_bridge.so"
    rm -f "${PROJECT_ROOT}/linux/arm64/libmaplibre_bridge.so"
elif [[ "${MODE}" == linux-x64 ]]; then
    rm -f "${PROJECT_ROOT}/linux/x64/libmaplibre_bridge.so"
elif [[ "${MODE}" == linux-arm64 ]]; then
    rm -f "${PROJECT_ROOT}/linux/arm64/libmaplibre_bridge.so"
fi
if [[ "${MODE}" == all || "${MODE}" == desktop || "${MODE}" == windows ]]; then
    rm -f "${PROJECT_ROOT}/windows/x64/maplibre_bridge.dll"
    rm -f "${PROJECT_ROOT}/windows/arm64/maplibre_bridge.dll"
elif [[ "${MODE}" == windows-x64 ]]; then
    rm -f "${PROJECT_ROOT}/windows/x64/maplibre_bridge.dll"
elif [[ "${MODE}" == windows-arm64 ]]; then
    rm -f "${PROJECT_ROOT}/windows/arm64/maplibre_bridge.dll"
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

if [[ "${MODE}" == all || "${MODE}" == desktop || "${MODE}" == linux ]]; then
    test -s "${PROJECT_ROOT}/linux/x64/libmaplibre_bridge.so"
    test -s "${PROJECT_ROOT}/linux/arm64/libmaplibre_bridge.so"
    git -C "${PROJECT_ROOT}" check-ignore -q linux/x64/libmaplibre_bridge.so
    git -C "${PROJECT_ROOT}" check-ignore -q linux/arm64/libmaplibre_bridge.so
elif [[ "${MODE}" == linux-x64 ]]; then
    test -s "${PROJECT_ROOT}/linux/x64/libmaplibre_bridge.so"
    git -C "${PROJECT_ROOT}" check-ignore -q linux/x64/libmaplibre_bridge.so
elif [[ "${MODE}" == linux-arm64 ]]; then
    test -s "${PROJECT_ROOT}/linux/arm64/libmaplibre_bridge.so"
    git -C "${PROJECT_ROOT}" check-ignore -q linux/arm64/libmaplibre_bridge.so
fi

if [[ "${MODE}" == all || "${MODE}" == desktop || "${MODE}" == windows ]]; then
    test -s "${PROJECT_ROOT}/windows/x64/maplibre_bridge.dll"
    test -s "${PROJECT_ROOT}/windows/arm64/maplibre_bridge.dll"
    git -C "${PROJECT_ROOT}" check-ignore -q windows/x64/maplibre_bridge.dll
    git -C "${PROJECT_ROOT}" check-ignore -q windows/arm64/maplibre_bridge.dll
elif [[ "${MODE}" == windows-x64 ]]; then
    test -s "${PROJECT_ROOT}/windows/x64/maplibre_bridge.dll"
    git -C "${PROJECT_ROOT}" check-ignore -q windows/x64/maplibre_bridge.dll
elif [[ "${MODE}" == windows-arm64 ]]; then
    test -s "${PROJECT_ROOT}/windows/arm64/maplibre_bridge.dll"
    git -C "${PROJECT_ROOT}" check-ignore -q windows/arm64/maplibre_bridge.dll
fi
