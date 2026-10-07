# Manual user-location parity check

This fixture compares the actual MapLibre Native iOS default location annotation
with `MapLibreMap.userLocation`. It is intentionally outside CI.

The reference uses MapLibre Native iOS 6.27.0 from the existing `maplibre_gl`
fixture's pinned dependency. A custom `MLNLocationManager` supplies deterministic
`CLLocation` and `CLHeading` values. It creates no Core Location manager, requests
no permission, and reads no device location.

Both apps use the same offline background style, camera, viewport, device pixel
ratio, and location inputs in `scenarios.dart`. The native reference is a real
`MLNMapView`, including its standard annotation layers. The GPU capture runs the
real native bridge and Flutter GPU renderer on the same iOS Simulator.

## Run

Use a booted iOS Simulator, Flutter 3.47 or newer, Xcode 27, and Python with Pillow.
The repository's matching Darwin native artifacts must already be built.

```sh
python3 -m venv build/user-location-tools
build/user-location-tools/bin/pip install Pillow
python3 tool/user_location/run.py --device <SIMULATOR_UDID>
build/user-location-tools/bin/python tool/user_location/compare.py
```

`--only native` and `--only gpu` recapture one implementation. The script copies
existing iOS project scaffolding into `build/user_location/reference_app` and
adds the small reference sources stored here. Dart templates avoid introducing
an integration-test dependency into the published package.

Check the Dart templates separately with
`python3 tool/user_location/run.py --check-templates`.

Raw screenshots, input metadata, and logs remain in `build/user_location`.
The comparison writes `doc/images/user-location-comparison.png` and
`tool/user_location/results.json`. The figure shows matching 180-point crops
around the native anchor. Its difference column multiplies RGB differences by
six so edge differences remain visible.

## What is checked

The nine captures cover zoom changes, map rotation, pitch, latitude-dependent
accuracy scale, heading, idle-camera position updates, hiding, resizing, and the
nearest world copy across the antimeridian. The GPU integration test also checks
null builders, builders returning null, hiding while paused, and preservation of
the latest location through paused updates and a fractional resize.

A native regression saves the adopted frame transform, advances the live native
camera without rendering, and confirms that the saved transform still projects
the location within 0.1 logical pixels of the original native result.

The animation test compares intermediate frames and actual marker layout with
an independent flat Mercator calculation.

```sh
cd e2e/visual/gpu_app
flutter test integration_test/user_location_animation_test.dart -d macos
```

It keeps its binding resumed if the desktop window loses focus so it can
continue sampling the native transition. The iOS capture separately checks
paused updates and resuming.

The comparison verifies the following against native pixels and native metadata.

- The marker is present when requested and absent when hidden.
- Projected anchors differ by at most 0.1 logical pixels.
- Colored marker area remains within ten percent of the reference.
- Colored marker intersection over union is at least 90 percent.
- Marker tint medians differ by at most two RGB levels.
- Accuracy radius geometry differs by at most 0.1 logical pixels.
- Visible accuracy extents differ by at most one logical pixel.
- Mean absolute RGB error over the foreground union is at most 5 out of 255.

Background agreement is excluded from the appearance error. The colored marker
mask includes the dot and heading arrow, so an empty image cannot pass on a large
plain background. Accuracy masks exclude antialiased colored marker edges.

## Reference normalization

Native Core Animation animations are removed from the real annotation layers
before capture. This freezes their model values and compares the static dot,
heading, accuracy area, and shadow. Native pulsing and tracking-mode animations
are outside this comparison.

MapLibre Native ignores a location update with exactly the previous coordinate,
even when its accuracy changes. The fixture sends a one-centimeter intermediate
fix before the requested final fix, waits for the requested accuracy to appear
in native readback, and captures only the final position.

The checked-in result uses an iPhone 18 Pro running iOS 27 at DPR 3. Its native
default tint is `#0088FF`. Native layer dimensions round the nominal 16.5-point
inner dot to 17 points. The outer dot remains 22 points. Accuracy diameters of
37 points or less are hidden by the native default annotation. These are
platform-specific reference details rather than claims about Android styling.
