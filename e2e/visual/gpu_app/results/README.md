# Benchmark results

Reference outputs of `symbol_benchmark.dart` and `symbol_map_benchmark.dart`
for comparing later revisions on the same machine. Compare a candidate run
against a file here with `dart run bin/compare_symbol_probes.dart` from
`e2e/visual/runner`. Numbers from other machines are not comparable.

Machine: Apple M1 Pro, macOS 27.0.1, Flutter 3.47.7, 800x600 logical at device pixel
ratio 2, Impeller Metal, semantics off unless the file name says otherwise.

| File | Run |
| --- | --- |
| `macos-synthetic-baseline.json` | all synthetic cases, counts 200 and 800, 4000 ms samples, 3 repeats |
| `macos-native-baseline.json` | all twenty native cases, 3 repeats |
| `macos-native-baseline-icons.json` | `MAP_PROBE_ICONS=true`, point cases |
| `macos-native-baseline-icons-translucent.json` | icons at `MAP_PROBE_ICON_OPACITY=0.85` |
| `macos-native-baseline-semantics.json` | `MAP_PROBE_SEMANTICS=true`, pan and rotate cases |
| `macos-native-baseline-cjk.json` | `MAP_PROBE_TEXT=cjk`, pan, zoom, rotate, and tilt zoom cases |
| `macos-native-baseline-fade.json` | `MAP_PROBE_FADE_MS=150`, pan cases |
| `macos-native-baseline-layers4.json` | `MAP_PROBE_LAYERS=4`, pan cases |
| `macos-native-baseline-semantics-tap.json` | semantics with `MAP_PROBE_TAP=true`, pan cases, before the single-node labels change |
| `macos-native-perf-branch.json` | all twenty native cases after the default symbol performance changes |
| `macos-synthetic-perf-branch.json` | all synthetic cases after the default symbol performance changes |
| `macos-native-perf-branch-cjk.json` | `MAP_PROBE_TEXT=cjk` after the changes |
| `macos-native-perf-branch-semantics.json` | `MAP_PROBE_SEMANTICS=true` after the changes |
| `macos-native-perf-branch-icons.json` | `MAP_PROBE_ICONS=true` after the changes |
| `macos-native-point-labels.json` | all twenty native cases after point labels moved to the glyph atlas |
| `macos-native-point-labels-cjk.json` | `MAP_PROBE_TEXT=cjk` after point labels moved to the glyph atlas |
| `macos-synthetic-point-labels.json` | all synthetic cases after point labels moved to the glyph atlas |

The baseline files were recorded at commit bd19403 and the perf-branch files
after the changes that followed it on the same branch, so comparing the two
sets shows the effect of those changes on this machine. The point-labels
files were recorded in a later session. Runs from different sessions drift
by around twenty percent on this machine, so a change is best judged from
runs recorded back to back, for example by alternating a baseline worktree
and the working tree.

## Device runs with a remote style

`MAP_PROBE_STYLE=liberty` replaces the inline fixture with the OpenFreeMap
Liberty style over the network. The `style_*` cases pan, rotate, and tilt over
Tokyo at zoom 14.1, where the style draws roughly 350 native commands,
fill-extrusion buildings, and about 130 to 210 placed symbols. Network tile
loading can affect the first repeat of a session. Each record's `counters`
include the GPU preparation and recording counters: `gpuPrepareMicros`,
`gpuRecordMicros`, `gpuDraws`, `gpuRenderPasses`, and `gpuStrata`.

The XIG02 renders this scene GPU bound at roughly 22 ms per frame, so its
`raster_ms` reports how long the raster thread waited for the GPU once the UI
thread got faster rather than added raster work. Compare `frames` per sample
between its files instead.

| File | Device | Run |
| --- | --- | --- |
| `android-xig02-liberty-baseline.json` | XIG02, Android 13, 393x825 at ratio 2.75 | pan, rotate and tilt, tilt and zoom, hidden pan, hidden tilt and zoom, 3 repeats, before the render pipeline changes |
| `ios-iphone12mini-liberty-baseline.json` | iPhone 12 mini, iOS 27.0.1, 375x812 at ratio 3 | the same cases before the render pipeline changes |
| `ios-iphone12mini-liberty-async.json` | iPhone 12 mini | the same cases after asynchronous rendering was enabled on every platform |
| `ios-iphone12mini-liberty-native-repack.json` | iPhone 12 mini | the same cases after native vertex conversion was enabled on every platform |
| `ios-iphone12mini-liberty-single-pass.json` | iPhone 12 mini | the same cases after logical passes were recorded into one native render pass on Metal |
| `android-xig02-liberty-tile-lod-shift.json` | XIG02 | rotate and tilt, tilt and zoom, 2 repeats, with `MAP_PROBE_TILE_LOD_PITCH=20`, `MAP_PROBE_TILE_LOD_MIN_RADIUS=0`, and `MAP_PROBE_TILE_LOD_ZOOM_SHIFT=-1`, which drops the native command count from about 354 to 122 and hides the zoom 14 building layer |
| `android-xig02-liberty-tile-batching.json` | XIG02 | all ten `style_*` cases, 3 repeats, after tile batching, which cuts the native command count from 348 to 145 and the pan UI median from 14.2 to 11.5 ms |
| `android-xig02-liberty-tile-batching-off.json` | XIG02 | the same cases recorded minutes earlier from the same build with `MAPLIBRE_TILE_BATCHING=false`, the control for the batching file |
| `ios-iphone12mini-liberty-tile-batching.json` | iPhone 12 mini | all ten `style_*` cases, 3 repeats, after tile batching, which cuts the pan UI median from 4.4 to 3.8 ms and recording from 1.9 to 1.3 ms at an unchanged raster time |
| `ios-iphone12mini-liberty-tile-batching-off.json` | iPhone 12 mini | the same cases recorded minutes later from the same build with `MAPLIBRE_TILE_BATCHING=false`, the control for the batching file |
