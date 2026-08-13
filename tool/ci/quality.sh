#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${PROJECT_ROOT}"

flutter pub get

flutter_packages=(
    example
    examples/gpu_map_scene
    examples/map_style_controls
    e2e/visual/gpu_app
    e2e/visual/maplibre_gl_app
    e2e/visual/shared
)
for package in "${flutter_packages[@]}"; do
    (
        cd "${package}"
        flutter pub get --enforce-lockfile
    )
done

(
    cd e2e/visual/runner
    dart pub get --enforce-lockfile
)

git ls-files -z -- '*.dart' |
    xargs -0 dart format --output=none --set-exit-if-changed

flutter test --coverage
dart run tool/ci/check_coverage.dart \
    --lcov coverage/lcov.info \
    --minimum "${MINIMUM_LINE_COVERAGE:-44}"
test -s assets/shaderbundles/MapShaders.shaderbundle

unit_test_packages=(
    example
    examples/gpu_map_scene
    examples/map_style_controls
    e2e/visual/shared
)
for package in "${unit_test_packages[@]}"; do
    (
        cd "${package}"
        flutter test
    )
done
test -s examples/gpu_map_scene/assets/shaderbundles/OverlayShaders.shaderbundle

(
    cd e2e/visual/runner
    dart test
)

dart analyze
for package in "${flutter_packages[@]}"; do
    (
        cd "${package}"
        dart analyze
    )
done
(
    cd e2e/visual/runner
    dart analyze
)

git diff --exit-code
