// Converts raw gesture measurements into camera movement.
import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Offset;

/// Resolves double-click zoom against the general zoom setting.
bool doubleClickZoomIsEnabled(
  bool? doubleClickZoomEnabled,
  bool zoomGesturesEnabled,
) => doubleClickZoomEnabled ?? zoomGesturesEnabled;

/// Converts a rotation in radians to a bearing delta in degrees.
double bearingGestureDelta(double rotationDelta) =>
    -rotationDelta * 180 / math.pi;

/// Converts cumulative trackpad scales into an incremental scale factor.
///
/// Returns 1 when either scale is invalid.
double trackpadScaleDelta(double currentScale, double previousScale) {
  if (!currentScale.isFinite ||
      !previousScale.isFinite ||
      currentScale <= 0 ||
      previousScale <= 0) {
    return 1;
  }
  return currentScale / previousScale;
}

/// Converts vertical mouse movement into pitch degrees.
double mouseTiltDelta(double verticalDelta) => -verticalDelta * 0.5;

/// Converts horizontal mouse movement into bearing degrees.
double mouseRotateDelta(double horizontalDelta) => horizontalDelta * 0.5;

/// Converts vertical quick-zoom movement into an exponential scale factor.
///
/// Returns 1 when the movement or sensitivity is invalid.
double quickZoomScaleDelta(double verticalDelta, {double sensitivity = 0.01}) {
  if (!verticalDelta.isFinite || !sensitivity.isFinite || sensitivity <= 0) {
    return 1;
  }
  return math.exp(verticalDelta * sensitivity);
}

/// Returns a tilt delta for a predominantly vertical two-finger gesture.
///
/// Returns null when the movement is better interpreted as zoom, rotation, or
/// horizontal motion.
double? tiltGestureDelta({
  required Offset focalPointDelta,
  required double scaleDelta,
  required double rotationDelta,
  required bool fingersApproximatelyHorizontal,
  double minimumVerticalDelta = 1,
}) {
  if (!fingersApproximatelyHorizontal) return null;
  if ((scaleDelta - 1).abs() >= 0.015 || rotationDelta.abs() >= 0.015) {
    return null;
  }
  if (focalPointDelta.dy.abs() <= focalPointDelta.dx.abs() * math.sqrt(3) ||
      focalPointDelta.dy.abs() < minimumVerticalDelta) {
    return null;
  }
  return -focalPointDelta.dy * 0.5;
}
