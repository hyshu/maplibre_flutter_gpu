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
test -s hook/desktop_artifacts.json

flutter pub get
flutter test \
    test/package_configuration_test.dart \
    test/desktop_artifact_hook_test.dart
test -s assets/shaderbundles/MapShaders.shaderbundle
publish_log="$(mktemp)"
trap 'rm -f "${publish_log}"' EXIT

dart pub publish --dry-run --ignore-warnings 2>&1 | tee "${publish_log}"

python3 - "${publish_log}" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"^Total compressed archive size: ([0-9.]+) ([KMG]B)\.$", text, re.M)
if match is None:
    raise SystemExit("error: pub archive size was not reported")
scale = {"KB": 1 / 1000, "MB": 1, "GB": 1000}[match.group(2)]
size_mb = float(match.group(1)) * scale
if size_mb >= 100:
    raise SystemExit(f"error: pub archive is {size_mb:g} MB, limit is below 100 MB")
print(f"Pub archive size gate passed: {size_mb:g} MB")
PY

if grep -Eq '^Package has [1-9][0-9]* warnings?\.$' "${publish_log}"; then
    grep -Fxq 'Package has 1 warning.' "${publish_log}"
    grep -Eq '\* [0-9]+ checked-in files? (is|are) ignored by a `.gitignore`\.' \
        "${publish_log}"
    grep -Fq 'vendor/maplibre-native' "${publish_log}"
fi
