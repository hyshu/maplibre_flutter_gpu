#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 <android-arm64-v8a|android-x86_64|darwin-ios|darwin|linux-x64|linux-arm64|windows-x64|windows-arm64> <archive>" >&2
    exit 64
fi

KIND="$1"
OUTPUT="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

case "${KIND}" in
    android-arm64-v8a|android-x86_64)
        ABI="${KIND#android-}"
        "${SCRIPT_DIR}/verify_android_artifact.sh" "${ABI}"
        ARCHIVE_PATH="android/src/main/jniLibs/${ABI}/libmaplibre_bridge.so"
        ;;
    darwin-ios)
        "${SCRIPT_DIR}/verify_darwin_artifact.sh" ios
        ARCHIVE_PATH='darwin/maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework'
        ;;
    darwin)
        "${SCRIPT_DIR}/verify_darwin_artifact.sh" full
        ARCHIVE_PATH='darwin/maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework'
        ;;
    linux-x64|linux-arm64)
        ARCHITECTURE="${KIND#linux-}"
        "${PROJECT_ROOT}/native/scripts/build_linux.sh" \
            --verify-only \
            "${PROJECT_ROOT}/linux/${ARCHITECTURE}/libmaplibre_bridge.so"
        ARCHIVE_PATH="linux/${ARCHITECTURE}/libmaplibre_bridge.so"
        ;;
    windows-x64|windows-arm64)
        ARCHITECTURE="${KIND#windows-}"
        python "${SCRIPT_DIR}/verify_desktop_artifact.py" \
            --platform windows \
            --library "${PROJECT_ROOT}/windows/${ARCHITECTURE}/maplibre_bridge.dll"
        ARCHIVE_PATH="windows/${ARCHITECTURE}/maplibre_bridge.dll"
        ;;
    *)
        echo "error: unsupported native artifact kind: ${KIND}" >&2
        exit 64
        ;;
esac

mkdir -p "$(dirname "${OUTPUT}")"
(
    cd "${PROJECT_ROOT}"
    COPYFILE_DISABLE=1 tar -czf "${OUTPUT}" "${ARCHIVE_PATH}"
)

OUTPUT_DIRECTORY="$(cd "$(dirname "${OUTPUT}")" && pwd)"
OUTPUT_NAME="$(basename "${OUTPUT}")"
(
    cd "${OUTPUT_DIRECTORY}"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${OUTPUT_NAME}" >"${OUTPUT_NAME}.sha256"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${OUTPUT_NAME}" >"${OUTPUT_NAME}.sha256"
    else
        echo 'error: sha256sum or shasum is required' >&2
        exit 1
    fi
)

ls -lh "${OUTPUT}" "${OUTPUT}.sha256"
