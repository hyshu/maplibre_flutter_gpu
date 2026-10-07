import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart' show immutable;

import 'camera.dart';
import 'map_frame_state.dart';

/// A location supplied by the application, independent of location services.
///
/// This value does not request permissions, start sensors, or move the camera.
@immutable
class MapUserLocation {
  /// Creates a location with optional heading and horizontal accuracy.
  ///
  /// Coordinates and heading must be finite. Accuracy must be finite and
  /// nonnegative. Invalid values throw an [ArgumentError].
  MapUserLocation({
    required this.position,
    double? headingDegrees,
    this.accuracyMeters,
  }) : headingDegrees = headingDegrees == null ? null : headingDegrees % 360 {
    if (!position.latitude.isFinite || !position.longitude.isFinite) {
      throw ArgumentError.value(position, 'position', 'Must be finite');
    }
    if (headingDegrees != null && !headingDegrees.isFinite) {
      throw ArgumentError.value(
        headingDegrees,
        'headingDegrees',
        'Must be finite',
      );
    }
    if (accuracyMeters != null &&
        (!accuracyMeters!.isFinite || accuracyMeters! < 0)) {
      throw ArgumentError.value(
        accuracyMeters,
        'accuracyMeters',
        'Must be finite and nonnegative',
      );
    }
  }

  /// The geographic position in degrees.
  final LatLng position;

  /// Direction clockwise from geographic north, normalized to `[0, 360)`.
  ///
  /// Null omits the heading indicator. Applications choose whether this is
  /// a device heading or a direction of travel.
  final double? headingDegrees;

  /// Horizontal uncertainty radius in meters.
  ///
  /// Null or zero omits the accuracy area.
  final double? accuracyMeters;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapUserLocation &&
          other.position == position &&
          other.headingDegrees == headingDegrees &&
          other.accuracyMeters == accuracyMeters;

  @override
  int get hashCode => Object.hash(position, headingDegrees, accuracyMeters);
}

/// Immutable location geometry projected against one adopted native frame.
///
/// Screen coordinates are logical pixels from the current map layout's
/// top-left corner. They already account for fractional layout sizes and any
/// scaling of the previous frame during a resize. They must not be multiplied
/// by the display's device pixel ratio.
@immutable
class MapUserLocationRenderState {
  /// Creates a snapshot for a location overlay.
  ///
  /// [accuracyPolygon] is copied so subsequent input changes cannot alter this
  /// snapshot.
  MapUserLocationRenderState({
    required this.location,
    required this.frame,
    required this.screenPosition,
    required this.viewportSize,
    this.headingRadians,
    List<Offset> accuracyPolygon = const [],
  }) : accuracyPolygon = List.unmodifiable(accuracyPolygon);

  /// The location input used to produce this geometry.
  final MapUserLocation location;

  /// The native frame used for every projection in this snapshot.
  final MapFrameState frame;

  /// The location's nearest horizontal world copy in logical layout pixels.
  ///
  /// This may lie outside the viewport.
  final Offset screenPosition;

  /// Current map layout dimensions in logical pixels.
  final Size viewportSize;

  /// Projected heading clockwise from screen-up, in radians.
  ///
  /// Null means no heading was supplied or its direction could not be
  /// projected. Camera bearing, pitch, and layout scaling are included.
  final double? headingRadians;

  /// The accuracy boundary in logical layout pixels.
  ///
  /// Like the native location annotation, its radius uses the ground scale at
  /// the location latitude and its vertical extent follows camera pitch.
  /// The first point is not repeated at the end. The list is empty when no
  /// positive accuracy was supplied or its boundary could not be projected.
  final List<Offset> accuracyPolygon;
}
