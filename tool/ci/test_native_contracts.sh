#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
cd "${project_root}"

javac -d "${work_dir}" \
    android/src/main/java/org/maplibre/android/http/NativeHttpRequest.java \
    native/tests/CancelRace.java
java -cp "${work_dir}" CancelRace

# Compile the exported implementation against a worker-thread owner adapter.
python3 - "${work_dir}/style_last_error.inc" <<'PY'
import pathlib
import sys
source = pathlib.Path('native/src/bridge_style.cpp').read_text()
start = source.index('MAPLIBRE_API const char *maplibre_style_last_error(void) {')
end = source.index('\nMAPLIBRE_API ', start + 1)
pathlib.Path(sys.argv[1]).write_text(source[start:end])
PY
"${CXX:-c++}" -std=c++20 -pthread -I "${work_dir}" \
    native/tests/style_error_test.cpp -o "${work_dir}/style_error_test"
"${work_dir}/style_error_test"

"${CXX:-c++}" -std=c++20 -I native/src \
    native/tests/repaint_budget_test.cpp -o "${work_dir}/repaint_budget_test"
"${work_dir}/repaint_budget_test"
