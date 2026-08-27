import 'package:flutter/foundation.dart';

/// Configures map gesture animation, thresholds, and sensitivity.
@immutable
class const MapGestureOptions({
  /// Whether a pan gesture may continue as a fling.
  final bool flingEnabled = true,

  /// Duration of a fling animation.
  final Duration flingDuration = const Duration(milliseconds: 998),

  /// Minimum pan speed in logical pixels per second that starts a fling.
  final double flingVelocityThreshold = 100,

  /// Fractional zoom change applied for each scroll wheel event.
  final double scrollWheelZoomRate = 0.03,

  /// Whether dragging after the second tap performs quick zoom.
  final bool quickZoomEnabled = true,

  /// Zoom sensitivity per logical pixel of quick-zoom movement.
  final double quickZoomSensitivity = 0.01,

  /// Duration of zoom animations started by tap gestures.
  final Duration doubleTapZoomDuration = const Duration(milliseconds: 300),
}) {
  this
    : assert(
        flingVelocityThreshold >= 0 && flingVelocityThreshold < double.infinity,
      ),
      assert(scrollWheelZoomRate > 0 && scrollWheelZoomRate < 1),
      assert(
        quickZoomSensitivity > 0 && quickZoomSensitivity < double.infinity,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapGestureOptions &&
          other.flingEnabled == flingEnabled &&
          other.flingDuration == flingDuration &&
          other.flingVelocityThreshold == flingVelocityThreshold &&
          other.scrollWheelZoomRate == scrollWheelZoomRate &&
          other.quickZoomEnabled == quickZoomEnabled &&
          other.quickZoomSensitivity == quickZoomSensitivity &&
          other.doubleTapZoomDuration == doubleTapZoomDuration;

  @override
  int get hashCode => Object.hash(
    flingEnabled,
    flingDuration,
    flingVelocityThreshold,
    scrollWheelZoomRate,
    quickZoomEnabled,
    quickZoomSensitivity,
    doubleTapZoomDuration,
  );
}
