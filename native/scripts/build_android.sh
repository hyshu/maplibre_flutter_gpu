#!/usr/bin/env bash
# Build and install the Android FlutterGPU bridge for one 64-bit ABI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${NATIVE_ROOT}/.." && pwd)"

ABI="${1:-arm64-v8a}"
case "${ABI}" in
    arm64-v8a|x86_64)
        ;;
    *)
        echo "error: supported ABIs: arm64-v8a, x86_64" >&2
        exit 64
        ;;
esac

SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "${SDK_ROOT}" && "$(uname -s)" == "Darwin" ]]; then
    SDK_ROOT="${HOME}/Library/Android/sdk"
fi
if [[ -z "${SDK_ROOT}" || ! -d "${SDK_ROOT}" ]]; then
    echo "error: set ANDROID_SDK_ROOT to an installed Android SDK" >&2
    exit 1
fi

NDK_VERSION="${MAPLIBRE_ANDROID_NDK_VERSION:-28.2.13676358}"
NDK_ROOT="${SDK_ROOT}/ndk/${NDK_VERSION}"
TOOLCHAIN="${NDK_ROOT}/build/cmake/android.toolchain.cmake"
if [[ ! -f "${TOOLCHAIN}" ]]; then
    echo "error: Android NDK ${NDK_VERSION} not found under ${SDK_ROOT}/ndk" >&2
    exit 1
fi

for tool in cmake ninja; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "error: ${tool} is required" >&2
        exit 1
    fi
done

BUILD_DIR="${MAPLIBRE_ANDROID_BUILD_DIR:-${PROJECT_ROOT}/build-android-fluttergpu-${ABI}}"
OUTPUT_DIR="${PROJECT_ROOT}/android/src/main/jniLibs/${ABI}"
OUTPUT="${OUTPUT_DIR}/libmaplibre_bridge.so"

echo "Configuring Android FlutterGPU bridge (${ABI})..."
cmake \
    -S "${NATIVE_ROOT}/platforms/android" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}" \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
    -DANDROID_ABI="${ABI}" \
    -DANDROID_PLATFORM=android-29 \
    -DANDROID_STL=c++_static

echo "Building Android FlutterGPU bridge (${ABI})..."
cmake --build "${BUILD_DIR}" --target maplibre_bridge --parallel

CANDIDATE="${BUILD_DIR}/libmaplibre_bridge.so"
if [[ ! -f "${CANDIDATE}" ]]; then
    echo "error: bridge not found: ${CANDIDATE}" >&2
    exit 1
fi

LLVM_NM="${NDK_ROOT}/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-nm"
LLVM_STRIP="${NDK_ROOT}/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-strip"
if [[ "$(uname -s)" == "Linux" ]]; then
    LLVM_NM="${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
    LLVM_STRIP="${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
fi
if [[ ! -x "${LLVM_NM}" ]]; then
    echo "error: llvm-nm not found in Android NDK" >&2
    exit 1
fi
if [[ ! -x "${LLVM_STRIP}" ]]; then
    echo "error: llvm-strip not found in Android NDK" >&2
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"
TEMP_OUTPUT="${OUTPUT}.tmp.$$"
trap 'rm -f "${TEMP_OUTPUT}"' EXIT
install -m 0755 "${CANDIDATE}" "${TEMP_OUTPUT}"
"${LLVM_STRIP}" --strip-unneeded "${TEMP_OUTPUT}"

REQUIRED_SYMBOLS=(
    JNI_OnLoad
    maplibre_session_create
    maplibre_session_release
    maplibre_session_select
    maplibre_async_render_supported
    maplibre_destroy
    maplibre_frame_acquire
    maplibre_frame_begin
    maplibre_frame_end
    maplibre_frame_get_command_count
    maplibre_frame_get_map_transform
    maplibre_frame_get_metadata
    maplibre_frame_get_commands
    maplibre_frame_needs_repaint
    maplibre_frame_release
    maplibre_get_camera
    maplibre_init
    maplibre_process_events
    maplibre_render_frame
    maplibre_render_frame_async
    maplibre_set_render_request_callback
    maplibre_set_camera_full
    maplibre_set_max_pitch
    maplibre_set_content_insets_with_duration
    maplibre_set_min_pitch
    maplibre_style_get_source_attributions
    maplibre_style_set
)
EXPORTED="$("${LLVM_NM}" --dynamic --defined-only --extern-only "${TEMP_OUTPUT}" | awk '{print $NF}')"
for symbol in "${REQUIRED_SYMBOLS[@]}"; do
    if ! grep -Fqx "${symbol}" <<<"${EXPORTED}"; then
        echo "error: stripped bridge does not export ${symbol}" >&2
        exit 1
    fi
done

mv -f "${TEMP_OUTPUT}" "${OUTPUT}"
trap - EXIT

echo "Built and verified: ${OUTPUT}"
ls -lh "${OUTPUT}"
