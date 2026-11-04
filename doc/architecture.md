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

## Android label update diagnostics

`--dart-define=MAPLIBRE_LABEL_UPDATE_DIAGNOSTICS=true` enables classification
after each label projection on Android. It is disabled by default. The internal
`LabelUpdateDiagnostics.snapshot()` API returns cumulative isolate counters.
It does not change rendering or the decision to rebuild symbol overlays.

Each map retains only its previous copied scalar snapshot. Nested font,
formatting, and path values are copied. No placement object, atlas, image,
native buffer, or GPU resource is retained. Reset discards the map's comparison
baseline while preserving cumulative counters.

The classifier compares the complete ordered label set and each layer in the
union of previous and current layers. Allowed anchor changes are geographic
coordinates, native center offsets, and projected positions. Membership,
component availability, order, fading, style, content, atlas identity, affine
transforms, sizes, and paths reject anchor-only classification. Even data for
absent components is compared, making this a conservative opportunity check.

Observations are label projections, not presented frames or overlay builds.
Layers have independent outcomes, and rejection reasons can overlap. Eligible
observations do not establish unchanged culling, GPU stratum topology, or custom
builder output. The `nativeChanged` counter families restrict comparisons to
changed native placement versions, excluding projections that already use the
position-only update path. Entry totals weight outcomes by current reconciled
label counts, including fading labels. Record cumulative reads at measurement
boundaries and keep these results separate from clean performance runs.
`comparisonMicros` measures
elapsed capture, comparison, and tally work, not CPU utilization.

## Android tile observer diagnostics

The Android CMake option `MAPLIBRE_ANDROID_TILE_DIAGNOSTICS` defaults to `OFF`.
Set it to `ON` when configuring a diagnostic native build to log tile events
from `SimpleObserver::onTileAction`. The definition applies only to the bridge
target. It does not change native core settings, cache policy, or repaint
behavior. When disabled, the formatter and observer trace state are excluded
from compilation. Restore `OFF` explicitly when reusing a diagnostic CMake
build directory.

Each `MapTileTrace` Android log message contains one JSON object with schema
version 1. All tile operations are recorded before the observer's existing
`EndParse` handling.

| Fields | Meaning |
| --- | --- |
| `session`, `event` | A unique observer serial within the process and its event sequence, starting at 1. Serials do not depend on allocator addresses. |
| `time_ns`, `clock_ok` | `CLOCK_MONOTONIC` nanoseconds at the observer callback. A failed clock read reports zero and `false`. |
| `operation`, `op` | The operation name and numeric `TileOperation` value, including cancellation, errors, and `NullOp`. |
| `z`, `x`, `y`, `overscaled_z`, `wrap` | The canonical and overscaled tile identity. Keep the source and session when grouping events. |
| `source_hex`, `source_bytes`, `source_truncated` | Lowercase hexadecimal source bytes, the original byte length, and whether the 512-byte encoding limit was exceeded. Hex preserves arbitrary identifiers on one bounded log line. |

Reject truncated source identities and failed clock reads when correlating
events. Check event sequences for missing records. A contiguous observed
sequence does not prove that the beginning or end of a capture is complete.
The observer serial identifies a map observer, not a style revision or tile
request generation.

`RequestedFromCache` and `LoadFromCache` describe the raw FileSource cache.
They do not report hits in the decoded tile retention cache. A cache request
can be followed by a network request in the same load cycle, and a network
response can be unchanged without triggering parsing. `StartParse` can follow
either new data or changed layers and is coalesced while work is pending.
`EndParse` marks an accepted layout result. These notifications neither count
every worker parse nor prove that repeated tile IDs used identical payloads.
Their intervals include scheduling and dependencies, so they are not worker
CPU durations.

Keep these recordings separate from performance measurements. Logging adds
work, and CPU values from a trace build must not be used to claim a performance
improvement or regression.
