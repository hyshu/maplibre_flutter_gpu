#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${PROJECT_ROOT}"

python3 -m unittest discover -s tool/ci -p 'test_*.py'

flutter pub get

flutter_packages=(
    example
    examples/gpu_map_scene
    examples/map_layers
    examples/map_style_controls
    examples/tv_map_explorer
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
flutter test --dart-define=MAPLIBRE_PACKED_LINE_VERTICES=true \
    test/numeric_packed_line_vertices_test.dart \
    test/numeric_packed_line_shader_test.dart \
    test/gpu_ready_line_test.dart \
    test/fill_outline_data_driven_shader_test.dart \
    test/native_vertex_staging_test.dart \
    test/packed_line_shader_test.dart \
    test/pipeline_registry_test.dart \
    test/prepared_graph_test.dart \
    test/gpu_renderer_test.dart
flutter test --dart-define=MAPLIBRE_CACHE_HILLSHADE_PREPARATION=false \
    test/hillshade_preparation_cache_test.dart \
    test/offscreen_pass_plan_test.dart \
    test/hillshade_shader_test.dart \
    test/command_decoder_test.dart \
    test/gpu_renderer_test.dart
flutter test --dart-define=MAPLIBRE_LABEL_UPDATE_DIAGNOSTICS=true \
    test/label_update_diagnostics_test.dart
test -s assets/shaderbundles/MapShaders.shaderbundle

unit_test_packages=(
    example
    examples/gpu_map_scene
    examples/map_layers
    examples/map_style_controls
    examples/tv_map_explorer
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
