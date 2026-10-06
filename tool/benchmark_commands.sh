#!/usr/bin/env bash
set -euo pipefail

# Measures native rendering and command publication without Flutter or network I/O.
# Reported command bytes include command headers and their separate payload arena.
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="${1:?Usage: benchmark_commands.sh /absolute/path/archive.a output-directory [runs] [layer-copies] [round-trips]}"
output_directory="${2:?An output directory is required}"
runs="${3:-3}"
layer_copies="${4:-16}"
round_trips="${5:-100}"

if [[ ! "${runs}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Run count must be a positive integer." >&2
    exit 64
fi
if [[ "$(uname -s)" != Darwin ]]; then
    echo "This benchmark links a macOS native archive." >&2
    exit 64
fi
mkdir -p "${output_directory}"
output_directory="$(cd "${output_directory}" && pwd)"
cd "${project_root}"
clang++ -std=c++20 -O3 -fno-rtti \
    -I native/src -isystem vendor/maplibre-native/vendor/rapidjson/include \
    native/benchmarks/command_frame_benchmark.cpp "${archive}" \
    -o "${output_directory}/command_frame_benchmark" \
    -framework AppKit -framework CFNetwork -framework CoreGraphics \
    -framework CoreImage -framework CoreLocation -framework CoreText \
    -framework Foundation -framework Security -framework SystemConfiguration \
    -lsqlite3 -lz

for ((run = 1; run <= runs; run += 1)); do
    "${output_directory}/command_frame_benchmark" \
        "${project_root}/e2e/visual/shared/assets/scenes/geometry.json" \
        "${output_directory}/native-${run}.json" "${layer_copies}" "${round_trips}" \
        >"${output_directory}/native-${run}.log" 2>&1
    cat "${output_directory}/native-${run}.json"
done
