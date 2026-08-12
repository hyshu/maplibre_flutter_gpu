#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
output="$repository_root/e2e/visual/report-ios"
device="${VISUAL_E2E_IOS_DEVICE:-}"
scene_option="${VISUAL_E2E_SCENE:-geometry}"
scenes_option="${VISUAL_E2E_SCENES:-}"
minimum_similarity="${VISUAL_E2E_MINIMUM_SIMILARITY:-}"
minimum_content_retention="${VISUAL_E2E_MINIMUM_CONTENT_RETENTION:-}"
minimum_content_ratio="${VISUAL_E2E_MINIMUM_CONTENT_RATIO:-0}"
zoom="${VISUAL_E2E_ZOOM:-}"
performance=false
drive_timeout_seconds="${VISUAL_E2E_IOS_DRIVE_TIMEOUT_SECONDS:-}"
drive_retries="${VISUAL_E2E_IOS_DRIVE_RETRIES:-2}"
idle_retries="${VISUAL_E2E_IOS_IDLE_RETRIES:-1}"
drive_kill_grace_seconds="${VISUAL_E2E_IOS_DRIVE_KILL_GRACE_SECONDS:-5}"
simctl_timeout_seconds="${VISUAL_E2E_IOS_SIMCTL_TIMEOUT_SECONDS:-300}"
simctl_cleanup_timeout_seconds="${VISUAL_E2E_IOS_SIMCTL_CLEANUP_TIMEOUT_SECONDS:-30}"

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
      scene_option="$2"
      scenes_option=""
      shift 2
      ;;
    --scenes)
      scenes_option="$2"
      scene_option=""
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

if ! [[ "$drive_retries" =~ ^[0-9]+$ ]]; then
  echo "VISUAL_E2E_IOS_DRIVE_RETRIES must be a non-negative integer." >&2
  exit 2
fi
if ! [[ "$idle_retries" =~ ^[0-9]+$ ]]; then
  echo "VISUAL_E2E_IOS_IDLE_RETRIES must be a non-negative integer." >&2
  exit 2
fi
if ! [[ "$drive_kill_grace_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "VISUAL_E2E_IOS_DRIVE_KILL_GRACE_SECONDS must be a positive integer." >&2
  exit 2
fi
if ! [[ "$simctl_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "VISUAL_E2E_IOS_SIMCTL_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi
if ! [[ "$simctl_cleanup_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "VISUAL_E2E_IOS_SIMCTL_CLEANUP_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi

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
    geometry|text-symbol|3d-buildings|mvt|tilejson-mvt|image-source|geojson-url|raster-jpeg|raster-webp|raster-tms|wmts|flutter-markers)
      ;;
    *)
      echo "Unsupported iOS parity scene: $scene" >&2
      exit 2
      ;;
  esac
  if [[ "$seen_scenes" == *"|$scene|"* ]]; then
    echo "Duplicate iOS parity scene: $scene" >&2
    exit 2
  fi
  seen_scenes="$seen_scenes$scene|"
  normalized_scenes+=("$scene")
done
scenes=("${normalized_scenes[@]}")

if [[ "${#scenes[@]}" -eq 0 ]]; then
  echo "At least one iOS parity scene is required." >&2
  exit 2
fi
if [[ -z "$drive_timeout_seconds" ]]; then
  drive_timeout_seconds=600
fi
if ! [[ "$drive_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "VISUAL_E2E_IOS_DRIVE_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi
if [[ "$performance" == true && "${#scenes[@]}" -ne 1 ]]; then
  echo "--performance requires exactly one scene." >&2
  exit 2
fi
if [[ -n "$zoom" && "${#scenes[@]}" -ne 1 ]]; then
  echo "--zoom requires exactly one scene." >&2
  exit 2
fi

if [[ "$output" != /* ]]; then
  output="$repository_root/$output"
fi
mkdir -p "$output/logs" "$output/performance"
rm -f \
  "$output/logs/maplibre_gl-pub-get.log" \
  "$output/logs/maplibre_gl-drive.log" \
  "$output/logs/maplibre_flutter_gpu-pub-get.log" \
  "$output/logs/maplibre_flutter_gpu-drive.log" \
  "$output/logs/.maplibre_gl-drive-timeout" \
  "$output/logs/.maplibre_flutter_gpu-drive-timeout" \
  "$output/performance/maplibre_gl.json" \
  "$output/performance/maplibre_flutter_gpu.json"
for scene in "${scenes[@]}"; do
  if [[ "${#scenes[@]}" -eq 1 ]]; then
    scene_output="$output"
  else
    scene_output="$output/$scene"
  fi
  rm -f \
    "$scene_output/images/maplibre_gl.png" \
    "$scene_output/images/gpu.png" \
    "$scene_output/images/diff.png" \
    "$scene_output/index.html" \
    "$scene_output/results.json"
done

capture_dir="$(mktemp -d "${TMPDIR:-/tmp}/maplibre-ios-e2e.XXXXXX")"
active_drive_pid=""
active_watchdog_pid=""
active_command_pid=""
active_command_watchdog_pid=""

process_group_exists() {
  local group_id="$1"

  kill -0 -- "-$group_id" 2>/dev/null
}

managed_process_exists() {
  local group_id="$1"

  process_group_exists "$group_id" || kill -0 "$group_id" 2>/dev/null
}

terminate_process_group() {
  local group_id="$1"

  if process_group_exists "$group_id"; then
    kill -TERM -- "-$group_id" 2>/dev/null || true
  else
    kill -TERM "$group_id" 2>/dev/null || true
  fi
}

force_kill_process_group() {
  local group_id="$1"

  if process_group_exists "$group_id"; then
    kill -STOP -- "-$group_id" 2>/dev/null || true
    kill -KILL -- "-$group_id" 2>/dev/null || true
    return
  fi
  if kill -0 "$group_id" 2>/dev/null; then
    kill -STOP "$group_id" 2>/dev/null || true
    kill -KILL "$group_id" 2>/dev/null || true
  fi
}

run_with_deadline() {
  local timeout_seconds="$1"
  shift
  local command_description="$*"
  local timeout_marker=""
  local command_status=0

  (
    exec ruby -e \
      'Process.setsid unless Process.getpgrp == Process.pid; exec(*ARGV)' \
      "$@"
  ) &
  local command_pid=$!
  timeout_marker="$capture_dir/.command-$command_pid-timeout"
  rm -f "$timeout_marker"
  active_command_pid="$command_pid"

  (
    local timer_pid=""
    stop_timer() {
      if [[ -n "$timer_pid" ]]; then
        kill -TERM "$timer_pid" 2>/dev/null || true
        wait "$timer_pid" 2>/dev/null || true
      fi
    }
    trap 'stop_timer; exit 0' TERM INT
    /bin/sleep "$timeout_seconds" &
    timer_pid=$!
    wait "$timer_pid"
    timer_pid=""
    if managed_process_exists "$command_pid"; then
      touch "$timeout_marker"
      terminate_process_group "$command_pid"
      /bin/sleep "$drive_kill_grace_seconds" &
      timer_pid=$!
      wait "$timer_pid"
      timer_pid=""
      force_kill_process_group "$command_pid"
    fi
    trap - TERM INT
  ) &
  local watchdog_pid=$!
  active_command_watchdog_pid="$watchdog_pid"

  if wait "$command_pid"; then
    command_status=0
  else
    command_status=$?
  fi
  if [[ ! -f "$timeout_marker" ]]; then
    kill -TERM "$watchdog_pid" 2>/dev/null || true
  fi
  wait "$watchdog_pid" 2>/dev/null || true
  active_command_watchdog_pid=""
  active_command_pid=""

  if [[ -f "$timeout_marker" ]]; then
    echo "Command timed out after ${timeout_seconds}s: $command_description" >&2
    return 124
  fi

  return "$command_status"
}

run_optional_simctl() {
  local timeout_seconds="$1"
  shift
  local status=0

  if run_with_deadline "$timeout_seconds" xcrun simctl "$@"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 124 ]]; then
    return 124
  fi

  return 0
}

cleanup() {
  local status=$?

  trap - EXIT INT TERM
  if [[ -n "$active_command_watchdog_pid" ]]; then
    kill -TERM "$active_command_watchdog_pid" 2>/dev/null || true
    wait "$active_command_watchdog_pid" 2>/dev/null || true
    active_command_watchdog_pid=""
  fi
  if [[ -n "$active_command_pid" ]]; then
    terminate_process_group "$active_command_pid"
    force_kill_process_group "$active_command_pid"
    wait "$active_command_pid" 2>/dev/null || true
    active_command_pid=""
  fi
  if [[ -n "$active_watchdog_pid" ]]; then
    kill -TERM "$active_watchdog_pid" 2>/dev/null || true
    wait "$active_watchdog_pid" 2>/dev/null || true
    active_watchdog_pid=""
  fi
  if [[ -n "$active_drive_pid" ]]; then
    terminate_process_group "$active_drive_pid"
    force_kill_process_group "$active_drive_pid"
    wait "$active_drive_pid" 2>/dev/null || true
    active_drive_pid=""
  fi
  rm -rf "$capture_dir"

  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

configure_simulator_status_bar() {
  run_with_deadline "$simctl_timeout_seconds" \
    xcrun simctl status_bar "$device" override \
    --time 9:41 \
    --batteryState charged \
    --batteryLevel 100 \
    --wifiBars 3 \
    --cellularBars 4 \
    --operatorName ""
}

boot_simulator() {
  run_optional_simctl "$simctl_timeout_seconds" boot "$device"
  open -gj -a Simulator 2>/dev/null || true
  run_with_deadline "$simctl_timeout_seconds" \
    xcrun simctl bootstatus "$device" -b
  configure_simulator_status_bar
}

restart_simulator() {
  run_optional_simctl "$simctl_cleanup_timeout_seconds" shutdown "$device"
  boot_simulator
}

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
boot_simulator

run_fixture() {
  local app_dir="$1"
  local label="$2"
  local root="$repository_root/e2e/visual/$app_dir"
  local capture_name=""
  local bundle_id=""
  local timeout_marker="$output/logs/.$label-drive-timeout"
  local scenes_define=""
  if [[ "$label" == "maplibre_gl" ]]; then
    bundle_id="dev.maplibre.fluttergpu.e2e.visualE2eMaplibreGl"
    capture_name="maplibre_gl"
  else
    bundle_id="dev.maplibre.fluttergpu.e2e.visualE2eGpu"
    capture_name="gpu"
  fi

  echo "[$label] resolving dependencies"
  (
    cd "$root"
    flutter pub get
  ) 2>&1 | tee "$output/logs/$label-pub-get.log"

  run_optional_simctl \
    "$simctl_cleanup_timeout_seconds" uninstall "$device" "$bundle_id"

  : >"$output/logs/$label-drive.log"
  for scene in "${scenes[@]}"; do
    rm -f "$output/logs/$label-$scene-attempt-"*.log
  done

  scenes_define="$(IFS=,; echo "${scenes[*]}")"
  local invocation=1
  local timeout_attempt=1
  local idle_attempt=1
  local max_timeout_attempts=$((drive_retries + 1))
  local max_idle_attempts=$((idle_retries + 1))
  local fixture_drive_timeout_seconds=$((drive_timeout_seconds * ${#scenes[@]}))
  local drive_description="scenes $scenes_define"
  if [[ "${#scenes[@]}" -eq 1 ]]; then
    drive_description="scene ${scenes[0]}"
  fi

  while true; do
    local fixture_capture_dir="$capture_dir/$label/attempt-$invocation"
    local current_log="$fixture_capture_dir/drive.log"
    local watchdog_ready_marker="$fixture_capture_dir/watchdog-ready"
    local performance_output=""
    local canonical_performance=""
    local -a dart_defines=()
    mkdir -p "$fixture_capture_dir"
    rm -f "$timeout_marker"

    if [[ "${#scenes[@]}" -eq 1 ]]; then
      dart_defines+=(--dart-define="VISUAL_E2E_SCENE=${scenes[0]}")
    else
      dart_defines+=(--dart-define="VISUAL_E2E_SCENES=$scenes_define")
    fi
    if [[ -n "$zoom" ]]; then
      dart_defines+=(--dart-define="VISUAL_E2E_ZOOM=$zoom")
    fi
    if [[ "$performance" == true ]]; then
      dart_defines+=(
        --dart-define=VISUAL_E2E_PERFORMANCE=true
        --dart-define="VISUAL_E2E_PERFORMANCE_ENVIRONMENT=iOS Simulator"
      )
      performance_output="$fixture_capture_dir/performance.json"
      canonical_performance="$output/performance/$label.json"
    fi

    echo "[$label] running iOS visual $drive_description, attempt $invocation"
    (
      cd "$root"
      exec env \
        VISUAL_E2E_SCREENSHOT_DIR="$fixture_capture_dir" \
        VISUAL_E2E_PERFORMANCE_OUTPUT="$performance_output" \
        ruby -e \
          'Process.setsid unless Process.getpgrp == Process.pid; exec(*ARGV)' \
          flutter drive \
          --driver=test_driver/integration_test.dart \
          --target=integration_test/visual_test.dart \
          --device-id="$device" \
          "${dart_defines[@]}"
    ) >"$current_log" 2>&1 &
    local drive_pid=$!
    active_drive_pid="$drive_pid"
    (
      local watchdog_sleep_pid=""
      stop_watchdog_sleep() {
        if [[ -n "$watchdog_sleep_pid" ]]; then
          kill -TERM "$watchdog_sleep_pid" 2>/dev/null || true
          wait "$watchdog_sleep_pid" 2>/dev/null || true
        fi
      }
      trap 'stop_watchdog_sleep; exit 0' TERM INT
      sleep "$fixture_drive_timeout_seconds" &
      watchdog_sleep_pid=$!
      touch "$watchdog_ready_marker"
      wait "$watchdog_sleep_pid"
      watchdog_sleep_pid=""
      if managed_process_exists "$drive_pid"; then
        touch "$timeout_marker"
        echo "[$label] $drive_description timed out after ${fixture_drive_timeout_seconds}s." >&2
        terminate_process_group "$drive_pid"
        /bin/sleep "$drive_kill_grace_seconds" &
        watchdog_sleep_pid=$!
        wait "$watchdog_sleep_pid"
        watchdog_sleep_pid=""
        force_kill_process_group "$drive_pid"
      fi
      trap - TERM INT
    ) &
    local watchdog_pid=$!
    active_watchdog_pid="$watchdog_pid"
    while [[ ! -f "$watchdog_ready_marker" ]]; do
      if ! kill -0 "$watchdog_pid" 2>/dev/null; then
        wait "$watchdog_pid" 2>/dev/null || true
        active_watchdog_pid=""
        echo "[$label] $drive_description watchdog failed to start." >&2
        return 1
      fi
      /bin/sleep 0.01
    done

    set +e
    wait "$drive_pid"
    local drive_status=$?
    set -e
    if [[ ! -f "$timeout_marker" ]]; then
      kill -TERM "$watchdog_pid" 2>/dev/null || true
    fi
    wait "$watchdog_pid" 2>/dev/null || true
    active_watchdog_pid=""
    active_drive_pid=""
    for scene in "${scenes[@]}"; do
      cp \
        "$current_log" \
        "$output/logs/$label-$scene-attempt-$invocation.log"
    done
    tee -a "$output/logs/$label-drive.log" <"$current_log"

    if [[ "$drive_status" -eq 0 && ! -f "$timeout_marker" ]]; then
      for scene in "${scenes[@]}"; do
        local attempt_capture="$fixture_capture_dir/$capture_name.png"
        local canonical_capture="$capture_dir/$capture_name.png"
        if [[ "${#scenes[@]}" -gt 1 ]]; then
          attempt_capture="$fixture_capture_dir/$capture_name-$scene.png"
          canonical_capture="$capture_dir/$capture_name-$scene.png"
        fi
        cp "$attempt_capture" "$canonical_capture"
      done
      if [[ "$performance" == true ]]; then
        cp "$performance_output" "$canonical_performance"
      fi
      break
    fi

    run_optional_simctl \
      "$simctl_cleanup_timeout_seconds" terminate "$device" "$bundle_id"
    run_optional_simctl \
      "$simctl_cleanup_timeout_seconds" uninstall "$device" "$bundle_id"
    if [[ -f "$timeout_marker" ]]; then
      if [[ "$timeout_attempt" -ge "$max_timeout_attempts" ]]; then
        echo "[$label] $drive_description timed out after $timeout_attempt attempts." >&2
        return 124
      fi
      echo "[$label] retrying $drive_description after timeout." >&2
      restart_simulator
      timeout_attempt=$((timeout_attempt + 1))
      invocation=$((invocation + 1))
      continue
    fi
    if ! grep -Fq 'did not become idle' "$current_log"; then
      echo "[$label] $drive_description failed for a reason other than the idle timeout." >&2
      return "$drive_status"
    fi
    if [[ "$idle_attempt" -ge "$max_idle_attempts" ]]; then
      echo "[$label] $drive_description did not become idle after $idle_attempt attempts." >&2
      return "$drive_status"
    fi
    echo "[$label] retrying $drive_description after the idle timeout." >&2
    idle_attempt=$((idle_attempt + 1))
    invocation=$((invocation + 1))
  done
}

default_similarity() {
  case "$1" in
    geometry) echo 0.995 ;;
    text-symbol) echo 0.970 ;;
    3d-buildings) echo 0.880 ;;
    *) echo 0.980 ;;
  esac
}

default_content_retention() {
  case "$1" in
    geometry|flutter-markers) echo 0 ;;
    *) echo 0.700 ;;
  esac
}

run_fixture maplibre_gl_app maplibre_gl
run_fixture gpu_app maplibre_flutter_gpu

(
  cd "$repository_root/e2e/visual/runner"
  dart pub get
)

suite_status=0
for scene in "${scenes[@]}"; do
  if [[ "${#scenes[@]}" -eq 1 ]]; then
    scene_output="$output"
    reference_capture="$capture_dir/maplibre_gl.png"
    gpu_capture="$capture_dir/gpu.png"
  else
    scene_output="$output/$scene"
    reference_capture="$capture_dir/maplibre_gl-$scene.png"
    gpu_capture="$capture_dir/gpu-$scene.png"
  fi
  images_dir="$scene_output/images"
  mkdir -p "$images_dir"
  rm -f \
    "$images_dir/maplibre_gl.png" \
    "$images_dir/gpu.png" \
    "$images_dir/diff.png" \
    "$scene_output/index.html" \
    "$scene_output/results.json"
  cp "$reference_capture" "$images_dir/maplibre_gl.png"
  cp "$gpu_capture" "$images_dir/gpu.png"

  scene_similarity="$minimum_similarity"
  if [[ -z "$scene_similarity" ]]; then
    scene_similarity="$(default_similarity "$scene")"
  fi
  scene_content_retention="$minimum_content_retention"
  if [[ -z "$scene_content_retention" ]]; then
    scene_content_retention="$(default_content_retention "$scene")"
  fi

  runner_args=(
    --skip-drive
    --platform iOS
    --scene "$scene"
    --output "$scene_output"
    --minimum-similarity "$scene_similarity"
    --minimum-content-retention "$scene_content_retention"
    --minimum-content-ratio "$minimum_content_ratio"
  )
  if [[ -n "$zoom" ]]; then
    runner_args+=(--zoom "$zoom")
  fi
  if [[ "$performance" == true ]]; then
    runner_args+=(
      --performance-reference "$output/performance/maplibre_gl.json"
      --performance-actual "$output/performance/maplibre_flutter_gpu.json"
    )
  fi

  set +e
  (
    cd "$repository_root/e2e/visual/runner"
    dart run bin/run_android.dart "${runner_args[@]}"
  )
  scene_status=$?
  set -e
  if [[ "$scene_status" -ne 0 && "$suite_status" -eq 0 ]]; then
    suite_status="$scene_status"
  fi
done

exit "$suite_status"
