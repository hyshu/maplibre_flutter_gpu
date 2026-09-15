part of '../maplibre_ffi.dart';

/// Coordinate projection, viewport insets, visible bounds, and ground scale.
///
/// Operations without a native implementation either use a documented
/// fallback or throw an [UnsupportedError].
mixin MaplibreBridgeProjectionBindings {
  BridgeSessionLifecycle get _lifecycle;
  NativeSymbolTable get _symbols;
  final _cameraOutput = calloc<Double>(4);

  late final LatLonToScreenD _latLonToScreen;
  ProjectCoordinatesD? _projectCoordinates;
  ProjectWrappedCoordinatesD? _projectWrappedCoordinates;
  LatLonToScreenD? _screenToLatLon;

  // Reusable native outputs for scalar coordinate projection.
  final _outX = calloc<Double>();
  final _outY = calloc<Double>();
  Pointer<Double> _projectionLatitudes = nullptr;
  Pointer<Double> _projectionLongitudes = nullptr;
  Pointer<Int32> _projectionTileWraps = nullptr;
  Pointer<Float> _projectionX = nullptr;
  Pointer<Float> _projectionY = nullptr;
  var _projectionCapacity = 0;

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
    if (duration != const .new(milliseconds: 300)) {
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

  /// Projects a geographic coordinate to logical screen pixels.
  ///
  /// [lat] and [lon] are expressed in degrees.
  Offset latLonToScreen(double lat, double lon) {
    _lifecycle.ensureActive();
    _latLonToScreen(lat, lon, _outX, _outY);

    return .new(_outX.value, _outY.value);
  }

  /// Projects geographic points in one native call.
  ///
  /// Results preserve input order and use logical screen pixels. When batch
  /// projection is unavailable, each coordinate uses [latLonToScreen].
  List<Offset> latLonsToScreen(
    List<({double latitude, double longitude})> coordinates,
  ) {
    _lifecycle.ensureActive();
    final count = coordinates.length;
    if (count == 0) return const [];
    final project = _projectCoordinates;
    if (project == null) {
      return [
        for (final coordinate in coordinates)
          latLonToScreen(coordinate.latitude, coordinate.longitude),
      ];
    }
    _ensureProjectionCapacity(count);
    for (var index = 0; index < count; index++) {
      final coordinate = coordinates[index];
      _projectionLatitudes[index] = coordinate.latitude;
      _projectionLongitudes[index] = coordinate.longitude;
    }
    project(
      _projectionLatitudes,
      _projectionLongitudes,
      _projectionX,
      _projectionY,
      count,
    );

    return [
      for (var index = 0; index < count; index++)
        .new(_projectionX[index], _projectionY[index]),
    ];
  }

  /// Projects coordinates at explicit horizontal world copies.
  List<Offset> wrappedLatLonsToScreen(
    List<({double latitude, double longitude, int tileWrap})> coordinates,
  ) {
    _lifecycle.ensureActive();
    final count = coordinates.length;
    if (count == 0) return const [];
    final project = _projectWrappedCoordinates;
    if (project == null) {
      return latLonsToScreen([
        for (final coordinate in coordinates)
          (latitude: coordinate.latitude, longitude: coordinate.longitude),
      ]);
    }
    _ensureProjectionCapacity(count);
    for (var index = 0; index < count; index++) {
      final coordinate = coordinates[index];
      _projectionLatitudes[index] = coordinate.latitude;
      _projectionLongitudes[index] = coordinate.longitude;
      _projectionTileWraps[index] = coordinate.tileWrap;
    }
    project(
      _projectionLatitudes,
      _projectionLongitudes,
      _projectionTileWraps,
      _projectionX,
      _projectionY,
      count,
    );

    return [
      for (var index = 0; index < count; index++)
        .new(_projectionX[index], _projectionY[index]),
    ];
  }

  /// Ensures the reusable native projection buffers can hold [count] points.
  void _ensureProjectionCapacity(int count) {
    if (_projectionCapacity >= count) return;
    var capacity = _projectionCapacity == 0 ? 64 : _projectionCapacity;
    while (capacity < count) {
      capacity *= 2;
    }
    if (_projectionCapacity != 0) {
      calloc
        ..free(_projectionLatitudes)
        ..free(_projectionLongitudes)
        ..free(_projectionTileWraps)
        ..free(_projectionX)
        ..free(_projectionY);
    }
    _projectionLatitudes = calloc<Double>(capacity);
    _projectionLongitudes = calloc<Double>(capacity);
    _projectionTileWraps = calloc<Int32>(capacity);
    _projectionX = calloc<Float>(capacity);
    _projectionY = calloc<Float>(capacity);
    _projectionCapacity = capacity;
  }

  /// Converts logical screen pixels to a geographic coordinate in degrees.
  ///
  /// Throws an [UnsupportedError] when native inverse projection is
  /// unavailable.
  ({double latitude, double longitude}) screenToLatLon(double x, double y) {
    _lifecycle.ensureActive();
    final callback = _screenToLatLon;
    if (callback == null) {
      throw UnsupportedError(
        'screenToLatLon requires rebuilt MapLibre native libraries',
      );
    }
    callback(x, y, _outX, _outY);

    return (latitude: _outX.value, longitude: _outY.value);
  }

  void _releaseProjectionResources() {
    calloc
      ..free(_cameraOutput)
      ..free(_outX)
      ..free(_outY);
    if (_projectionCapacity != 0) {
      calloc
        ..free(_projectionLatitudes)
        ..free(_projectionLongitudes)
        ..free(_projectionTileWraps)
        ..free(_projectionX)
        ..free(_projectionY);
    }
  }
}
