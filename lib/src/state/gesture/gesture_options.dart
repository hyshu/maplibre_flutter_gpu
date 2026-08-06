import 'package:flutter/foundation.dart';

/// Configures map gesture animation, thresholds, and sensitivity.
@immutable
class MapGestureOptions {
  const MapGestureOptions({
    this.flingEnabled = true,
    this.flingDuration = const Duration(milliseconds: 998),
    this.flingVelocityThreshold = 100,
    this.scrollWheelZoomRate = 0.03,
    this.quickZoomEnabled = true,
    this.quickZoomSensitivity = 0.01,
    this.doubleTapZoomDuration = const Duration(milliseconds: 300),
  }) : assert(
         flingVelocityThreshold >= 0 &&
             flingVelocityThreshold < double.infinity,
       ),
       assert(scrollWheelZoomRate > 0 && scrollWheelZoomRate < 1),
       assert(
         quickZoomSensitivity > 0 && quickZoomSensitivity < double.infinity,
       );

  /// Whether a pan gesture may continue as a fling.
  final bool flingEnabled;

  /// Duration of a fling animation.
  final Duration flingDuration;

  /// Minimum pan speed in logical pixels per second that starts a fling.
  final double flingVelocityThreshold;

  /// Fractional zoom change applied for each scroll wheel event.
  final double scrollWheelZoomRate;

  /// Whether dragging after the second tap performs quick zoom.
  final bool quickZoomEnabled;

  /// Zoom sensitivity per logical pixel of quick-zoom movement.
  final double quickZoomSensitivity;

  /// Duration of zoom animations started by tap gestures.
  final Duration doubleTapZoomDuration;

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
