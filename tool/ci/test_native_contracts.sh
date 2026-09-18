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
python3 - "${work_dir}" <<'PY'
import pathlib
import re
import sys
work_dir = pathlib.Path(sys.argv[1])
source = pathlib.Path('native/src/bridge_style.cpp').read_text()
start = source.index('MAPLIBRE_API const char *maplibre_style_last_error(void) {')
end = source.index('\nMAPLIBRE_API ', start + 1)
(work_dir / 'style_last_error.inc').write_text(source[start:end])

def function(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

frames = '\n'.join(pathlib.Path(path).read_text() for path in (
    'native/src/bridge_frame.cpp',
    'native/src/frame/async_renderer.cpp',
))
lifecycle = pathlib.Path('native/src/maplibre_bridge.cpp').read_text()
(work_dir / 'frame_scheduling.inc').write_text(
    function(frames, 'void bridge_finishRenderOnOwner() {') + '\n' +
    function(lifecycle, 'void bridge_resetRepaintBudget() {') + '\n' +
    function(frames, 'static bool enqueueAsyncRenderTask() {') + '\n')
async_render = re.search(r'static void runAsyncRenderOnOwner\([^;{}]*\)\s*\{', frames)
assert async_render is not None
for signature in (async_render.group(),
                  'MAPLIBRE_API int maplibre_render_frame(void) {'):
    body = function(frames, signature)
    rendered = body.index('g_frontend->renderFrame();')
    scheduled = body.index('bridge_finishRenderOnOwner();')
    published = body.index('endCommandFrameOnOwner(')
    assert rendered < scheduled < published, signature
PY
"${CXX:-c++}" -std=c++20 -pthread -I "${work_dir}" \
    native/tests/style_error_test.cpp -o "${work_dir}/style_error_test"
"${work_dir}/style_error_test"

"${CXX:-c++}" -std=c++20 -I native/src \
    native/tests/repaint_budget_test.cpp -o "${work_dir}/repaint_budget_test"
"${work_dir}/repaint_budget_test"

"${CXX:-c++}" -std=c++20 -I native/src -I "${work_dir}" \
    native/tests/frame_scheduling_test.cpp -o "${work_dir}/frame_scheduling_test"
"${work_dir}/frame_scheduling_test"
