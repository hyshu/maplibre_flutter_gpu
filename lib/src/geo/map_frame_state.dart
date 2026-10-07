import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show immutable;

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
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapFrameState &&
          other.camera == camera &&
          other.logicalSize == logicalSize &&
          other.physicalSize == physicalSize &&
          other.devicePixelRatio == devicePixelRatio &&
          other.sequence == sequence;

  @override
  int get hashCode => Object.hash(
    camera,
    logicalSize,
    physicalSize,
    devicePixelRatio,
    sequence,
  );

  @override
  String toString() =>
      'MapFrameState(camera: $camera, logicalSize: $logicalSize, '
      'physicalSize: $physicalSize, devicePixelRatio: $devicePixelRatio, '
      'sequence: $sequence)';
}
