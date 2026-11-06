# Native regressions

Run the host contract checks from the repository root with
`bash tool/ci/test_native_contracts.sh`.

Android Command Export core builds use `-O2` in Release and RelWithDebInfo.
Configure with `-DMAPLIBRE_ANDROID_CORE_OPTIMIZE_SPEED=OFF` to use the upstream
size optimization for comparison. This option does not change bridge,
dependency, or link flags. CMake retains explicit values in its build cache,
so pass `ON` to enable speed optimization in a directory previously set to `OFF`.
The host contract suite checks the default and both explicit values across
optimized and unoptimized build configurations.

The optional `maplibre_repack_vertices_v1` entry point accepts these
vertex layouts. Input bytes are little-endian, and outputs are numeric float32
values except for paint attributes copied unchanged.

| Layout | Input bytes | Output bytes | Encoding |
| --- | ---: | ---: | --- |
| 1 | 12 | 24 | Fill-extrusion position, decimal/edge, and normal fields |
| 2 | 44 | 56 | The same fill-extrusion fields followed by 32 paint bytes |
| 3 | 8 | 24 | Two signed line position fields and four unsigned data bytes |
| 4 | 8 | 12 | Three numeric floats containing byte groups 0–2, 3–5, and 6–7 |

Layout 4 treats each byte group as a little-endian unsigned integer. Its values
are at most `0xffffff`, so float32 preserves every input bit without NaN or
subnormal carriers. Unknown layouts return zero, allowing callers to fall back
to another conversion. Supported empty inputs succeed without dereferencing
pointers. Invalid spans return minus one without writing output. The entry point
allocates no memory and retains neither caller-owned pointer. Contract checks
cover unaligned spans, integer boundaries, round trips, overlap rejection, and
the exported C ABI.

The inactive fill-extrusion memory regression also runs against the real
Android Command Export core. It checks retained tile ownership and geometry
recovery across visible, hidden, and visible camera states with zero and
positive tile-cache limits.

```sh
bash native/scripts/build_android.sh arm64-v8a
cmake -S native/platforms/android \
  -B build-android-fluttergpu-arm64-v8a \
  -DMAPLIBRE_BUILD_OFFLINE_MEMORY_TEST=ON
cmake --build build-android-fluttergpu-arm64-v8a \
  --target maplibre_inactive_fe_memory_test --parallel
adb -s "$MAPLIBRE_TEST_DEVICE" push \
  build-android-fluttergpu-arm64-v8a/maplibre_inactive_fe_memory_test \
  /data/local/tmp/maplibre_inactive_fe_memory_test
adb -s "$MAPLIBRE_TEST_DEVICE" shell \
  chmod 755 /data/local/tmp/maplibre_inactive_fe_memory_test
adb -s "$MAPLIBRE_TEST_DEVICE" shell \
  /data/local/tmp/maplibre_inactive_fe_memory_test
```

Set `MAPLIBRE_TEST_DEVICE` to the selected Android device serial. The executable
uses offline GeoJSON and native threads without a JVM. Unexpected HTTP requests
fail the test. Production bridge builds retain the Android HTTP and thread
implementations.

Core headers and test translation units must share the same `NDEBUG` setting
because it affects native object layouts. Use `MAPLIBRE_TEST_CHECK` for checks
that must execute in Release builds, including initialization calls.
