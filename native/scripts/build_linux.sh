#!/usr/bin/env bash
# Build, verify, and install the Linux FlutterGPU bridge.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${NATIVE_ROOT}/.." && pwd)"
BUILD_DIR="${MAPLIBRE_LINUX_BUILD_DIR:-${PROJECT_ROOT}/build-linux-fluttergpu}"
VERIFY_SCRIPT="${PROJECT_ROOT}/tool/ci/verify_desktop_artifact.py"

case "$(uname -m)" in
    x86_64) ARCHITECTURE_DIR='x64' ;;
    *)
        echo "error: unsupported Linux architecture: $(uname -m)" >&2
        exit 1
        ;;
esac
OUTPUT_DIR="${PROJECT_ROOT}/linux/${ARCHITECTURE_DIR}"
OUTPUT="${OUTPUT_DIR}/libmaplibre_bridge.so"

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required tool not found: $1" >&2
        exit 1
    fi
}

verify_bridge() {
    python3 "${VERIFY_SCRIPT}" --platform linux --library "$1"
}

if [[ "${1:-}" == "--verify-only" ]]; then
    require_tool nm
    require_tool python3
    verify_bridge "${2:-${OUTPUT}}"
    exit 0
fi

INSTALL_OUTPUT=1
if [[ "${1:-}" == "--no-install" ]]; then
    INSTALL_OUTPUT=0
    shift
fi
if [[ $# -ne 0 ]]; then
    echo "usage: $0 [--no-install | --verify-only [path]]" >&2
    exit 2
fi
if [[ "$(uname -s)" != "Linux" ]]; then
    echo "error: Linux bridge must be built on Linux" >&2
    exit 1
fi

require_tool cmake
require_tool ninja
require_tool nm
require_tool python3

if [[ ! -f "${PROJECT_ROOT}/vendor/maplibre-native/CMakeLists.txt" ]]; then
    echo "error: MapLibre Native submodule is missing" >&2
    echo "Run git submodule update --init --recursive." >&2
    exit 1
fi

echo "Configuring Linux FlutterGPU bridge..."
cmake \
    -S "${NATIVE_ROOT}/platforms/linux" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"

echo "Building Linux FlutterGPU bridge..."
cmake --build "${BUILD_DIR}" --target maplibre_bridge --parallel

CANDIDATE="${BUILD_DIR}/libmaplibre_bridge.so"
verify_bridge "${CANDIDATE}"

if [[ ${INSTALL_OUTPUT} -eq 0 ]]; then
    echo "Built and verified without replacing ${OUTPUT}: ${CANDIDATE}"
    exit 0
fi

# Replace the packaged artifact only after verification succeeds.
mkdir -p "${OUTPUT_DIR}"
TEMP_OUTPUT="${OUTPUT}.tmp.$$"
trap 'rm -f "${TEMP_OUTPUT}"' EXIT
install -m 0755 "${CANDIDATE}" "${TEMP_OUTPUT}"
mv -f "${TEMP_OUTPUT}" "${OUTPUT}"
trap - EXIT

echo "Built: ${OUTPUT}"
ls -lh "${OUTPUT}"
