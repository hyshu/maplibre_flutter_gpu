part of '../maplibre_ffi.dart';

/// Viewport insets, visible geographic bounds, and ground scale.
///
/// Operations without a native implementation either use a documented
/// fallback or throw an [UnsupportedError].
mixin MaplibreBridgeProjectionBindings {
  BridgeSessionLifecycle get _lifecycle;
  NativeSymbolTable get _symbols;
  Pointer<Double> get _cameraOutput;

  // The bridge resolves these optional native callbacks.
  SetContentInsetsD? _setContentInsets;
  SetContentInsetsWithDurationD? _setContentInsetsWithDuration;
  GetVisibleRegionD? _getVisibleRegion;
  DoubleArgD? _getMetersPerPixelAtLatitude;

  /// Camera zoom required by the meters-per-pixel fallback.
  double getCameraZoom();

  /// Sets the logical-pixel insets of the map viewport.
  ///
  /// Custom durations require the duration-aware native operation. A duration
  /// of 300 milliseconds can use the compatibility operation. Throws an
  /// [UnsupportedError] when the required operation is unavailable and a
  /// [StateError] when MapLibre rejects the update.
  void setContentInsets({
    required double top,
    required double left,
    required double bottom,
    required double right,
    required bool animated,
    required Duration duration,
  }) {
    _lifecycle.ensureActive();
    final withDuration = _setContentInsetsWithDuration;
    if (withDuration != null) {
      if (withDuration(
            top,
            left,
            bottom,
            right,
            animated ? 1 : 0,
            duration.inMilliseconds,
          ) ==
          0) {
        throw StateError('MapLibre rejected the content insets');
      }
      return;
    }
    if (duration != const Duration(milliseconds: 300)) {
      _symbols.requireSymbol(
        withDuration,
        'updateContentInsets duration',
        feature: 'content inset duration',
      );
    }
    final callback = _symbols.requireSymbol(
      _setContentInsets,
      'updateContentInsets',
    );
    if (callback(top, left, bottom, right, animated ? 1 : 0) == 0) {
      throw StateError('MapLibre rejected the content insets');
    }
  }

  /// Returns the visible geographic bounds in degrees.
  ///
  /// Longitudes remain unwrapped when the viewport crosses the antimeridian.
  /// Throws an [UnsupportedError] when the native operation is unavailable and
  /// a [StateError] when MapLibre cannot determine the bounds.
  ({double south, double west, double north, double east}) getVisibleRegion() {
    _lifecycle.ensureActive();
    final callback = _symbols.requireSymbol(
      _getVisibleRegion,
      'getVisibleRegion',
    );
    final result = callback(
      _cameraOutput,
      _cameraOutput + 1,
      _cameraOutput + 2,
      _cameraOutput + 3,
    );
    if (result == 0) {
      throw StateError('MapLibre could not determine the visible region');
    }
    return (
      south: _cameraOutput[0],
      west: _cameraOutput[1],
      north: _cameraOutput[2],
      east: _cameraOutput[3],
    );
  }

  /// Returns ground meters represented by one logical pixel at [latitude].
  ///
  /// [latitude] is expressed in degrees. When the native operation is
  /// unavailable, the value is calculated from the current zoom after clamping
  /// the latitude to the Web Mercator range.
  double getMetersPerPixelAtLatitude(double latitude) {
    _lifecycle.ensureActive();
    final callback = _getMetersPerPixelAtLatitude;
    if (callback != null) return callback(latitude);
    final clampedLatitude = latitude.clamp(-85.0511287798066, 85.0511287798066);

    return math.cos(clampedLatitude * math.pi / 180) *
        2 *
        math.pi *
        6378137.0 /
        (512 * math.pow(2, getCameraZoom()));
  }
}
