# Measurement and reporting rules

Every agent session in this harness receives this file. It records how this
project decides whether a change is an improvement. The rules come from
`maplibre_compare/README.md` and from `AGENTS.md` in this repository.

## What counts as evidence

1. A performance claim needs the same device, build mode, map size, device
   pixel ratio, scene and warmup for both sides of the comparison, with at
   least three runs of each configuration.
2. Alternate the order of configurations across runs, and alternate the order of
   the GL and GPU implementations. Compare the median of the per-run p50 and
   p95 values, not a single run.
3. Startup time and memory comparisons need a fresh process for each side,
   because a shared process keeps the earlier implementation's caches.
4. Hold temperature, charging state, brightness, refresh rate and
   accessibility settings equal. Do not build, test, record the screen or run a
   high frequency profiler during a measurement.
5. Confirm the drawn content and camera tracking at the route landmarks. A
   result that comes from dropped labels, missing layers or stalled updates is a
   defect, never an improvement.
6. Record the source commit, the MapLibre Native revision, and the SHA-256 of
   the binaries and shaders used. Measurements taken with a prebuilt binary and
   measurements taken with a rebuilt one are not the same baseline.
7. An Android or Vulkan only change does not need an iOS re-measurement. A
   change to shared Dart or native code does.

## What may not be claimed

- No general speed or memory improvement from a mixed result. If the per pair
  differences do not point the same way, say so and keep the flag default off.
- No comparison between runs that used different scene, viewport mode, map
  logical size or device pixel ratio.
- No treating a diagnostic counter reduction as a rendering improvement.
- No treating a single run, or a run whose idle state before measurement was
  not observed, as a statistical result. Record the condition instead.
- No claim about a cause that the measurement does not separate from the other
  changes present in the same binary.

## Reporting style

- State what the measurement shows, then state plainly what it does not show.
- Prefer concrete numbers with their units over adjectives.
- Avoid em dashes, semicolons and label style colons in prose. Write complete
  sentences.
- Keep the default of a new flag off unless the measurements support turning it
  on, and say which measurement supports the decision.

## Review output rules

- Report a defect only when you can name the input or state that triggers it.
- Separate a confirmed defect, where you traced the path, from a plausible one,
  where a path you could not read fully might still handle it.
- Do not report a style issue as a correctness defect, and do not report
  anything outside the branch diff.
