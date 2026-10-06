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
record per case and repeat. Keep the app in the foreground at the same window
size and device pixel ratio for every revision. The app waits for focus and
retries measurements interrupted by a lifecycle change. A run fails after three
invalid attempts, including samples with fewer than five frames. Keep the
accessibility and semantics state the same for every variant. UI inspection can
cause the operating system to enable semantics, so avoid inspecting the app
during a sample. Each record includes `semanticsEnabled` for comparison. Do not
run builds, tests, or other CPU-heavy work concurrently with measurements.

The synthetic benchmark isolates Flutter symbol updates from native map work.
Its precomputed symbols share the text `Maple Road`, with optional halos, and
its anchors and paths cycle through 48 precomputed variants. Position cases
only request relayout. Transform and shape cases also update visual data.
Refresh cases replace the symbols with equivalent visual data. The
`path_offsets` and `path_halo_offsets` cases move glyphs along a path whose outer
extents stay fixed. They isolate placement updates that can avoid layout when
label and glyph sizes do not change. The shape cases also change label bounds.

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
output path. Each `SYMBOL_PROBE` record includes frame distributions in
milliseconds, element and render object counts, and whole-app layer counts.
Increase `PROBE_MEASURE_MS` for slow cases so each run collects several dozen
frames before comparing distributions.

The native map benchmark uses inline GeoJSON with 320 point labels or 224 road
labels and bundled glyphs served over loopback. It compares default and hidden
symbols during pan and combined bearing/pitch changes. Hidden cases retain
native placement. Each `MAP_PROBE` record includes frame distributions and
placed label counts before and after measurement. Zero labels invalidate the
sample. These counts describe native placements before Flutter viewport culling,
including hidden labels. The camera follows the same route over elapsed time,
while `cameraSteps` and frame counts can differ with rendering throughput.

```bash
flutter run -d macos --profile -t lib/symbol_map_benchmark.dart \
  --dart-define=MAP_PROBE_VARIANT=baseline \
  --dart-define=MAP_PROBE_CASES=point320_default_pan,line224_default_pan \
  --dart-define=MAP_PROBE_REPEATS=3
```

`MAP_PROBE_SECONDS` defaults to 3. Omit `MAP_PROBE_CASES` to include all eight
cases. `MAP_PROBE_OUTPUT` optionally names an absolute JSON output path.

For a method comparison, build each revision with identical case, count, timing,
and repeat settings. Save each variant's JSON output separately. Compare the
median of the per-repeat medians and inspect p95, raster time, label counts, and
sample sizes as well. Report synthetic and native results separately because
they exercise different workloads. Shared synthetic text exposes cache reuse
and does not represent the variety of a real map.

`ui_ms` measures `FrameTiming.buildDuration`, including layout and paint on the
UI thread, rather than only widget building. `raster_ms` measures raster-thread
work, not pure GPU execution. Do not add these medians or invert them to claim
an application frame rate.
