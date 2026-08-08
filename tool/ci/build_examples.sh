#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 <android|ios|macos>" >&2
    exit 64
fi

PLATFORM="$1"
case "${PLATFORM}" in
    android|ios|macos)
        ;;
    *)
        echo "error: unsupported example platform: ${PLATFORM}" >&2
        exit 64
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
EXAMPLES=(
    example
    examples/gpu_map_scene
    examples/map_style_controls
)

for example in "${EXAMPLES[@]}"; do
    (
        cd "${PROJECT_ROOT}/${example}"
        flutter pub get --enforce-lockfile

        case "${PLATFORM}" in
            android)
                flutter build apk \
                    --debug \
                    --no-pub \
                    --target-platform android-arm64,android-x64
                apk='build/app/outputs/flutter-apk/app-debug.apk'
                apk_entries="$(unzip -Z1 "${apk}")"
                grep -Fqx \
                    'lib/arm64-v8a/libmaplibre_bridge.so' \
                    <<<"${apk_entries}"
                grep -Fqx \
                    'lib/x86_64/libmaplibre_bridge.so' \
                    <<<"${apk_entries}"
                ;;
            ios)
                flutter build ios \
                    --simulator \
                    --debug \
                    --no-codesign \
                    --no-pub
                ;;
            macos)
                flutter build macos --debug --no-pub
                ;;
        esac
    )
done

if [[ "${PLATFORM}" == macos ]]; then
    pod ipc spec "${PROJECT_ROOT}/darwin/maplibre_flutter_gpu.podspec" >/dev/null
fi
