## 0.0.4

* Render symbol icons and text with closer MapLibre parity, including
  data-driven styling, halos, formatted text, inline images, multiple sprite
  sources, and style layer ordering.
* Make symbol text and icons follow roads and other lines, with support for
  bidirectional and vertical text.
* Add opt-in `SymbolCompositingMode.fastOverlay` for maps where speed is
  preferred over exact style layer ordering.

## 0.0.3

* Add Linux and Windows support for x64 and ARM64 in debug and profile modes.
* Upgrade to Flutter 3.47.0 and Dart 3.13.0.

## 0.0.2

* Improve Flutter GPU setup instructions and API documentation in the README.
* Fix published shader bundle packaging and runtime lookup.
* Restrict `IgnorePointer` to the default symbol builders instead of wrapping
  every widget returned by custom symbol icon and text builders.
* Stop the shared native runtime before macOS process teardown to prevent
  shutdown crashes.

## 0.0.1

* Initial development release for iOS, Android, and macOS.
* Render MapLibre fill, line, circle, raster, symbol, and fill-extrusion layers
  with Flutter GPU.
* Provide map camera, gesture, style, source, layer, filter, sprite, and
  attribution APIs.
* Support custom Flutter GPU map rendering with geographic transforms and
  optional shared depth for 3D content.
* Render idle maps on demand and suspend frame scheduling with the application
  lifecycle.
* Include examples for landmark markers, style controls, and custom GPU
  rendering.
