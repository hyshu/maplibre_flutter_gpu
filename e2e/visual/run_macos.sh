#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output="${VISUAL_E2E_MACOS_OUTPUT:-$repository_root/e2e/visual/report-macos}"
scene="${VISUAL_E2E_SCENE:-geometry}"
baseline=""
update_baseline=0
allow_missing_baseline=0
minimum_similarity="${VISUAL_E2E_MINIMUM_SIMILARITY:-1.0}"
idle_retries="${VISUAL_E2E_IDLE_RETRIES:-3}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    --scene)
      scene="$2"
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
if ! [[ "$idle_retries" =~ ^[0-9]+$ ]]; then
  echo "--idle-retries must be a non-negative integer (got \"$idle_retries\")." >&2
  exit 2
fi
if [[ "$output" != /* ]]; then
  output="$repository_root/$output"
fi
if [[ -z "$baseline" ]]; then
  baseline="$repository_root/e2e/visual/baseline/macos-$scene.png"
fi
if [[ "$baseline" != /* ]]; then
  baseline="$repository_root/$baseline"
fi
coverage_expectation="$repository_root/e2e/visual/baseline/macos-$scene.coverage.json"
# Scene-scoped so consecutive runs of different scenes do not overwrite each
# other's screenshot, diff, and results.
output="$output/$scene"
images_dir="$output/images"
logs_dir="$output/logs"
screenshot="$images_dir/gpu.png"
mkdir -p "$images_dir" "$logs_dir"
# Remove every artifact this run regenerates. A stale baseline-results.json
# left over from an earlier run would otherwise read as this run's verdict.
rm -f \
  "$screenshot" \
  "$images_dir/baseline.png" \
  "$images_dir/baseline-diff.png" \
  "$output/index.html" \
  "$output/results.json" \
  "$output/baseline-results.json" \
  "$images_dir/command-coverage.json"
rm -f "$logs_dir"/maplibre_flutter_gpu-test-attempt-*.log

# The macOS harness intermittently fails with "did not become idle": the app
# reports "Failed to foreground app" on every run, and a backgrounded window
# does not always get GPU frames. That is an environment flake, not a result,
# so retry it — but ONLY it. Every other failure, including a baseline
# mismatch, is a real signal and must surface on the first attempt.
attempt=1
max_attempts=$((idle_retries + 1))
while true; do
  test_log="$logs_dir/maplibre_flutter_gpu-test-attempt-$attempt.log"
  set +e
  (
    cd "$repository_root/e2e/visual/gpu_app"
    flutter pub get
    flutter test \
      integration_test/visual_test.dart \
      -d macos \
      --dart-define=VISUAL_E2E_SCENE="$scene" \
      --dart-define=VISUAL_E2E_SCREENSHOT_PATH="$screenshot"
  ) 2>&1 | tee "$test_log"
  test_status=${PIPESTATUS[0]}
  set -e

  if [[ "$test_status" == 0 ]]; then
    break
  fi
  if ! grep -q 'did not become idle' "$test_log"; then
    echo "Visual E2E failed for a reason other than the idle timeout." >&2
    exit "$test_status"
  fi
  if [[ "$attempt" -ge "$max_attempts" ]]; then
    echo "Visual E2E did not become idle after $attempt attempts." >&2
    exit "$test_status"
  fi
  echo "Attempt $attempt hit the idle timeout; retrying." >&2
  attempt=$((attempt + 1))
  sleep 5
done

(
  cd "$repository_root/e2e/visual/runner"
  dart run bin/verify_desktop_smoke.dart \
    --screenshot "$screenshot" \
    --scene "$scene" \
    --output "$output"
)

# Baseline diff. The smoke check above only proves that something was drawn,
# so it cannot catch a refactor that corrupts UBO offsets, pass ordering, or
# vertex strides. This step does, once a baseline has been committed.
(
  cd "$repository_root/e2e/visual/runner"
  if [[ "$update_baseline" == 1 ]]; then
    dart run bin/verify_desktop_baseline.dart \
      --screenshot "$screenshot" \
      --baseline "$baseline" \
      --scene "$scene" \
      --output "$output" \
      --update-baseline
  elif [[ -f "$baseline" ]]; then
    dart run bin/verify_desktop_baseline.dart \
      --screenshot "$screenshot" \
      --baseline "$baseline" \
      --scene "$scene" \
      --output "$output" \
      --minimum-similarity "$minimum_similarity"
  elif [[ "$allow_missing_baseline" == 1 ]]; then
    echo "WARNING: no macOS baseline at $baseline — regression diff skipped." >&2
  else
    # Failing here is the point. A missing baseline means this run proved
    # nothing about regressions, and reporting success would hide that.
    echo "ERROR: no macOS baseline at $baseline." >&2
    echo "       Capture one on a known-good commit with:" >&2
    echo "         $0 --scene $scene --update-baseline" >&2
    echo "       or pass --allow-missing-baseline to skip the diff on purpose." >&2
    exit 3
  fi
)

# Command coverage. Several render paths write no visible pixels, so the image
# diff above cannot tell whether they ran. This checks that the scene still
# reaches every path it reached when its baseline was captured.
(
  cd "$repository_root/e2e/visual/runner"
  coverage="$images_dir/command-coverage.json"
  if [[ "$update_baseline" == 1 ]]; then
    dart run bin/verify_command_coverage.dart \
      --coverage "$coverage" \
      --expected "$coverage_expectation" \
      --scene "$scene" \
      --update-expected
  elif [[ -f "$coverage_expectation" ]]; then
    dart run bin/verify_command_coverage.dart \
      --coverage "$coverage" \
      --expected "$coverage_expectation" \
      --scene "$scene"
  elif [[ "$allow_missing_baseline" == 1 ]]; then
    echo "WARNING: no coverage expectation at $coverage_expectation." >&2
  else
    echo "ERROR: no command coverage expectation at $coverage_expectation." >&2
    echo "       Record one with: $0 --scene $scene --update-baseline" >&2
    exit 3
  fi
)
