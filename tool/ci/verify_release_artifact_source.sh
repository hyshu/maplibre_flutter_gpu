#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    echo "Usage: $0 <artifact-source-commit> <release-commit> [repository]" >&2
    exit 64
fi

ARTIFACT_SOURCE_COMMIT="$1"
RELEASE_COMMIT="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY="${3:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

git -C "${REPOSITORY}" rev-parse --verify \
    "${ARTIFACT_SOURCE_COMMIT}^{commit}" >/dev/null
git -C "${REPOSITORY}" rev-parse --verify \
    "${RELEASE_COMMIT}^{commit}" >/dev/null
git -C "${REPOSITORY}" merge-base --is-ancestor \
    "${ARTIFACT_SOURCE_COMMIT}" \
    "${RELEASE_COMMIT}"

while IFS= read -r path; do
    case "${path}" in
        .agents/skills/release-maplibre-flutter-gpu/SKILL.md | \
            .pubignore | \
            CHANGELOG.md | \
            android/src/main/java/org/maplibre/android/http/NativeHttpRequest.java | \
            darwin/maplibre_flutter_gpu.podspec | \
            e2e/visual/gpu_app/pubspec.lock | \
            example/pubspec.lock | \
            example/pubspec.yaml | \
            examples/gpu_map_scene/pubspec.lock | \
            examples/gpu_map_scene/pubspec.yaml | \
            examples/map_style_controls/pubspec.lock | \
            examples/map_style_controls/pubspec.yaml | \
            hook/desktop_artifacts.json | \
            pubspec.yaml)
            ;;
        *)
            echo "error: artifact source is incompatible with release change: ${path}" >&2
            exit 1
            ;;
    esac
done < <(
    git -C "${REPOSITORY}" diff \
        --name-only \
        "${ARTIFACT_SOURCE_COMMIT}..${RELEASE_COMMIT}"
)

echo "Release artifact source is compatible with the release commit."
