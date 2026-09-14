part of 'maplibre_map_controller.dart';

mixin _ProjectionController on _CameraController {
  /// Projects `latLng` into the map viewport's logical-pixel coordinate space.
  ///
  /// The origin is the top-left corner of the [MapLibreMap]. The returned
  /// future completes with the horizontal and vertical position relative to
  /// that origin. Use [toScreenOffset] when a synchronous [Offset] is more
  /// convenient.
  Future<math.Point<num>> toScreenLocation(LatLng latLng) async {
    final value = toScreenOffset(latLng);

    return math.Point<double>(value.dx, value.dy);
  }

  /// Projects each coordinate in `latLngs` into logical viewport pixels.
  ///
  /// The origin is the top-left corner of the [MapLibreMap]. The returned list
  /// preserves input order and is empty when `latLngs` is empty. The future
  /// completes after all coordinates have been projected.
  Future<List<math.Point<num>>> toScreenLocationBatch(
    Iterable<LatLng> latLngs,
  ) async {
    _ensureNotDisposed();
    final result = <math.Point<num>>[];
    for (final latLng in latLngs) {
      final value = _bridge.latLonToScreen(latLng.latitude, latLng.longitude);
      result.add(math.Point<double>(value.dx, value.dy));
    }
    return result;
  }

  /// Projects `latLng` into logical viewport pixels synchronously.
  ///
  /// The returned [Offset] is relative to the top-left corner of the
  /// [MapLibreMap].
  Offset toScreenOffset(LatLng latLng) {
    _ensureNotDisposed();

    return _bridge.latLonToScreen(latLng.latitude, latLng.longitude);
  }

  /// Projects every visible horizontal world copy of `latLng`.
  ///
  /// Multiple offsets can be returned when a low zoom shows the same wrapped
  /// world more than once. [padding] expands the viewport used to retain
  /// copies, which lets an overlay remain mounted while its anchor is just
  /// outside an edge.
  List<Offset> toScreenOffsets(
    LatLng latLng, {
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    _ensureNotDisposed();
    final width = _bridge.logicalWidth;
    final height = _bridge.logicalHeight;
    final camera = _cameraPosition;
    if (width <= 0 || height <= 0 || camera == null) {
      return [toScreenOffset(latLng)];
    }
    final worldSize = 512 * math.pow(2, camera.zoom);
    final paddedSpan = math.max(
      width + padding.horizontal,
      height + padding.vertical,
    );
    final radius = (paddedSpan / worldSize).ceil() + 2;
    final centerWrap = ((camera.target.longitude - latLng.longitude) / 360)
        .round();
    final wraps = <int>[
      for (var wrap = centerWrap - radius; wrap <= centerWrap + radius; wrap++)
        wrap,
    ];
    final projected = _bridge.wrappedLatLonsToScreen([
      for (final wrap in wraps)
        (
          latitude: latLng.latitude,
          longitude: latLng.longitude,
          tileWrap: wrap,
        ),
    ]);
    final result = <Offset>[];
    for (final offset in projected) {
      final visible =
          offset.dx >= -padding.left &&
          offset.dx <= width + padding.right &&
          offset.dy >= -padding.top &&
          offset.dy <= height + padding.bottom;
      if (visible && !result.contains(offset)) result.add(offset);
    }

    return result;
  }

  /// Converts a logical viewport position to a geographic coordinate.
  ///
  /// `screenLocation` is relative to the top-left corner of the [MapLibreMap].
  /// The returned future completes with the coordinate under that position. Use
  /// [toLatLngOffset] when a synchronous [Offset] input is more convenient.
  Future<LatLng> toLatLng(math.Point<num> screenLocation) async =>
      toLatLngOffset(
        Offset(screenLocation.x.toDouble(), screenLocation.y.toDouble()),
      );

  /// Converts a logical viewport `screenLocation` to a coordinate synchronously.
  ///
  /// `screenLocation` is relative to the top-left corner of the [MapLibreMap].
  LatLng toLatLngOffset(Offset screenLocation) {
    _ensureNotDisposed();
    final result = _bridge.screenToLatLon(screenLocation.dx, screenLocation.dy);

    return .new(result.latitude, result.longitude);
  }

  /// Returns the geographic bounds visible in the current viewport.
  ///
  /// The bounds are latitude and longitude aligned. A viewport that crosses the
  /// antimeridian can produce bounds whose southwest longitude is greater than
  /// its northeast longitude. The future throws a [StateError] when MapLibre
  /// cannot determine the bounds.
  Future<LatLngBounds> getVisibleRegion() async {
    _ensureNotDisposed();
    final region = _bridge.getVisibleRegion();

    return .new(
      southwest: .new(region.south, region.west),
      northeast: .new(region.north, region.east),
    );
  }

  /// Returns ground meters represented by one logical pixel at `latitude`.
  ///
  /// `latitude` is specified in degrees. The scale is calculated at the current
  /// camera zoom. The returned future completes with the scale for that
  /// latitude.
  Future<double> getMetersPerPixelAtLatitude(double latitude) async {
    _ensureNotDisposed();

    return _bridge.getMetersPerPixelAtLatitude(latitude);
  }
}
