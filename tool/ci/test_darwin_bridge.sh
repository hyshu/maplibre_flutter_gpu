#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
archive="${1:?Usage: test_darwin_bridge.sh /absolute/path/libMapLibreBridge.a}"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
cd "${project_root}"
source native/scripts/packaging/darwin_common.sh

for test in style_error frame_scheduling; do
    clang++ -std=c++20 -fno-rtti \
        -DMLN_RENDER_BACKEND_COMMAND_EXPORT=1 -DMLN_USE_UNORDERED_DENSE=1 \
        -I native/src "${BRIDGE_INCLUDE_ARGS[@]}" \
        "native/tests/${test}_integration_test.cpp" "${archive}" \
        -o "${work_dir}/${test}_test" \
        -framework AppKit -framework CFNetwork -framework CoreGraphics \
        -framework CoreImage -framework CoreLocation -framework CoreText \
        -framework Foundation -framework Security -framework SystemConfiguration \
        -lsqlite3 -lz
    "${work_dir}/${test}_test"
done
