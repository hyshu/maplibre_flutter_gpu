# maplibre_flutter_gpu

Render MapLibre maps with Flutter GPU without Platform Views. Maps and Flutter Widgets stay smooth and synchronized, with support for custom 3D rendering.

## Widgets on the map

Have you ever wanted to place a Flutter widget on a map as a marker?

With conventional map packages, the widget falls out of sync while the map moves.

<p align="center">
  <img src="https://raw.githubusercontent.com/hyshu/maplibre_flutter_gpu/main/doc/images/map-widget-comparison.gif" alt="Flutter widget synchronization comparison" width="600">
</p>

Flutter and the map use different rendering engines,
so their frames cannot stay perfectly synchronized. The effect becomes more
noticeable on lower-end devices and can make the map difficult to use.

MapLibre Flutter GPU solves this by letting Flutter render the map and the
widgets together.

## Everything (Text and Symbols) is a Widget

Every label and symbol on the map is a Flutter widget. You can also place any
widget you like at any geographic coordinate.

Use Flutter to restyle place names and regional labels or bring them to life
with animations. Map content and your interface share the same widget system
and stay synchronized while the camera moves.

## Place 3D objects in map space

Because the map is rendered with Flutter GPU, you can render custom geometry
directly in the map's 3D coordinate space from Dart.

<p align="center">
  <img src="https://raw.githubusercontent.com/hyshu/maplibre_flutter_gpu/main/doc/images/custom-3d-rendering.gif" alt="Custom 3D rendering on a Flutter GPU map" width="400" height="400">
</p>

New to Flutter GPU? That is fine. Modern LLMs can already help implement a
surprisingly wide range of Flutter GPU effects.

Turn a flat map pin into a 3D object positioned in geographic space. Animate
cars along roads. If you want to go further, you could even build a flight
simulator or an FPS game around a real map.

## Supported platforms

MapLibre Flutter GPU currently supports the following platforms.

- iOS
- Android
- macOS
- Windows x64 and ARM64
- Linux x64 and ARM64

Web is not supported because Flutter GPU is unavailable there.

## Getting started

Flutter 3.47.0 or later is required.

Add MapLibre Flutter GPU to your project with this command.

```bash
flutter pub add maplibre_flutter_gpu
```

Enable Flutter GPU in your app's `ios/Runner/Info.plist` and
`macos/Runner/Info.plist`.

```xml
<key>FLTEnableFlutterGPU</key>
<true/>
```

On Windows and Linux, enable Flutter GPU when running the app.

```bash
flutter run -d windows --enable-flutter-gpu
flutter run -d linux --enable-flutter-gpu
```

Flutter 3.47 does not yet support Flutter GPU in Windows or Linux release
builds.

Import the package and add a `MapLibreMap` widget.

```dart
import 'package:flutter/material.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  MapLibreMapController? _controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: MapLibreMap(
      styleString: MapLibreStyles.openfreemapLiberty,
      initialCameraPosition: const CameraPosition(
        target: LatLng(35.6812, 139.7671),
        zoom: 13,
      ),
      onMapCreated: (controller) {
        _controller = controller;
      },
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () {
        _controller?.animateCamera(
          CameraUpdate.newLatLngZoom(
            const LatLng(35.6586, 139.7454),
            15,
          ),
        );
      },
      child: const Icon(Icons.location_searching),
    ),
  );
}
```

## MapLibreMap constructor

### Map and lifecycle

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `initialCameraPosition` | `CameraPosition?` | Style camera | Camera used when the map is created. Use the controller for later changes. |
| `styleString` | `String` | `MapLibreStyles.demo` | Style URL, raw style JSON, absolute file path, file URI, or Flutter asset path. |
| `onMapCreated` | `MapCreatedCallback?` | `null` | Receives the controller after renderer creation. The initial style may still be loading. |
| `onStyleLoadedCallback` | `OnStyleLoadedCallback?` | `null` | Runs after the active style loads and after every successful style replacement. |
| `onCameraMove` | `OnCameraMoveCallback?` | `null` | Reports camera changes caused by gestures or controller commands. |
| `onCameraIdle` | `OnCameraIdleCallback?` | `null` | Runs after camera movement settles. It does not mean all map work has finished. |
| `onMapIdle` | `OnMapIdleCallback?` | `null` | Runs whenever style, camera, and pending map work have fully settled. |
| `onMapClick` | `OnMapClickCallback?` | `null` | Reports a tap using logical screen coordinates and geographic coordinates. |
| `onMapLongClick` | `OnMapClickCallback?` | `null` | Reports the start of a long press using screen and geographic coordinates. |

### Camera and gestures

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `cameraTargetBounds` | `CameraTargetBounds` | No explicit bounds | Limits the geographic camera target. Web Mercator projection limits still apply. |
| `minMaxZoomPreference` | `MinMaxZoomPreference` | 0–25.5 | Limits camera zoom. |
| `minMaxTiltPreference` | `MinMaxTiltPreference` | 0–60° | Limits camera tilt in degrees. |
| `rotateGesturesEnabled` | `bool` | `true` | Enables two-finger rotation. |
| `scrollGesturesEnabled` | `bool` | `true` | Enables one-finger panning. |
| `zoomGesturesEnabled` | `bool` | `true` | Enables pinch and scroll-wheel zoom. |
| `tiltGesturesEnabled` | `bool` | `true` | Enables three-finger vertical tilt. |
| `doubleClickZoomEnabled` | `bool?` | Follows zoom gestures | Enables double-tap zoom independently. |
| `gestureOptions` | `MapGestureOptions` | `const MapGestureOptions()` | Configures gesture animation, thresholds, and sensitivity. |
| `trackCameraPosition` | `bool` | `false` | Makes the controller notify its listeners when the camera changes. |

### Map controls

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `compassEnabled` | `bool` | `true` | Displays the compass when its builder is available. |
| `compassViewPosition` | `CompassViewPosition?` | Top right | Positions the compass. |
| `compassViewMargins` | `Point<num>?` | `(8, 8)` | Sets compass insets in logical pixels. |
| `compassBuilder` | `CompassWidgetBuilder?` | Default compass | Builds the compass from its bearing and reset callback. |
| `logoEnabled` | `bool` | `false` | Displays the MapLibre logo when its builder is available. |
| `logoViewPosition` | `LogoViewPosition?` | Bottom left | Positions the logo. |
| `logoViewMargins` | `Point<num>?` | `(8, 8)` | Sets logo insets in logical pixels. |
| `logoBuilder` | `WidgetBuilder?` | Default logo | Builds the MapLibre logo. |
| `attributionButtonEnabled` | `bool` | `true` | Displays the attribution button. |
| `attributionButtonPosition` | `AttributionButtonPosition?` | Bottom right | Positions the attribution button. |
| `attributionButtonMargins` | `Point<num>?` | `(8, 8)` | Sets attribution-button insets in logical pixels. |
| `onAttributionLinkTap` | `AttributionLinkCallback?` | `null` | Handles links selected in the default attribution dialog. |
| `attributionButtonBuilder` | `AttributionButtonWidgetBuilder?` | Default button | Builds the attribution button. |
| `attributionDialogBuilder` | `WidgetBuilder?` | Default dialog | Builds the dialog opened by the attribution button. |
| `scaleControlEnabled` | `bool` | `false` | Displays a scale bar when its value can be calculated. |
| `scaleControlPosition` | `ScaleControlPosition` | Bottom left | Positions the scale bar. |
| `scaleControlUnit` | `ScaleControlUnit` | Metric | Selects metric or imperial distance. |
| `scaleControlMargins` | `Point<num>` | `(8, 8)` | Sets scale-bar insets in logical pixels. |
| `scaleControlMaxWidth` | `double` | `80` | Sets the maximum scale-bar width in logical pixels. |
| `scaleControlAvoidLogo` | `bool` | `true` | Moves the scale bar above a logo in the same bottom corner. |
| `scaleControlLogoOffset` | `double` | `27` | Sets the logo avoidance offset in logical pixels. |
| `scaleControlBuilder` | `ScaleControlWidgetBuilder?` | Default scale bar | Builds the scale bar from a `ScaleBarValue`. |

### Flutter widgets and custom GPU content

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `foregroundLoadColor` | `Color?` | Transparent | Value supplied to the loading builder. |
| `loadingBuilder` | `MapLoadingWidgetBuilder?` | Default overlay | Builds the widget displayed while a style loads. |
| `errorBuilder` | `MapErrorWidgetBuilder?` | `ErrorWidget` | Builds the replacement widget when map creation fails. |
| `symbolIconBuilder` | `SymbolWidgetBuilder?` | Style sprite | Builds every placed symbol icon as a Flutter widget. Return `null` to hide one. |
| `symbolTextBuilder` | `SymbolWidgetBuilder?` | Style text | Builds every placed symbol label as a Flutter widget. Return `null` to hide one. |
| `symbolFadeDuration` | `Duration` | 150 ms | Controls symbol fade-in and fade-out. |
| `symbolCullingPadding` | `EdgeInsets` | 120 horizontal, 60 vertical | Keeps symbols built slightly outside the viewport. |
| `symbolCompositingMode` | `SymbolCompositingMode` | `interleaved` | Preserves style layer order or uses a faster single-surface overlay. |
| `gpuMapRenderCallback` | `MapLibreGpuRenderCallback?` | `null` | Records geographic GPU geometry inside the map's 3D sequence with shared depth. |
| `gpuRenderCallback` | `MapLibreGpuRenderCallback?` | `null` | Records a final Flutter GPU overlay above the map. |
| `gpuRepaint` | `Listenable?` | `null` | Requests new frames for animated custom GPU content. |
| `gpuOverlayDepthMode` | `MapLibreGpuDepthMode` | `isolated` | Selects isolated or shared depth for the final GPU overlay. |

`MapLibreMap` creates and owns its `MapLibreMapController`. Receive the
controller through `onMapCreated`, then use it to move the camera, change the
style, manage layers, inspect source metadata, and convert between geographic
and screen coordinates. Do not dispose the controller yourself.

MapLibre performs symbol placement and collision detection, while Flutter
builds the result. Customize map labels and icons with ordinary widgets.

```dart
MapLibreMap(
  symbolTextBuilder: (context, symbol) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(symbol.data.text),
    ),
  ),
  symbolIconBuilder: (context, symbol) => const Icon(
    Icons.location_on,
    color: Colors.red,
  ),
)
```

For symbol-heavy maps, `fastOverlay` renders the native map into one GPU surface
and places all symbol widgets above it. Custom symbol builders continue to work,
but native layers that follow a symbol layer can no longer cover that symbol.

```dart
MapLibreMap(
  symbolCompositingMode: SymbolCompositingMode.fastOverlay,
)
```

### Interactive Flutter markers

Widget overlays are intentionally decoupled from `MapLibreMap`. Use a `Stack`
with the controller's coordinate conversion methods to place widgets at
geographic coordinates.

```dart
final position = controller.toScreenOffset(markerCoordinate);

Stack(
  children: [
    MapLibreMap(
      trackCameraPosition: true,
      ...
    ),
    Positioned(
      left: position.dx,
      top: position.dy,
      child: const Icon(Icons.location_pin),
    ),
  ],
)
```

Listen to the controller and update `position` when the camera changes. See the
[`example`](example/) app for a complete implementation, including listener
cleanup.

### Style-dependent operations

For operations that depend on the loaded style, wait for
`onStyleLoadedCallback`.

```dart
MapLibreMap(
  onMapCreated: (controller) {
    _controller = controller;
  },
  onStyleLoadedCallback: () async {
    await _controller?.setLayerVisibility('building-3d', true);
  },
)
```

## MapLibreMapController

The controller is used to change a map after it has been created. Save the
instance received by `onMapCreated` for later use.

### Style and layers

| Method | Description |
| --- | --- |
| `setStyle(styleString)` | Starts loading a style URL, JSON document, file, or Flutter asset. |
| `getStyle()` | Returns the active style JSON when available. |
| `getLayerIds()` | Returns the IDs of the loaded style layers. |
| `getSourceIds()` | Returns the IDs of the loaded style sources. |
| `getSourceAttributions()` | Returns unique source attribution strings. |
| `setLayerVisibility(layerId, visible)` | Shows or hides a loaded layer. |
| `getLayerVisibility(layerId)` | Returns layer visibility, or `null` when the layer does not exist. |
| `addFillExtrusionLayer(...)` | Adds a `maplibre_gl`-compatible fill-extrusion layer. |
| `addLayer(...)` | Adds a fill-extrusion layer from a `LayerProperties` object. |
| `setLayerProperties(layerId, properties)` | Updates the properties of a loaded layer. |
| `removeLayer(layerId)` | Removes a loaded layer. |
| `setFilter(layerId, filter)` | Applies a JSON-compatible filter and throws when the layer is missing. |
| `setLayerFilter(layerId, filter)` | Applies a JSON filter string and reports whether the layer was found. |
| `getFilter(layerId)` | Returns the parsed filter for a layer. |

### Camera and coordinates

| Method or property | Description |
| --- | --- |
| `cameraPosition` | Latest camera position cached by the controller. |
| `isCameraMoving` | Whether a programmatic camera transition is active. |
| `moveCamera(update)` | Applies a camera update immediately. |
| `animateCamera(update, duration: ...)` | Animates to a camera update. |
| `easeCamera(update, duration: ..., interpolation: ...)` | Applies a camera update with configurable easing. |
| `queryCameraPosition()` | Refreshes and returns the current camera position. |
| `toScreenLocation(latLng)` | Converts a geographic coordinate to logical screen pixels. |
| `toScreenLocationBatch(latLngs)` | Converts multiple geographic coordinates in one call. |
| `toScreenOffset(latLng)` | Synchronous `Offset` version of `toScreenLocation`. |
| `toLatLng(screenLocation)` | Converts logical screen pixels to a geographic coordinate. |
| `toLatLngOffset(screenLocation)` | Synchronous `Offset` version of `toLatLng`. |
| `getVisibleRegion()` | Returns the current visible geographic bounds. |
| `getMetersPerPixelAtLatitude(latitude)` | Returns map resolution at a latitude. |
| `setCameraBounds(...)` | Animates the camera to fit geographic bounds. |
| `updateContentInsets(...)` | Updates camera padding in logical pixels. |
| `resetNorth()` | Resets the camera bearing to north. |
| `getPlacedLabels()` | Returns the latest native label-placement snapshot. |
| `isMapIdle` | Whether the native map had no pending work after its last frame. This does not include Flutter fling animation. |

The controller belongs to its `MapLibreMap`. Do not call `dispose()` yourself
and do not use it after the map widget has been removed.

See the [`example`](example/) app and the standalone [`examples`](examples/)
for Flutter markers, runtime style controls, and custom Flutter GPU rendering.

---

This package is currently in beta. API and runtime stability are not
guaranteed. Android in particular still needs testing across a wider range of
devices and environments.

Bug reports, device compatibility results, and other feedback are welcome in
[GitHub Issues](https://github.com/hyshu/maplibre_flutter_gpu/issues).

This is an independent community project. It is not affiliated with or endorsed by the MapLibre organization.
