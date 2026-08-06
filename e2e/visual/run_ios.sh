#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output="$repository_root/e2e/visual/report-ios"
device="${VISUAL_E2E_IOS_DEVICE:-}"
minimum_similarity="${VISUAL_E2E_MINIMUM_SIMILARITY:-0.995}"
minimum_content_retention="${VISUAL_E2E_MINIMUM_CONTENT_RETENTION:-0}"
minimum_content_ratio="${VISUAL_E2E_MINIMUM_CONTENT_RATIO:-0}"
scene="${VISUAL_E2E_SCENE:-geometry}"
zoom="${VISUAL_E2E_ZOOM:-}"
performance=false
drive_timeout_seconds="${VISUAL_E2E_IOS_DRIVE_TIMEOUT_SECONDS:-600}"
drive_retries="${VISUAL_E2E_IOS_DRIVE_RETRIES:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      device="$2"
      shift 2
      ;;
    --output)
      output="$2"
      shift 2
      ;;
    --minimum-similarity)
      minimum_similarity="$2"
      shift 2
      ;;
    --minimum-content-retention)
      minimum_content_retention="$2"
      shift 2
      ;;
    --minimum-content-ratio)
      minimum_content_ratio="$2"
      shift 2
      ;;
    --scene)
      scene="$2"
      shift 2
      ;;
    --zoom)
      zoom="$2"
      shift 2
      ;;
    --performance)
      performance=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if ! [[ "$drive_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "VISUAL_E2E_IOS_DRIVE_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi
if ! [[ "$drive_retries" =~ ^[0-9]+$ ]]; then
  echo "VISUAL_E2E_IOS_DRIVE_RETRIES must be a non-negative integer." >&2
  exit 2
fi

if [[ "$output" != /* ]]; then
  output="$repository_root/$output"
fi
images_dir="$output/images"
logs_dir="$output/logs"
performance_dir="$output/performance"
mkdir -p "$images_dir" "$logs_dir" "$performance_dir"
rm -f \
  "$images_dir/maplibre_gl.png" \
  "$images_dir/gpu.png" \
  "$images_dir/diff.png" \
  "$performance_dir/maplibre_gl.json" \
  "$performance_dir/maplibre_flutter_gpu.json" \
  "$output/index.html" \
  "$output/results.json"

if [[ -z "$device" ]]; then
  device="$(
    xcrun simctl list devices available --json |
      ruby -rjson -e '
        devices = JSON.parse(STDIN.read).fetch("devices")
        match = devices.values.flatten.find { |d|
          d["isAvailable"] && d["name"].start_with?("iPhone")
        }
        abort "No available iPhone Simulator" unless match
        puts match.fetch("udid")
      '
  )"
fi

echo "Using iOS Simulator: $device"
xcrun simctl boot "$device" 2>/dev/null || true
open -gj -a Simulator 2>/dev/null || true
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override \
  --time 9:41 \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularBars 4 \
  --operatorName ""

run_fixture() {
  local app_dir="$1"
  local label="$2"
  local root="$repository_root/e2e/visual/$app_dir"
  local zoom_args=()
  local performance_args=()
  local performance_output=""
  local bundle_id=""
  local attempt=1
  local max_attempts=$((drive_retries + 1))
  local timeout_marker="$logs_dir/.$label-drive-timeout"
  if [[ -n "$zoom" ]]; then
    zoom_args+=(--dart-define="VISUAL_E2E_ZOOM=$zoom")
  fi
  if [[ "$performance" == true ]]; then
    performance_args+=(
      --dart-define=VISUAL_E2E_PERFORMANCE=true
      --dart-define="VISUAL_E2E_PERFORMANCE_ENVIRONMENT=iOS Simulator"
    )
    performance_output="$performance_dir/$label.json"
  fi
  if [[ "$label" == "maplibre_gl" ]]; then
    bundle_id="dev.maplibre.fluttergpu.e2e.visualE2eMaplibreGl"
  else
    bundle_id="dev.maplibre.fluttergpu.e2e.visualE2eGpu"
  fi

  echo "[$label] resolving dependencies"
  (
    cd "$root"
    flutter pub get
  ) 2>&1 | tee "$logs_dir/$label-pub-get.log"

  # Prevent a failed build from attaching to a stale fixture with old defines.
  xcrun simctl uninstall "$device" "$bundle_id" 2>/dev/null || true

  echo "[$label] running iOS integration test"
  while true; do
    rm -f "$timeout_marker"
    (
      cd "$root"
      VISUAL_E2E_SCREENSHOT_DIR="$images_dir" \
      VISUAL_E2E_PERFORMANCE_OUTPUT="$performance_output" \
        flutter drive \
          --driver=test_driver/integration_test.dart \
          --target=integration_test/visual_test.dart \
          --device-id="$device" \
          --dart-define=VISUAL_E2E_SCENE="$scene" \
          ${performance_args[@]+"${performance_args[@]}"} \
          ${zoom_args[@]+"${zoom_args[@]}"}
    ) &
    local drive_pid=$!
    (
      sleep "$drive_timeout_seconds"
      if kill -0 "$drive_pid" 2>/dev/null; then
        touch "$timeout_marker"
        echo "[$label] flutter drive timed out after ${drive_timeout_seconds}s." >&2
        pkill -TERM -P "$drive_pid" 2>/dev/null || true
        kill -TERM "$drive_pid" 2>/dev/null || true
      fi
    ) &
    local watchdog_pid=$!

    set +e
    wait "$drive_pid"
    local drive_status=$?
    set -e
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true

    if [[ ! -f "$timeout_marker" ]]; then
      return "$drive_status"
    fi
    xcrun simctl terminate "$device" "$bundle_id" 2>/dev/null || true
    xcrun simctl uninstall "$device" "$bundle_id" 2>/dev/null || true
    if [[ "$attempt" -ge "$max_attempts" ]]; then
      echo "[$label] flutter drive timed out after $attempt attempts." >&2
      return 124
    fi
    echo "[$label] retrying flutter drive after timeout." >&2
    attempt=$((attempt + 1))
  done 2>&1 | tee "$logs_dir/$label-drive.log"
}

run_fixture maplibre_gl_app maplibre_gl
run_fixture gpu_app maplibre_flutter_gpu

runner_zoom_args=()
if [[ -n "$zoom" ]]; then
  runner_zoom_args+=(--zoom "$zoom")
fi
runner_performance_args=()
if [[ "$performance" == true ]]; then
  runner_performance_args+=(
    --performance-reference "$performance_dir/maplibre_gl.json"
    --performance-actual "$performance_dir/maplibre_flutter_gpu.json"
  )
fi

(
  cd "$repository_root/e2e/visual/runner"
  dart run bin/run_android.dart \
    --skip-drive \
    --platform iOS \
    --scene "$scene" \
    ${runner_zoom_args[@]+"${runner_zoom_args[@]}"} \
    ${runner_performance_args[@]+"${runner_performance_args[@]}"} \
    --output "$output" \
    --minimum-similarity "$minimum_similarity" \
    --minimum-content-retention "$minimum_content_retention" \
    --minimum-content-ratio "$minimum_content_ratio"
)
