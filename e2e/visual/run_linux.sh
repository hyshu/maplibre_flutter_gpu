#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
output="${VISUAL_E2E_LINUX_OUTPUT:-$repository_root/e2e/visual/report-linux}"
scene_option="${VISUAL_E2E_SCENE:-geometry}"
scenes_option="${VISUAL_E2E_SCENES:-}"
baseline=""
update_baseline=0
allow_missing_baseline=0
minimum_similarity="${VISUAL_E2E_MINIMUM_SIMILARITY:-1.0}"
idle_retries="${VISUAL_E2E_IDLE_RETRIES:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    --scene)
      scene_option="$2"
      scenes_option=""
      shift 2
      ;;
    --scenes)
      scenes_option="$2"
      scene_option=""
      shift 2
      ;;
    --baseline)
      baseline="$2"
      shift 2
      ;;
    --update-baseline)
      update_baseline=1
      shift
      ;;
    --allow-missing-baseline)
      allow_missing_baseline=1
      shift
      ;;
    --minimum-similarity)
      minimum_similarity="$2"
      shift 2
      ;;
    --idle-retries)
      idle_retries="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -n "$scenes_option" ]]; then
  IFS=',' read -r -a scenes <<<"$scenes_option"
elif [[ -n "$scene_option" ]]; then
  scenes=("$scene_option")
else
  scenes=("geometry")
fi

declare -a normalized_scenes=()
seen_scenes="|"
for scene in "${scenes[@]}"; do
  scene="${scene//[[:space:]]/}"
  case "$scene" in
    geometry|text-symbol|3d-buildings|line-variants|raster-pattern|mvt|mlt|tilejson-mvt|pmtiles-raster|mbtiles-raster|image-source|geojson-url|raster-jpeg|raster-webp|raster-tms|wmts|pmtiles-vector|pmtiles-mlt|mbtiles-vector|mbtiles-mlt)
      ;;
    *)
      echo "Unsupported Linux visual scene: $scene" >&2
      exit 2
      ;;
  esac
  if [[ "$seen_scenes" == *"|$scene|"* ]]; then
    echo "Duplicate Linux visual scene: $scene" >&2
    exit 2
  fi
  seen_scenes="$seen_scenes$scene|"
  normalized_scenes+=("$scene")
done
scenes=("${normalized_scenes[@]}")

if [[ "${#scenes[@]}" -eq 0 ]]; then
  echo "At least one Linux visual scene is required." >&2
  exit 2
fi
if [[ -z "$idle_retries" ]]; then
  if [[ "${#scenes[@]}" -eq 1 ]]; then
    idle_retries=3
  else
    idle_retries=0
  fi
fi
if ! [[ "$idle_retries" =~ ^[0-9]+$ ]]; then
  echo "--idle-retries must be a non-negative integer (got \"$idle_retries\")." >&2
  exit 2
fi
if [[ -n "$baseline" && "${#scenes[@]}" -ne 1 ]]; then
  echo "--baseline requires exactly one scene." >&2
  exit 2
fi
if [[ "$update_baseline" -eq 1 && "${#scenes[@]}" -ne 1 ]]; then
  echo "--update-baseline requires exactly one scene." >&2
  exit 2
fi
if [[ "$allow_missing_baseline" -eq 1 && "${#scenes[@]}" -ne 1 ]]; then
  echo "--allow-missing-baseline requires exactly one scene." >&2
  exit 2
fi

if [[ "$output" != /* ]]; then
  output="$repository_root/$output"
fi
if [[ -n "$baseline" && "$baseline" != /* ]]; then
  baseline="$repository_root/$baseline"
fi
if [[ "${#scenes[@]}" -eq 1 ]]; then
  logs_dir="$output/${scenes[0]}/logs"
else
  logs_dir="$output/logs"
fi
mkdir -p "$logs_dir"
rm -f "$logs_dir"/maplibre_flutter_gpu-test*.log
for scene in "${scenes[@]}"; do
  scene_output="$output/$scene"
  rm -f \
    "$scene_output/images/gpu.png" \
    "$scene_output/images/baseline.png" \
    "$scene_output/images/baseline-diff.png" \
    "$scene_output/images/command-coverage.json" \
    "$scene_output/index.html" \
    "$scene_output/results.json" \
    "$scene_output/baseline-results.json"
done

capture_dir="$(mktemp -d "${TMPDIR:-/tmp}/maplibre-linux-e2e.XXXXXX")"
cleanup() {
  rm -rf "$capture_dir"
}
trap cleanup EXIT

(
  cd "$repository_root/e2e/visual/gpu_app"
  flutter pub get
)

: >"$logs_dir/maplibre_flutter_gpu-test.log"
for scene in "${scenes[@]}"; do
  test_command=(
    flutter test
    --enable-impeller
    --enable-flutter-gpu
    integration_test/visual_test.dart
    -d linux
    --dart-define="VISUAL_E2E_SCREENSHOT_DIR=$capture_dir"
    --dart-define="VISUAL_E2E_SCENE=$scene"
  )
  attempt=1
  max_attempts=$((idle_retries + 1))
  while true; do
    current_log="$capture_dir/$scene-test-attempt-$attempt.log"
    attempt_log="$logs_dir/maplibre_flutter_gpu-test-attempt-$attempt.log"
    rm -f \
      "$capture_dir/$scene.png" \
      "$capture_dir/$scene.coverage.json" \
      "$current_log"
    set +e
    (
      cd "$repository_root/e2e/visual/gpu_app"
      "${test_command[@]}"
    ) 2>&1 | tee "$current_log" | tee -a "$attempt_log"
    test_status=${PIPESTATUS[0]}
    set -e

    if [[ "$test_status" -eq 0 ]]; then
      cat "$current_log" >>"$logs_dir/maplibre_flutter_gpu-test.log"
      break
    fi
    if ! grep -q 'did not become idle' "$current_log"; then
      echo "Visual E2E scene $scene failed for a reason other than the idle timeout." >&2
      exit "$test_status"
    fi
    if [[ "$attempt" -ge "$max_attempts" ]]; then
      echo "Visual E2E scene $scene did not become idle after $attempt attempts." >&2
      exit "$test_status"
    fi
    echo "Scene $scene attempt $attempt hit the idle timeout; retrying." >&2
    attempt=$((attempt + 1))
    sleep 5
  done
done

(
  cd "$repository_root/e2e/visual/runner"
  dart pub get
)

is_strict_scene() {
  case "$1" in
    geometry|text-symbol|3d-buildings|line-variants|raster-pattern) return 0 ;;
    *) return 1 ;;
  esac
}

suite_status=0
record_status() {
  local status="$1"
  if [[ "$status" -ne 0 && "$suite_status" -eq 0 ]]; then
    suite_status="$status"
  fi
}

for scene in "${scenes[@]}"; do
  scene_output="$output/$scene"
  images_dir="$scene_output/images"
  screenshot="$images_dir/gpu.png"
  coverage="$images_dir/command-coverage.json"
  mkdir -p "$images_dir"
  rm -f \
    "$screenshot" \
    "$images_dir/baseline.png" \
    "$images_dir/baseline-diff.png" \
    "$coverage" \
    "$scene_output/index.html" \
    "$scene_output/results.json" \
    "$scene_output/baseline-results.json"
  cp "$capture_dir/$scene.png" "$screenshot"
  cp "$capture_dir/$scene.coverage.json" "$coverage"

  set +e
  (
    cd "$repository_root/e2e/visual/runner"
    dart run bin/verify_desktop_smoke.dart \
      --platform Linux \
      --screenshot "$screenshot" \
      --scene "$scene" \
      --output "$scene_output"
  )
  status=$?
  set -e
  record_status "$status"

  scene_baseline="$repository_root/e2e/visual/baseline/linux-$scene.png"
  if [[ -n "$baseline" ]]; then
    scene_baseline="$baseline"
  fi
  coverage_expectation="$repository_root/e2e/visual/baseline/linux-$scene.coverage.json"

  if [[ "$update_baseline" -eq 1 ]]; then
    set +e
    (
      set -e
      cd "$repository_root/e2e/visual/runner"
      dart run bin/verify_desktop_baseline.dart \
        --platform Linux \
        --screenshot "$screenshot" \
        --baseline "$scene_baseline" \
        --scene "$scene" \
        --output "$scene_output" \
        --update-baseline
      dart run bin/verify_command_coverage.dart \
        --coverage "$coverage" \
        --expected "$coverage_expectation" \
        --scene "$scene" \
        --update-expected
    )
    status=$?
    set -e
    record_status "$status"
  elif [[ "${#scenes[@]}" -eq 1 ]] || \
    is_strict_scene "$scene" || \
    [[ -n "$baseline" ]]; then
    if [[ "$allow_missing_baseline" -eq 1 && ! -f "$scene_baseline" ]]; then
      echo "WARNING: no Linux baseline at $scene_baseline." >&2
    else
      set +e
      (
        cd "$repository_root/e2e/visual/runner"
        dart run bin/verify_desktop_baseline.dart \
          --platform Linux \
          --screenshot "$screenshot" \
          --baseline "$scene_baseline" \
          --scene "$scene" \
          --output "$scene_output" \
          --minimum-similarity "$minimum_similarity"
      )
      status=$?
      set -e
      record_status "$status"
    fi

    if [[ "$allow_missing_baseline" -eq 1 && ! -f "$coverage_expectation" ]]; then
      echo "WARNING: no coverage expectation at $coverage_expectation." >&2
    else
      set +e
      (
        cd "$repository_root/e2e/visual/runner"
        dart run bin/verify_command_coverage.dart \
          --coverage "$coverage" \
          --expected "$coverage_expectation" \
          --scene "$scene"
      )
      status=$?
      set -e
      record_status "$status"
    fi
  fi
done

exit "$suite_status"
