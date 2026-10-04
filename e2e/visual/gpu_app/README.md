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
