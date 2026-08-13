#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 <artifact-directory> <output-directory>" >&2
    exit 64
fi

ARTIFACT_DIRECTORY="$(cd "$1" && pwd)"
OUTPUT_DIRECTORY="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

mkdir -p "${OUTPUT_DIRECTORY}"
"${SCRIPT_DIR}/install_native_artifacts.sh" "${ARTIFACT_DIRECTORY}"

archives=(
    native-android-arm64-v8a.tar.gz
    native-android-x86_64.tar.gz
    native-darwin.tar.gz
    native-linux-x64.tar.gz
    native-windows-x64.tar.gz
)
for archive in "${archives[@]}"; do
    cp "${ARTIFACT_DIRECTORY}/${archive}" "${OUTPUT_DIRECTORY}/${archive}"
    cp \
        "${ARTIFACT_DIRECTORY}/${archive}.sha256" \
        "${OUTPUT_DIRECTORY}/${archive}.sha256"
done

(
    cd "${OUTPUT_DIRECTORY}"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${archives[@]}" >SHA256SUMS
    else
        shasum -a 256 "${archives[@]}" >SHA256SUMS
    fi
)

ROOT_COMMIT="$(git -C "${PROJECT_ROOT}" rev-parse HEAD)"
SUBMODULE_COMMIT="$(
    git -C "${PROJECT_ROOT}" ls-tree HEAD vendor/maplibre-native |
        awk '{ print $3 }'
)"
FLUTTER_VERSION="$(flutter --version | sed -n '1p')"
XCODE_VERSION="$(xcodebuild -version | tr '\n' ' ')"
NDK_VERSION='28.2.13676358'

{
    echo "repository=hyshu/maplibre_flutter_gpu"
    echo "commit=${ROOT_COMMIT}"
    echo "maplibre_native_commit=${SUBMODULE_COMMIT}"
    echo "flutter=${FLUTTER_VERSION}"
    echo "xcode=${XCODE_VERSION}"
    echo "android_ndk=${NDK_VERSION}"
} >"${OUTPUT_DIRECTORY}/release-manifest.txt"

"${SCRIPT_DIR}/check_publish.sh" 2>&1 |
    tee "${OUTPUT_DIRECTORY}/pub-dry-run.log"

git -C "${PROJECT_ROOT}" diff --exit-code
ls -lh "${OUTPUT_DIRECTORY}"
