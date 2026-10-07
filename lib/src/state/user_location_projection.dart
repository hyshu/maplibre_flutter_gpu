import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import '../geo/map_frame_state.dart';
import '../geo/map_user_location.dart';
import '../native/frame_metadata.dart';

/// Location geometry cached while the adopted native frame is pinned.
///
/// Rebuilding an overlay only scales this snapshot and never queries a newer
/// native camera.
class UserLocationProjection {
  UserLocationProjection._({
    required this.location,
    required this.frame,
    required this.position,
    required this.headingVector,
    required this.accuracyPolygon,
  });

  final MapUserLocation location;
  final MapFrameState frame;
  final Offset position;
  final Offset? headingVector;
  final List<Offset> accuracyPolygon;

  /// Projects a location while the caller owns the frame snapshot.
  ///
  /// [transform] must belong to [frame]. It selects the nearest horizontal
  /// world copy without querying a live camera. Missing or invalid transforms
  /// and points behind the camera omit the location.
  static UserLocationProjection? capture({
    required MapUserLocation location,
    required MapFrameState frame,
    required FrameMapTransform? transform,
  }) {
    final latitude = location.position.latitude;
    final longitude = location.position.longitude;
    final position = _project(
      latitude,
      longitude,
      frame.logicalSize,
      transform,
    );
    if (position == null) return null;
    final heading = location.headingDegrees;
    final pitchScale = math.cos(frame.camera.tilt * math.pi / 180).abs();
    final direction = heading == null
        ? null
        : (heading - frame.camera.bearing) * math.pi / 180;
    final vector = direction == null
        ? null
        : Offset(math.sin(direction), -math.cos(direction) * pitchScale);
    final accuracy = location.accuracyMeters;
    final polygon = <Offset>[];
    if (accuracy != null && accuracy > 0) {
      final metersPerPixel =
          math.cos(
            latitude.clamp(-85.0511287798066, 85.0511287798066) * math.pi / 180,
          ) *
          2 *
          math.pi *
          _earthRadius /
          (512 * math.pow(2, frame.camera.zoom));
      final diameter = accuracy / metersPerPixel * 2;
      if (diameter.isFinite) {
        // The native location view rounds its accuracy diameter in logical
        // pixels before applying the camera pitch transform.
        final radius = diameter.roundToDouble() / 2;
        for (var index = 0; index < 64; index++) {
          final angle = index * math.pi * 2 / 64;
          polygon.add(
            position +
                Offset(
                  math.sin(angle) * radius,
                  -math.cos(angle) * radius * pitchScale,
                ),
          );
        }
      }
    }

    return UserLocationProjection._(
      location: location,
      frame: frame,
      position: position,
      headingVector:
          vector != null && _finite(vector) && vector.distanceSquared > 1e-12
          ? vector
          : null,
      accuracyPolygon: List.unmodifiable(polygon),
    );
  }

  /// Scales the cached geometry to the current Flutter layout.
  MapUserLocationRenderState forLayout(Size size) {
    final scaleX = size.width / frame.logicalSize.width;
    final scaleY = size.height / frame.logicalSize.height;
    Offset scale(Offset value) => Offset(value.dx * scaleX, value.dy * scaleY);
    final vector = headingVector == null ? null : scale(headingVector!);

    return MapUserLocationRenderState(
      location: location,
      frame: frame,
      screenPosition: scale(position),
      viewportSize: size,
      headingRadians: vector == null ? null : math.atan2(vector.dx, -vector.dy),
      accuracyPolygon: accuracyPolygon.map(scale).toList(growable: false),
    );
  }
}

const _earthRadius = 6378137.0;

bool _finite(Offset point) => point.dx.isFinite && point.dy.isFinite;

Offset? _project(
  double latitude,
  double longitude,
  Size viewport,
  FrameMapTransform? transform,
) {
  if (transform == null ||
      !transform.worldSize.isFinite ||
      transform.worldSize <= 0 ||
      !transform.originX.isFinite ||
      !transform.originY.isFinite ||
      transform.viewProjectionMatrix.length != 16 ||
      !viewport.isFinite ||
      viewport.isEmpty) {
    return null;
  }
  final worldSize = transform.worldSize;
  var x = (longitude + 180) / 360 * worldSize - transform.originX;
  final halfWorld = worldSize / 2;
  if (x > halfWorld) {
    x -= ((x - halfWorld) / worldSize).ceilToDouble() * worldSize;
  } else if (x < -halfWorld) {
    x += ((-halfWorld - x) / worldSize).ceilToDouble() * worldSize;
  }
  final sinLatitude = math.sin(
    latitude.clamp(-85.0511287798066, 85.0511287798066) * math.pi / 180,
  );
  final y =
      (0.5 - math.log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * math.pi)) *
          worldSize -
      transform.originY;
  final matrix = transform.viewProjectionMatrix;
  final clipX = matrix[0] * x + matrix[4] * y + matrix[12];
  final clipY = matrix[1] * x + matrix[5] * y + matrix[13];
  final clipW = matrix[3] * x + matrix[7] * y + matrix[15];
  if (!clipW.isFinite || clipW <= 0) return null;
  final position = Offset(
    (clipX + clipW) * viewport.width / (2 * clipW),
    (clipW - clipY) * viewport.height / (2 * clipW),
  );

  return _finite(position) ? position : null;
}
