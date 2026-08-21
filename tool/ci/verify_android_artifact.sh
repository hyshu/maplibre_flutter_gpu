#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 <arm64-v8a|x86_64>" >&2
    exit 64
fi

ABI="$1"
case "${ABI}" in
    arm64-v8a)
        EXPECTED_MACHINE='AArch64'
        ;;
    x86_64)
        EXPECTED_MACHINE='Advanced Micro Devices X86-64'
        ;;
    *)
        echo "error: unsupported Android ABI: ${ABI}" >&2
        exit 64
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIBRARY="${PROJECT_ROOT}/android/src/main/jniLibs/${ABI}/libmaplibre_bridge.so"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "${SDK_ROOT}" ]]; then
    SDK_ROOT="${HOME}/Library/Android/sdk"
fi
NDK_ROOT="${SDK_ROOT}/ndk/28.2.13676358"
READ_ELF="${NDK_ROOT}/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf"
LLVM_NM="${NDK_ROOT}/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-nm"

if [[ ! -s "${LIBRARY}" ]]; then
    echo "error: Android bridge is missing: ${LIBRARY}" >&2
    exit 1
fi
if [[ ! -x "${READ_ELF}" || ! -x "${LLVM_NM}" ]]; then
    echo "error: Android NDK 28.2.13676358 is missing under ${SDK_ROOT}" >&2
    exit 1
fi

ELF_HEADER="$("${READ_ELF}" -h "${LIBRARY}")"
if ! grep -Eq "Machine:[[:space:]]+${EXPECTED_MACHINE}$" <<<"${ELF_HEADER}"; then
    echo "error: ${LIBRARY} does not match ${ABI}" >&2
    exit 1
fi

PROGRAM_HEADERS="$("${READ_ELF}" -lW "${LIBRARY}")"
LOAD_ALIGNMENTS="$(awk '$1 == "LOAD" { print $NF }' <<<"${PROGRAM_HEADERS}")"
if [[ -z "${LOAD_ALIGNMENTS}" ]]; then
    echo "error: ${LIBRARY} has no LOAD segments" >&2
    exit 1
fi

while IFS= read -r alignment; do
    if (( alignment < 0x4000 )); then
        echo "error: ${LIBRARY} has LOAD alignment ${alignment}" >&2
        exit 1
    fi
done <<<"${LOAD_ALIGNMENTS}"

DYNAMIC_SECTION="$("${READ_ELF}" -d "${LIBRARY}")"
if grep -Fq 'libc++_shared.so' <<<"${DYNAMIC_SECTION}"; then
    echo "error: ${LIBRARY} unexpectedly depends on libc++_shared.so" >&2
    exit 1
fi

required_symbols=(
    JNI_OnLoad
    maplibre_session_create
    maplibre_session_release
    maplibre_session_select
    maplibre_bridge_feature_flags
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
exported_symbols="$(
    "${LLVM_NM}" --dynamic --defined-only --extern-only "${LIBRARY}" |
        awk '{ print $NF }'
)"
for symbol in "${required_symbols[@]}"; do
    if ! grep -Fqx "${symbol}" <<<"${exported_symbols}"; then
        echo "error: ${LIBRARY} does not export ${symbol}" >&2
        exit 1
    fi
done

ls -lh "${LIBRARY}"
