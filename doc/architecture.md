# Source layout

The public Dart entry point is `lib/maplibre_flutter_gpu.dart`. It exposes map
widgets, controllers, camera values, symbols, and sprite APIs. Implementation
libraries live under `lib/src`. Parts keep private implementation types inside
their owning library while separating responsibilities into files.

| Location | Responsibility |
| --- | --- |
| `lib/src/controller/` | Application camera and style operations. |
| `lib/src/geo/` | Camera values, geographic bounds, and constraints. |
| `lib/src/state/` | Viewport changes, style sessions, render scheduling, and gestures. |
| `lib/src/widgets/map/` | Map lifecycle, layer composition, gesture region, and GPU image ownership. |
| `lib/src/widgets/controls/` | Control options, attribution, compass, logo, and scale bar presentation. |
| `lib/src/widgets/symbols/` | Symbol identity, fades, projection, layout, text, and icon rendering. |
| `lib/src/labels/` | Placement snapshots, reconciliation, and ordering of symbol and GPU layers. |
| `lib/src/sprites/` | Atlas loading, icon metadata, stretch geometry, and sprite painting. |
| `lib/src/frame/` | Draw-command admission, GPU state, pass planning, uniform packing, and vertex formats. |
| `lib/src/gpu/` | Command decoding, resource uploads, uniforms, prepared graphs, caches, and pass execution. |
| `lib/src/native/bindings/` | FFI operations grouped by native capability. |
| `lib/src/native/labels/` | Binary label records, cached static content, placement data, and blob decoding. |
| `native/src/` | Native session lifecycle, camera operations, projection, frame publication, and style mutation. |
| `native/src/labels/` | Label ABI definitions, encoding, session caches, and publication. |
| `e2e/visual/shared/lib/src/` | Visual test configuration, scenes, local assets, font setup, capture, and performance probes. |

The map state owns the bridge, renderer, controller, and compositing resources.
The renderer coordinates command decoding, resource caches, uniform uploads,
and render passes. Decoded command views borrow native memory and must remain
inside the acquired frame snapshot's lifetime. The final GPU stratum releases
the shared snapshot after all strata have recorded their work.

Label content and placement have different lifetimes. Static records cache
strings, formatting, and evaluated style values. Placement records supply
frame-specific anchors, paths, and transforms. Full static decoding and scalar
refresh share the same scalar reader, so their field mappings stay aligned.

`native/cmake/bridge_sources.cmake` and
`native/scripts/packaging/darwin_common.sh` list native compilation units.
`tool/gen_abi.dart` reads the native ABI definitions and generates
`lib/src/native/abi_generated.dart`. Update these together when moving native
sources or changing binary layouts.

Behavior tests live in `test/` and each example or visual harness package.
Native, shader, and ABI contracts that require source inspection use the narrow
file sets in `test/support/source_files.dart`. Update the relevant set when
moving its implementation. `tool/ci/quality.sh` runs package tests, coverage,
formatting, and analysis across the repository.
