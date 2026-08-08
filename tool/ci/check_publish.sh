#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -gt 1 ]]; then
    echo "Usage: $0 [--allow-deferred|--metadata-only]" >&2
    exit 64
fi

MODE="${1:-strict}"
case "${MODE}" in
    strict|--allow-deferred|--metadata-only)
        ;;
    *)
        echo "Usage: $0 [--allow-deferred|--metadata-only]" >&2
        exit 64
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${PROJECT_ROOT}"

ready=true
if [[ ! -f README.md ]]; then
    echo '::notice::Publish dry run deferred until README.md is added.'
    ready=false
fi
if grep -Eq "^publish_to:[[:space:]]*['\"]?none['\"]?[[:space:]]*$" pubspec.yaml; then
    echo '::notice::Publish dry run deferred while publish_to is none.'
    ready=false
fi

if [[ "${ready}" != true ]]; then
    if [[ "${MODE}" == --allow-deferred ]]; then
        exit 0
    fi

    echo 'error: package metadata is not ready for publishing' >&2
    exit 1
fi

if [[ "${MODE}" == --metadata-only ]]; then
    exit 0
fi

test -s android/src/main/jniLibs/arm64-v8a/libmaplibre_bridge.so
test -s android/src/main/jniLibs/x86_64/libmaplibre_bridge.so
test -f darwin/maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework/Info.plist

flutter pub get
flutter test test/package_configuration_test.dart
test -s build/shaderbundles/MapShaders.shaderbundle
dart pub publish --dry-run
