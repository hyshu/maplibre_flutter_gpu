# GPU E2E fixture

Visual and performance fixture app for `maplibre_flutter_gpu`. Run the visual
tests through the parent E2E runner. This is not a standalone product example.

Run the deterministic macOS heatmap scene from the repository root.

```bash
bash e2e/visual/run_macos.sh --scene heatmap
```

The scene compares an isolated point, four coincident points, a double-weight
point, and two radii driven by feature properties and zoom. It also renders a
second heatmap between two circle layers. Pixel checks verify accumulated
density, the color ramp, intensity, opacity, Gaussian falloff, and layer order.
Command coverage requires both heatmap passes and render-target commands.

The lifecycle test checks pixels after camera changes, resizing, style
replacement, zero opacity, and empty sources. It also checks two heatmap layers
separated by a placed Flutter symbol, using bundled glyphs through the local
fixture server, plus runtime layer creation and paint updates through the
controller. Failures save a PNG under `build/heatmap-validation/lifecycle`.

```bash
cd e2e/visual/gpu_app
flutter test integration_test/heatmap_lifecycle_test.dart -d macos
```

The hillshade scene serves a generated DEM through the local fixture server.
Its plateau and three directional slopes have known elevations, encoded in
both Mapbox and Terrarium PNGs. The lifecycle test checks expected pixels for
all five shading methods, four lights, reversed illumination, viewport and map
anchors, zero exaggeration, layer removal and recreation, shared DEM sources,
style reloads, resizing, overzoom, and heatmap composition over terrain. The
mixed frame checks both RGBA8 and RGBA16F offscreen passes. Failures save a PNG under
`build/hillshade-validation/lifecycle`.

```bash
cd e2e/visual/gpu_app
flutter test integration_test/hillshade_lifecycle_test.dart -d macos
```

Capture the standalone scene from the repository root without requiring an
image baseline.

```bash
bash e2e/visual/run_macos.sh --scene hillshade --allow-missing-baseline
```

Regenerate the DEM fixtures from the runner directory.

```bash
cd e2e/visual/runner
dart run bin/generate_hillshade_tiles.dart --output-directory ../shared/assets/resources
```

## Default symbol benchmarks

The standalone entry points require profile mode and exit after writing one JSON
record per case and repeat. Keep the app visible at the same window size and
device pixel ratio for every revision. On macOS, launch with the environment
variable `VISUAL_E2E_FLOATING=1` to keep the window above other windows and on
every Space, so other work does not occlude it. An occluded or paused app stops
producing frames, so the app waits until it is visible again and retries the
interrupted sample. A case is skipped after six invalid attempts, including
samples with fewer than five frames, and the JSON output is rewritten after
every accepted record. Keep the accessibility and semantics state the same for
every variant. UI inspection can cause the operating system to enable
semantics, so avoid inspecting the app during a sample. Each record includes
`semanticsEnabled` and the lifecycle states observed during the sample. Do not
run builds, tests, or other CPU-heavy work concurrently with measurements.

The synthetic benchmark isolates Flutter symbol updates from native map work.
Its precomputed symbols share the text `Maple Road`, with optional halos, and
its anchors and paths cycle through 48 precomputed variants. Position cases
only request relayout. Transform and shape cases also update visual data.
Refresh cases replace the symbols with equivalent visual data. The
`path_offsets` and `path_halo_offsets` cases move glyphs along a path whose outer
extents stay fixed. They isolate placement updates that can avoid layout when
label and glyph sizes do not change. The shape cases also change label bounds.
The `point_halo_size` and `path_halo_size` cases cycle the font size between
12.75 and 13.25 so every text cache key changes, as zoom-interpolated text
sizes do on a real map. `point_distinct` refreshes symbols that each carry a
unique string. `path_halo_blur_shape` adds a one pixel halo blur. The
`icons_transform` case rotates raster icons, and the `icons_sdf_halo_*` cases
draw a signed distance field circle with a halo.

```bash
cd e2e/visual/gpu_app
flutter run -d macos --profile -t lib/symbol_benchmark.dart \
  --dart-define=PROBE_VARIANT=baseline \
  --dart-define=PROBE_COUNTS=200,800 \
  --dart-define=PROBE_CASES=point_halo_transform,path_halo_shape \
  --dart-define=PROBE_REPEATS=3
```

`PROBE_MEASURE_MS` defaults to 2000 and `PROBE_WARMUP_MS` to 750. Omit
`PROBE_CASES` to run all cases. `PROBE_OUTPUT` optionally names an absolute JSON
output path. `PROBE_SEMANTICS=true` enables the semantics tree before the first
frame. Each `SYMBOL_PROBE` record includes frame distributions in milliseconds,
element and render object counts, whole-app layer counts, and the symbol
pipeline counters described below. Increase `PROBE_MEASURE_MS` for slow cases
so each run collects several dozen frames before comparing distributions.

The native map benchmark uses inline GeoJSON with 320 point labels or 224 road
labels and bundled glyphs served over loopback. It compares default and hidden
symbols during five camera routes: `pan`, `rotateTilt` (bearing and pitch),
`zoom`, `pitchOnly`, and `tiltZoom`. The two zoom routes oscillate between zoom
13.5 and 14.5 with a zoom-interpolated `text-size`, so every zoom frame changes
the evaluated font size. Hidden cases retain native placement. Each `MAP_PROBE`
record includes frame distributions, vsync overhead, placed symbol counts
before and after measurement, the style knobs, and the pipeline counters. Zero
symbols invalidate the sample. These counts describe native placements before
Flutter viewport culling, including hidden labels. The camera follows the same
route over elapsed time, while `cameraSteps` and frame counts can differ with
rendering throughput.

```bash
flutter run -d macos --profile -t lib/symbol_map_benchmark.dart \
  --dart-define=MAP_PROBE_VARIANT=baseline \
  --dart-define=MAP_PROBE_CASES=point320_default_pan,line224_default_pan \
  --dart-define=MAP_PROBE_REPEATS=3
```

`MAP_PROBE_SECONDS` defaults to 3. Omit `MAP_PROBE_CASES` to include all
twenty cases. `MAP_PROBE_OUTPUT` optionally names an absolute JSON output path.

Style knobs apply to every case of a run and are recorded in each record.
`MAP_PROBE_HALO_WIDTH` (default 1) and `MAP_PROBE_HALO_BLUR` (default 0) set the
text halo. `MAP_PROBE_FADE_MS` (default 0) sets the symbol fade duration and
switches the layers to collision placement, so labels appear and disappear
while the camera moves. `MAP_PROBE_TEXT` selects `latin` (default), `cjk`
(a unique three character name per feature from the bundled NotoCJK ranges),
or `cjk-vertical`. `MAP_PROBE_LAYERS` (default 1) splits the features across
that many symbol layers separated by native line layers, so interleaved
compositing uses one GPU stratum per symbol layer. `MAP_PROBE_ICONS=true` adds
a signed distance field sprite with a halo to every symbol, drawn at
`MAP_PROBE_ICON_OPACITY` (default 1).
`MAP_PROBE_SEMANTICS=true` enables the semantics tree before the first frame,
and `MAP_PROBE_TAP=true` installs a map tap handler, which merges symbol
semantics into the map's gesture node. `MAP_PROBE_CHROME=true` wraps the map
in a Material scaffold with an app bar and enables the map controls, so
repaint propagation outside the map is part of the measurement.

Both benchmarks reset the package's profile-mode symbol counters before each
sample and store them under `counters`. `fullSymbolUpdates` and
`relayoutUpdates` count map frames that rebuilt every overlay or only moved
existing children. `nativeRenderCalls`, `labelSyncMicros`, and
`labelProjectionMicros` describe native frame reads. `textVisualMisses`,
`iconVisualMisses`, and `transformOnlyMisses` count default widgets rebuilt
because their style data changed, and how many of those differed only in an
affine transform. `relayoutSetStates` counts position-only updates that still
rebuilt an overlay because a component crossed the culling boundary.

`dart run bin/compare_symbol_probes.dart` in `e2e/visual/runner` prints one row
per case from a JSON output file and, given a second file, the candidate delta
against the baseline. Native rows include the counters per camera step.
Baseline outputs for this machine live under `results/`.

For a method comparison, build each revision with identical case, count, timing,
and repeat settings. Save each variant's JSON output separately. Compare the
median of the per-repeat medians and inspect p95, raster time, label counts, and
sample sizes as well. On displays faster than 60 Hz the native medians mix
camera-step frames with cheaper repaint frames, so compare p95 for the camera
frame cost. Report synthetic and native results separately because they
exercise different workloads. Shared synthetic text exposes cache reuse and
does not represent the variety of a real map.

`ui_ms` measures `FrameTiming.buildDuration`, including layout and paint on the
UI thread, rather than only widget building. `raster_ms` measures raster-thread
work, not pure GPU execution. Do not add these medians or invert them to claim
an application frame rate.
