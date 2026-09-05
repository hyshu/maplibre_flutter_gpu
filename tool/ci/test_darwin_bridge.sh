#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
archive="${1:?Usage: test_darwin_bridge.sh /absolute/path/libMapLibreBridge.a}"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
cd "${project_root}"

clang++ -std=c++20 native/tests/style_error_integration_test.cpp "${archive}" \
    -o "${work_dir}/style_error_test" \
    -framework AppKit -framework CFNetwork -framework CoreGraphics \
    -framework CoreImage -framework CoreLocation -framework CoreText \
    -framework Foundation -framework Security -framework SystemConfiguration \
    -lsqlite3 -lz
"${work_dir}/style_error_test"
