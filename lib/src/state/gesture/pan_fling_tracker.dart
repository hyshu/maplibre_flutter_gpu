// Estimates pan velocity and converts fling progress into camera movement.
import 'dart:ui' show Offset;

import 'package:flutter/animation.dart' show Cubic;

/// A pan delta in logical pixels and the time it was recorded.
typedef PanSample = ({Offset delta, DateTime time});

/// Tracks recent pan movement and calculates fling movement.
class PanFlingTracker {
  /// Default minimum speed in logical pixels per second for starting a fling.
  static const flingThreshold = 100.0;

  /// How many pan deltas the velocity estimate averages over.
  static const _maxPanSamples = 5;

  /// Minimum time span required for velocity estimation.
  static const _minimumSampleSeconds = 0.005;

  /// Converts initial velocity into total fling distance.
  static const _flingDamping = 0.998 / 4.0;

  // Mouse inertia uses logical pixels and seconds.
  static const _mouseLinearity = 0.3;
  static const _mouseDeceleration = 2500.0;
  static const _mouseMaxSpeed = 1400.0;
  static const _mouseEasing = Cubic(0, 0, 0.3, 1);

  /// Minimum visible movement in logical pixels.
  static const _minimumMoveDelta = 0.01;

  final _panSamples = <PanSample>[];
  var _flingDistance = Offset.zero;
  var _mouseFling = false;
  var _previousProgress = 0.0;

  /// Records a pan delta and retains only the recent sample window.
  void addPanSample(Offset delta, DateTime time) {
    _panSamples.add((delta: delta, time: time));
    if (_panSamples.length > _maxPanSamples) _panSamples.removeAt(0);
  }

  /// Clears the movement history used for velocity estimation.
  void clearPanSamples() => _panSamples.clear();

  /// Estimates average velocity in logical pixels per second.
  ///
  /// The first sample establishes the start time. Returns zero when the sample
  /// window is too small.
  Offset estimateVelocity() {
    if (_panSamples.length < 2) return .zero;
    final seconds =
        _panSamples.last.time
            .difference(_panSamples.first.time)
            .inMicroseconds /
        1e6;
    if (seconds < _minimumSampleSeconds) return .zero;
    var totalDx = 0.0;
    var totalDy = 0.0;
    for (final sample in _panSamples.skip(1)) {
      totalDx += sample.delta.dx;
      totalDy += sample.delta.dy;
    }
    return .new(totalDx / seconds, totalDy / seconds);
  }

  /// Whether [velocity] exceeds the fling threshold.
  bool isFling(Offset velocity, {double threshold = flingThreshold}) =>
      velocity.distance > threshold;

  /// Starts fling calculations with [velocity] as the initial velocity.
  void beginFling(Offset velocity) {
    _flingDistance = velocity * _flingDamping;
    _mouseFling = false;
    _previousProgress = 0;
  }

  /// Starts a mouse drag fling and returns its speed-dependent duration.
  ///
  /// Velocity uses logical pixels per second. Distance and easing follow
  /// MapLibre GL JS drag inertia. Zero velocity produces no movement.
  Duration beginMouseFling(Offset velocity) {
    _mouseFling = true;
    _previousProgress = 0;
    final magnitude = velocity.distance;
    if (magnitude == 0) {
      _flingDistance = Offset.zero;

      return Duration.zero;
    }
    final speed = (magnitude * _mouseLinearity).clamp(0.0, _mouseMaxSpeed);
    final seconds = speed / (_mouseDeceleration * _mouseLinearity);
    _flingDistance = velocity / magnitude * (speed * seconds / 2);

    return Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round(),
    );
  }

  /// Converts normalized animation progress [t] into incremental movement.
  ///
  /// Returns null when the movement is below the visible threshold. Progress
  /// is consumed even when no movement is returned.
  Offset? advance(double t) {
    final eased = _mouseFling
        ? _mouseEasing.transform(t)
        : 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
    final step = eased - _previousProgress;
    _previousProgress = eased;
    final dx = _flingDistance.dx * step;
    final dy = _flingDistance.dy * step;
    if (dx.abs() <= _minimumMoveDelta && dy.abs() <= _minimumMoveDelta) {
      return null;
    }
    return .new(dx, dy);
  }
}
