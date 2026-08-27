import 'package:flutter/foundation.dart';

import 'camera.dart';

/// Bounds for the map camera target.
@immutable
class const CameraTargetBounds(this.bounds) {
  /// The geographical bounding box, or `null` for no explicit target bounds.
  ///
  /// The map projection's intrinsic latitude limits still apply.
  final LatLngBounds? bounds;

  /// Camera target bounds with no explicit geographical restriction.
  static const CameraTargetBounds unbounded = CameraTargetBounds(null);

  dynamic toJson() => <dynamic>[bounds?.toList()];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraTargetBounds && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;

  @override
  String toString() => 'CameraTargetBounds(bounds: $bounds)';
}

/// Preferred minimum and maximum map zoom levels.
@immutable
class const MinMaxZoomPreference(this.minZoom, this.maxZoom) {
  this : assert(minZoom == null || maxZoom == null || minZoom <= maxZoom);

  /// The minimum zoom level, or `null` when unspecified.
  final double? minZoom;

  /// The maximum zoom level, or `null` when unspecified.
  final double? maxZoom;

  /// A zoom preference that uses the default range from 0 to 25.5.
  static const MinMaxZoomPreference unbounded = MinMaxZoomPreference(
    null,
    null,
  );

  dynamic toJson() => <dynamic>[minZoom, maxZoom];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MinMaxZoomPreference &&
          other.minZoom == minZoom &&
          other.maxZoom == maxZoom;

  @override
  int get hashCode => Object.hash(minZoom, maxZoom);

  @override
  String toString() =>
      'MinMaxZoomPreference(minZoom: $minZoom, maxZoom: $maxZoom)';
}

/// Preferred minimum and maximum map tilt levels, in degrees.
@immutable
class const MinMaxTiltPreference(this.minTilt, this.maxTilt) {
  this
    : assert(minTilt == null || maxTilt == null || minTilt <= maxTilt),
      assert(minTilt == null || (minTilt >= 0 && minTilt <= 180)),
      assert(maxTilt == null || (maxTilt >= 0 && maxTilt <= 180));

  /// The minimum tilt in degrees, or `null` when unspecified.
  final double? minTilt;

  /// The maximum tilt in degrees, or `null` when unspecified.
  final double? maxTilt;

  /// A tilt preference that uses the default range from 0 to 60 degrees.
  static const MinMaxTiltPreference unbounded = MinMaxTiltPreference(
    null,
    null,
  );

  dynamic toJson() => <dynamic>[minTilt, maxTilt];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MinMaxTiltPreference &&
          other.minTilt == minTilt &&
          other.maxTilt == maxTilt;

  @override
  int get hashCode => Object.hash(minTilt, maxTilt);

  @override
  String toString() =>
      'MinMaxTiltPreference(minTilt: $minTilt, maxTilt: $maxTilt)';
}
