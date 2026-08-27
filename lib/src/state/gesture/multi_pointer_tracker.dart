// Interprets raw pointer positions as multi-pointer camera updates.
// This tracker reports camera changes without applying them.
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'gesture_math.dart';

/// How a multi-pointer gesture has been interpreted so far.
enum TwoFingerGestureMode {
  /// Two fingers are down but have not moved far enough to mean anything.
  undecided,

  /// Two fingers are pinching and/or rotating.
  transform,

  /// Three fingers are down and vertical movement tilts.
  tilt,
}

/// The camera change one frame of pointer movement asks for.
///
/// Each property is optional and reports only the movement that was recognized.
class const MultiPointerCameraUpdate({
  /// Pitch change in degrees.
  final double? tiltDelta,

  /// Zoom factor, applied about [scaleFocus].
  final double? scale,

  /// Logical map position used as the center of [scale].
  final Offset? scaleFocus,

  /// Rotation in radians, before conversion to a bearing delta.
  final double? rotationDelta,
});

/// Returns the signed shortest difference between two angles in radians.
double normalizedAngleDelta(double current, double previous) =>
    (current - previous + math.pi) % (2 * math.pi) - math.pi;

/// Tracks pointer geometry and produces multi-pointer camera updates.
class MultiPointerTracker {
  /// Distance in logical pixels a pinch or pan must cover to commit.
  static const _transformThreshold = 4.0;

  /// Rotation required to commit a two-finger gesture.
  static const _rotationThreshold = math.pi / 60;

  /// Below this, a scale or rotation is noise from finger jitter.
  static const _changeEpsilon = 0.001;

  final Map<int, Offset> _positions = <int, Offset>{};
  final Map<int, Offset> _startPositions = <int, Offset>{};
  Offset? _previousCenter;
  double? _previousDistance;
  double? _previousAngle;
  TwoFingerGestureMode _mode = TwoFingerGestureMode.undecided;

  /// Number of pointers currently being tracked.
  int get pointerCount => _positions.length;

  /// Whether the current pointer set is one this tracker interprets.
  bool get isMultiPointer => _positions.length == 2 || _positions.length == 3;

  /// Current interpretation of the multi-pointer gesture.
  TwoFingerGestureMode get mode => _mode;

  /// Adds a pointer and initializes a baseline when its set is supported.
  void down(int pointer, Offset position) {
    _positions[pointer] = position;
    _resetBaseline();
  }

  /// Updates the current position of a pointer.
  void move(int pointer, Offset position) => _positions[pointer] = position;

  /// Removes a lifted pointer.
  ///
  /// A remaining two-pointer or three-pointer set starts again from its current
  /// positions instead of retaining a baseline that included the lifted
  /// pointer.
  void up(int pointer) {
    _positions.remove(pointer);
    _resetBaseline();
  }

  void _resetBaseline() {
    if (!isMultiPointer) {
      _startPositions.clear();
      _previousCenter = null;
      _previousDistance = null;
      _previousAngle = null;
      _mode = TwoFingerGestureMode.undecided;

      return;
    }
    _startPositions
      ..clear()
      ..addAll(_positions);
    final points = _positions.values.toList(growable: false);
    _previousCenter =
        points.fold(Offset.zero, (a, b) => a + b) / points.length.toDouble();
    if (points.length == 2) {
      final difference = points[1] - points[0];
      _previousDistance = difference.distance;
      _previousAngle = difference.direction;
      _mode = TwoFingerGestureMode.undecided;
    } else {
      // Three fingers are unambiguous: no threshold to clear.
      _previousDistance = null;
      _previousAngle = null;
      _mode = TwoFingerGestureMode.tilt;
    }
  }

  /// Consumes the movement since the previous call.
  ///
  /// Returns null when the pointer count is unsupported, the gesture remains
  /// undecided, or movement is below the noise threshold. The baseline still
  /// advances so later updates do not include previously ignored movement.
  MultiPointerCameraUpdate? evaluate({
    required bool zoomEnabled,
    required bool rotateEnabled,
    required bool tiltEnabled,
  }) {
    final count = _positions.length;
    if (count != 2 && count != 3) return null;
    final ids = _startPositions.keys.toList(growable: false);
    // A changed pointer set has no valid baseline. Wait for down or up to
    // rebuild it.
    if (ids.length != count || ids.any((id) => !_positions.containsKey(id))) {
      return null;
    }

    if (count == 3) {
      final points = ids.map((id) => _positions[id]!).toList(growable: false);
      final currentCenter = points.fold(Offset.zero, (a, b) => a + b) / 3.0;
      final tiltDelta = tiltEnabled
          ? tiltGestureDelta(
              focalPointDelta: currentCenter - _previousCenter!,
              scaleDelta: 1,
              rotationDelta: 0,
              fingersApproximatelyHorizontal: true,
              minimumVerticalDelta: 0,
            )
          : null;
      _previousCenter = currentCenter;
      if (tiltDelta == null) return null;

      return MultiPointerCameraUpdate(tiltDelta: tiltDelta);
    }

    final startA = _startPositions[ids[0]]!;
    final startB = _startPositions[ids[1]]!;
    final currentA = _positions[ids[0]]!;
    final currentB = _positions[ids[1]]!;
    final translation = (currentA + currentB) / 2 - (startA + startB) / 2;
    final currentCenter = (currentA + currentB) / 2;
    final currentDifference = currentB - currentA;
    final currentDistance = currentDifference.distance;
    final currentAngle = currentDifference.direction;
    final startDifference = startB - startA;
    final startDistance = startDifference.distance;
    final rotationFromStart = normalizedAngleDelta(
      currentAngle,
      startDifference.direction,
    );

    if (_mode == TwoFingerGestureMode.undecided) {
      // Commitment lasts for the gesture. Returning to the starting positions
      // does not restore the undecided mode.
      final pinchRecognized =
          zoomEnabled &&
          (currentDistance - startDistance).abs() >= _transformThreshold;
      final rotationRecognized =
          rotateEnabled && rotationFromStart.abs() >= _rotationThreshold;
      if (pinchRecognized ||
          rotationRecognized ||
          translation.distance >= _transformThreshold) {
        _mode = TwoFingerGestureMode.transform;
      }
    }

    double? scale;
    double? rotation;
    if (_mode == TwoFingerGestureMode.transform) {
      final previousDistance = _previousDistance!;
      if (zoomEnabled && previousDistance > 0) {
        final frameScale = currentDistance / previousDistance;
        if ((frameScale - 1).abs() > _changeEpsilon) scale = frameScale;
      }
      if (rotateEnabled) {
        final frameRotation = normalizedAngleDelta(
          currentAngle,
          _previousAngle!,
        );
        if (frameRotation.abs() > _changeEpsilon) rotation = frameRotation;
      }
    }

    _previousCenter = currentCenter;
    _previousDistance = currentDistance;
    _previousAngle = currentAngle;
    if (scale == null && rotation == null) return null;

    return MultiPointerCameraUpdate(
      scale: scale,
      scaleFocus: currentCenter,
      rotationDelta: rotation,
    );
  }
}
