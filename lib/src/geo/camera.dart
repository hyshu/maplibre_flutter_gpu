import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// A pair of latitude and longitude coordinates, stored as degrees.
@immutable
class LatLng {
  /// Creates a geographical location from [latitude] and [longitude].
  /// Both values are specified in degrees.
  ///
  /// The latitude is clamped to the inclusive interval `[-90.0, 90.0]`.
  const new(double latitude, double longitude)
    : latitude = latitude < -90.0 ? -90.0 : (latitude > 90.0 ? 90.0 : latitude),
      longitude = (longitude + 180.0) % 360.0 - 180.0;

  /// The latitude in degrees between -90.0 and 90.0, both inclusive.
  final double latitude;

  /// The longitude in degrees from -180.0 inclusive to 180.0 exclusive.
  /// Values outside this range are normalized by the constructor.
  final double longitude;

  dynamic toJson() => [latitude, longitude];

  List<double> toGeoJsonCoordinates() => [longitude, latitude];

  @override
  String toString() => 'LatLng($latitude, $longitude)';

  @override
  bool operator ==(Object other) =>
      other is LatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// A latitude/longitude-aligned rectangle.
@immutable
class const LatLngBounds({
  /// The southwest corner of these bounds.
  required final LatLng southwest,

  /// The northeast corner of these bounds.
  required final LatLng northeast,
}) {
  List<dynamic> toList() => [southwest.toJson(), northeast.toJson()];

  /// Returns whether [point] lies within these bounds.
  ///
  /// Bounds whose southwest longitude is greater than their northeast
  /// longitude are treated as crossing the antimeridian.
  bool contains(LatLng point) {
    final latitudeInBounds =
        point.latitude >= southwest.latitude &&
        point.latitude <= northeast.latitude;
    final longitudeInBounds = southwest.longitude <= northeast.longitude
        ? point.longitude >= southwest.longitude &&
              point.longitude <= northeast.longitude
        : point.longitude >= southwest.longitude ||
              point.longitude <= northeast.longitude;

    return latitudeInBounds && longitudeInBounds;
  }

  @override
  bool operator ==(Object other) =>
      other is LatLngBounds &&
      other.southwest == southwest &&
      other.northeast == northeast;

  @override
  int get hashCode => Object.hash(southwest, northeast);

  @override
  String toString() => 'LatLngBounds($southwest, $northeast)';
}

/// Describes the viewpoint from which the map is shown.
@immutable
class const CameraPosition({
  /// The camera's bearing in degrees, measured clockwise from north.
  final double bearing = 0.0,

  /// The geographical location that the camera is pointing at.
  required final LatLng target,

  /// The angle, in degrees, of the camera from the nadir (straight down).
  final double tilt = 0.0,

  /// The zoom level of the camera.
  final double zoom = 0.0,
}) {
  @override
  String toString() =>
      'CameraPosition(bearing: $bearing, target: $target, tilt: $tilt, zoom: $zoom)';

  @override
  bool operator ==(Object other) =>
      other is CameraPosition &&
      other.bearing == bearing &&
      other.target == target &&
      other.tilt == tilt &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(bearing, target, tilt, zoom);

  Map<String, dynamic> toMap() => {
    'bearing': bearing,
    'target': target.toJson(),
    'tilt': tilt,
    'zoom': zoom,
  };
}

/// Easing curve used by the controller's `easeCamera` method.
enum CameraAnimationInterpolation {
  /// Constant velocity.
  linear,

  /// Accelerates, then decelerates.
  easeInOut,

  /// Decelerates towards the target.
  easeOut,

  /// Material Design's fast-out/linear-in curve.
  fastOutLinearIn,
}

/// Defines an absolute or partial camera move.
class CameraUpdate {
  new _({
    required this.kind,
    this.cameraPosition,
    this.bounds,
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
    this.dx = 0,
    this.dy = 0,
    this.amount = 0,
    this.focus,
  });

  @internal
  final CameraUpdateKind kind;

  @internal
  final CameraPosition? cameraPosition;

  @internal
  final LatLngBounds? bounds;

  @internal
  final double left;

  @internal
  final double top;

  @internal
  final double right;

  @internal
  final double bottom;

  @internal
  final double dx;

  @internal
  final double dy;

  @internal
  final double amount;

  @internal
  final Offset? focus;

  /// Returns a camera update that moves the camera to the specified position.
  factory newCameraPosition(CameraPosition cameraPosition) => ._(
    kind: .cameraPosition,
    cameraPosition: cameraPosition,
  );

  /// Returns a camera update that moves the camera target to the specified
  /// geographical location.
  factory newLatLng(LatLng latLng) => ._(
    kind: .target,
    cameraPosition: .new(target: latLng),
  );

  /// Fits [bounds] inside the viewport using the supplied logical-pixel
  /// padding. The resulting bearing and tilt are zero.
  factory newLatLngBounds(
    LatLngBounds bounds, {
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) => ._(
    kind: .bounds,
    bounds: bounds,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  );

  /// Returns a camera update that moves the camera target to [latLng] and
  /// zooms to [zoom].
  factory newLatLngZoom(LatLng latLng, double zoom) => ._(
    kind: .targetAndZoom,
    cameraPosition: .new(target: latLng, zoom: zoom),
  );

  /// Moves the target by [dx], [dy] logical screen pixels.
  factory scrollBy(double dx, double dy) =>
      ._(kind: .scroll, dx: dx, dy: dy);

  /// Changes zoom by [amount], optionally preserving the coordinate under
  /// [focus].
  factory zoomBy(double amount, [Offset? focus]) => ._(
    kind: .zoomBy,
    amount: amount,
    focus: focus,
  );

  /// Zooms in by one level.
  factory zoomIn() => ._(kind: .zoomIn, amount: 1);

  /// Zooms out by one level.
  factory zoomOut() => ._(kind: .zoomOut, amount: -1);

  /// Returns a camera update that zooms the camera to the specified level.
  factory zoomTo(double zoom) => ._(
    kind: .zoom,
    cameraPosition: .new(target: const LatLng(0, 0), zoom: zoom),
  );

  /// Sets camera bearing.
  factory bearingTo(double bearing) => ._(
    kind: .bearing,
    cameraPosition: .new(
      target: const LatLng(0, 0),
      bearing: bearing,
    ),
  );

  /// Sets camera tilt.
  factory tiltTo(double tilt) => ._(
    kind: .tilt,
    cameraPosition: .new(target: const LatLng(0, 0), tilt: tilt),
  );

  /// maplibre_gl-compatible serialized representation.
  dynamic toJson() => switch (kind) {
    .cameraPosition => <dynamic>[
      'newCameraPosition',
      cameraPosition!.toMap(),
    ],
    .target => <dynamic>[
      'newLatLng',
      cameraPosition!.target.toJson(),
    ],
    .bounds => <dynamic>[
      'newLatLngBounds',
      bounds!.toList(),
      left,
      top,
      right,
      bottom,
    ],
    .targetAndZoom => <dynamic>[
      'newLatLngZoom',
      cameraPosition!.target.toJson(),
      cameraPosition!.zoom,
    ],
    .scroll => <dynamic>['scrollBy', dx, dy],
    .zoomBy =>
      focus == null
          ? <dynamic>['zoomBy', amount]
          : <dynamic>[
              'zoomBy',
              amount,
              [focus!.dx, focus!.dy],
            ],
    .zoomIn => <dynamic>['zoomIn'],
    .zoomOut => <dynamic>['zoomOut'],
    .zoom => <dynamic>['zoomTo', cameraPosition!.zoom],
    .bearing => <dynamic>['bearingTo', cameraPosition!.bearing],
    .tilt => <dynamic>['tiltTo', cameraPosition!.tilt],
  };

  /// Resolves this partial update against [current] without treating valid
  /// zero values as sentinels.
  @internal
  CameraPosition resolveAgainst(CameraPosition current) {
    final value = cameraPosition;

    if (value == null) return current;

    return switch (kind) {
      .cameraPosition => value,
      .target => .new(
        bearing: current.bearing,
        target: value.target,
        tilt: current.tilt,
        zoom: current.zoom,
      ),
      .targetAndZoom => .new(
        bearing: current.bearing,
        target: value.target,
        tilt: current.tilt,
        zoom: value.zoom,
      ),
      .zoom => .new(
        bearing: current.bearing,
        target: current.target,
        tilt: current.tilt,
        zoom: value.zoom,
      ),
      .bearing => .new(
        bearing: value.bearing,
        target: current.target,
        tilt: current.tilt,
        zoom: current.zoom,
      ),
      .tilt => .new(
        bearing: current.bearing,
        target: current.target,
        tilt: value.tilt,
        zoom: current.zoom,
      ),
      .zoomBy => .new(
        bearing: current.bearing,
        target: current.target,
        tilt: current.tilt,
        zoom: current.zoom + amount,
      ),
      .zoomIn || .zoomOut => .new(
        bearing: current.bearing,
        target: current.target,
        tilt: current.tilt,
        zoom: current.zoom + amount,
      ),
      .bounds || .scroll => current,
    };
  }
}

/// Package-internal normalized camera update kind.
@internal
enum CameraUpdateKind {
  cameraPosition,
  target,
  bounds,
  targetAndZoom,
  scroll,
  zoomBy,
  zoomIn,
  zoomOut,
  zoom,
  bearing,
  tilt,
}
