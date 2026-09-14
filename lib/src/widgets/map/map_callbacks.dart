part of '../maplibre_map.dart';

/// Signature for a callback that receives a newly created map controller.
///
/// The callback runs once after a [MapLibreMap] successfully initializes its
/// renderer. The initial style might not have loaded yet. The map owns the
/// controller and disposes it when the widget is removed.
typedef MapCreatedCallback = void Function(MapLibreMapController controller);

/// Signature for a callback that runs after the active style has loaded.
///
/// The callback runs for the initial style and for each later style
/// replacement.
typedef OnStyleLoadedCallback = void Function();

/// Signature for a callback that receives each observed camera position.
///
/// Positions can result from gestures or commands sent through
/// [MapLibreMapController].
typedef OnCameraMoveCallback = void Function(CameraPosition cameraPosition);

/// Signature for a callback that runs when camera movement ends.
///
/// The movement can result from a gesture or a command sent through
/// [MapLibreMapController]. Scroll-wheel zoom does not have a completion phase
/// and does not call this callback.
typedef OnCameraIdleCallback = void Function();

/// Signature for a callback that runs when the map is fully settled.
///
/// A settled map has a loaded style, no pending map work, no active camera
/// transition, and no Flutter fling animation.
typedef OnMapIdleCallback = void Function();

/// Signature for callbacks that receive a point selected on the map.
///
/// `point` is measured in logical pixels from the map's top-left corner.
/// `coordinates` is the geographic position at that point.
typedef OnMapClickCallback = void Function(
  math.Point<double> point,
  LatLng coordinates,
);

/// Signature for building the overlay displayed while a map style is loading.
///
/// `foregroundLoadColor` is the value configured by
/// [MapLibreMap.foregroundLoadColor] and can be null. The returned widget does
/// not receive pointer events.
typedef MapLoadingWidgetBuilder = Widget Function(
  BuildContext context,
  Color? foregroundLoadColor,
);

/// Signature for building the replacement shown when initialization fails.
///
/// `error` contains the initialization error message.
typedef MapErrorWidgetBuilder = Widget Function(
  BuildContext context,
  String error,
);

/// Controls how Flutter symbol widgets are composited with native style layers.
enum SymbolCompositingMode {
  /// Interleaves native GPU surfaces and symbol widgets in style layer order.
  ///
  /// This preserves the relative order of symbol and non-symbol style layers,
  /// but may require more than one full-size GPU surface.
  interleaved,

  /// Renders the native map once and places every symbol widget above it.
  ///
  /// This minimizes GPU surfaces and render passes. Symbol icons and text
  /// remain Flutter widgets and continue to use the configured builders. Their
  /// relative order with native layers above their style layer is not preserved.
  fastOverlay,
}
