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
