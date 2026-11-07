import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show immutable;

import '../gpu/render_context.dart';
import 'camera.dart';

/// Immutable camera and viewport metadata for an adopted native frame.
///
/// Flutter presentation and map resource loading progress are independent of
/// this state.
@immutable
class const MapFrameState({
  /// The camera used to produce the native frame.
  required final CameraPosition camera,

  /// Native viewport dimensions in logical pixels.
  required final Size logicalSize,

  /// Native render target dimensions in physical pixels.
  ///
  /// These dimensions include native rounding and need not equal [logicalSize]
  /// multiplied by [devicePixelRatio].
  required final Size physicalSize,

  /// The pixel ratio adopted by the native map for its lifetime.
  ///
  /// This can differ from the current display's pixel ratio.
  required final double devicePixelRatio,

  /// A monotonically increasing identifier within one map's lifetime.
  ///
  /// Values from separate map instances are unrelated.
  required final int sequence,

  /// Map-space projection for this exact adopted frame, when available.
  ///
  /// The matrix accepts origin-relative world pixels for X/Y and meters above
  /// sea level for Z. Use [MapLibreGpuMapTransform.project] for geographic
  /// coordinates. Native data is copied into Dart and may be retained after
  /// the frame callback. Treat the matrix as read-only.
  ///
  /// This is null when the native renderer does not provide a transform.
  /// Frame equality compares transforms by snapshot identity.
  final MapLibreGpuMapTransform? mapTransform,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapFrameState &&
          other.camera == camera &&
          other.logicalSize == logicalSize &&
          other.physicalSize == physicalSize &&
          other.devicePixelRatio == devicePixelRatio &&
          other.sequence == sequence &&
          identical(other.mapTransform, mapTransform);

  @override
  int get hashCode => Object.hash(
    camera,
    logicalSize,
    physicalSize,
    devicePixelRatio,
    sequence,
    mapTransform,
  );

  @override
  String toString() =>
      'MapFrameState(camera: $camera, logicalSize: $logicalSize, '
      'physicalSize: $physicalSize, devicePixelRatio: $devicePixelRatio, '
      'sequence: $sequence)';
}
