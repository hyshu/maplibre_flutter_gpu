part of '../visual_e2e_shared.dart';

const bool visualE2ePerformanceEnabled = bool.fromEnvironment(
  'VISUAL_E2E_PERFORMANCE',
);

const String visualE2ePerformanceEnvironment = String.fromEnvironment(
  'VISUAL_E2E_PERFORMANCE_ENVIRONMENT',
  defaultValue: 'local',
);

final VisualE2ePerformanceProbe visualE2ePerformanceProbe =
    VisualE2ePerformanceProbe();

typedef VisualE2eCameraAnimator = Future<void> Function(
  VisualCamera camera,
  Duration duration,
);

const _performanceAnimationDuration = Duration(milliseconds: 900);
const _performanceWarmUpRoundTrips = 1;
const _performanceMeasuredRoundTrips = 3;
const _frameBudgetMicros = 16667;

Future<Map<String, Object?>> runVisualE2eCameraBenchmark({
  required VisualE2eCameraAnimator animateCamera,
}) async {
  if (visualE2eSceneId != 'flutter-markers') {
    throw StateError(
      'visual performance is calibrated for flutter-markers only',
    );
  }
  final zoom = visualE2eZoom ?? 13;
  final cameraA = VisualCamera(
    latitude: 35.6812,
    longitude: 139.7671,
    zoom: zoom,
    bearing: 0,
    tilt: 0,
  );
  final cameraB = VisualCamera(
    latitude: cameraA.latitude,
    longitude: cameraA.longitude,
    zoom: cameraA.zoom + 0.75,
    bearing: 20,
    tilt: 20,
  );

  for (var i = 0; i < _performanceWarmUpRoundTrips; i++) {
    await animateCamera(cameraB, _performanceAnimationDuration);
    await animateCamera(cameraA, _performanceAnimationDuration);
  }

  final metrics = await visualE2ePerformanceProbe.measure(() async {
    for (var i = 0; i < _performanceMeasuredRoundTrips; i++) {
      await visualE2ePerformanceProbe.recordAnimation(
        () => animateCamera(cameraB, _performanceAnimationDuration),
      );
      await visualE2ePerformanceProbe.recordAnimation(
        () => animateCamera(cameraA, _performanceAnimationDuration),
      );
    }
  });
  return {
    'environment': visualE2ePerformanceEnvironment,
    'build_mode': kProfileMode
        ? 'profile'
        : kReleaseMode
        ? 'release'
        : 'debug',
    'scene': visualE2eSceneId,
    'zoom': zoom,
    'animation_duration_millis': _performanceAnimationDuration.inMilliseconds,
    'warm_up_round_trips': _performanceWarmUpRoundTrips,
    'measured_round_trips': _performanceMeasuredRoundTrips,
    ...metrics,
  };
}

class VisualE2ePerformanceProbe {
  final _cameraUpdateSegments = <List<int>>[];
  final _cameraApplyDurationsMicros = <int>[];
  final _animationDurationsMicros = <int>[];
  final _frameTimings = <ui.FrameTiming>[];
  Stopwatch? _animationWatch;
  List<int>? _activeCameraUpdates;

  void recordCameraStep(Duration applyDuration) {
    final watch = _animationWatch;
    final updates = _activeCameraUpdates;
    if (watch != null && updates != null) {
      updates.add(watch.elapsedMicroseconds);
      _cameraApplyDurationsMicros.add(applyDuration.inMicroseconds);
    }
  }

  Future<void> recordAnimation(Future<void> Function() action) async {
    if (_activeCameraUpdates != null) {
      throw StateError('visual performance animations cannot overlap');
    }
    final updates = <int>[];
    final watch = Stopwatch()..start();
    _cameraUpdateSegments.add(updates);
    _activeCameraUpdates = updates;
    _animationWatch = watch;
    try {
      await action();
    } finally {
      watch.stop();
      _animationDurationsMicros.add(watch.elapsedMicroseconds);
      _activeCameraUpdates = null;
      _animationWatch = null;
    }
  }

  Future<Map<String, Object?>> measure(Future<void> Function() action) async {
    _cameraUpdateSegments.clear();
    _cameraApplyDurationsMicros.clear();
    _animationDurationsMicros.clear();
    _frameTimings.clear();

    // The engine batches FrameTiming delivery. Let pre-benchmark timings flush
    // before registering, then wait once after the workload for the last batch.
    await Future<void>.delayed(const Duration(seconds: 1));
    void callback(List<ui.FrameTiming> timings) {
      _frameTimings.addAll(timings);
    }

    WidgetsBinding.instance.addTimingsCallback(callback);
    final total = Stopwatch()..start();
    try {
      await action();
    } finally {
      total.stop();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      WidgetsBinding.instance.removeTimingsCallback(callback);
    }

    final cameraIntervals = <int>[
      for (final segment in _cameraUpdateSegments)
        for (var i = 1; i < segment.length; i++) segment[i] - segment[i - 1],
    ];
    final cameraSpanMicros = _cameraUpdateSegments.fold<int>(
      0,
      (sum, segment) =>
          sum + (segment.length < 2 ? 0 : segment.last - segment.first),
    );
    final buildTimes = <int>[
      for (final timing in _frameTimings) timing.buildDuration.inMicroseconds,
    ];
    final rasterTimes = <int>[
      for (final timing in _frameTimings) timing.rasterDuration.inMicroseconds,
    ];
    final jankyFlutterFrames = [
      for (var i = 0; i < buildTimes.length; i++)
        if (buildTimes[i] > _frameBudgetMicros ||
            rasterTimes[i] > _frameBudgetMicros)
          i,
    ].length;
    final cameraUpdateCount = _cameraUpdateSegments.fold<int>(
      0,
      (sum, segment) => sum + segment.length,
    );

    return {
      'animation_count': _cameraUpdateSegments.length,
      'total_measurement_millis': total.elapsedMicroseconds / 1000,
      'average_animation_elapsed_millis':
          _average(_animationDurationsMicros) / 1000,
      'p90_animation_elapsed_millis':
          _percentile(_animationDurationsMicros, 0.90) / 1000,
      'camera_step_count': cameraUpdateCount,
      'average_camera_steps_per_animation': _cameraUpdateSegments.isEmpty
          ? 0
          : cameraUpdateCount / _cameraUpdateSegments.length,
      'camera_step_fps': cameraSpanMicros == 0
          ? 0
          : cameraIntervals.length *
                Duration.microsecondsPerSecond /
                cameraSpanMicros,
      'average_camera_apply_time_millis':
          _average(_cameraApplyDurationsMicros) / 1000,
      'p90_camera_apply_time_millis':
          _percentile(_cameraApplyDurationsMicros, 0.90) / 1000,
      'p99_camera_apply_time_millis':
          _percentile(_cameraApplyDurationsMicros, 0.99) / 1000,
      'average_camera_step_interval_millis': _average(cameraIntervals) / 1000,
      'p90_camera_step_interval_millis':
          _percentile(cameraIntervals, 0.90) / 1000,
      'p99_camera_step_interval_millis':
          _percentile(cameraIntervals, 0.99) / 1000,
      'camera_step_interval_over_16_7ms_count': cameraIntervals
          .where((value) => value > _frameBudgetMicros)
          .length,
      'camera_step_interval_over_33_3ms_count': cameraIntervals
          .where((value) => value > _frameBudgetMicros * 2)
          .length,
      'flutter_frame_count': _frameTimings.length,
      'average_flutter_build_time_millis': _average(buildTimes) / 1000,
      'p50_flutter_build_time_millis': _percentile(buildTimes, 0.50) / 1000,
      'p90_flutter_build_time_millis': _percentile(buildTimes, 0.90) / 1000,
      'p99_flutter_build_time_millis': _percentile(buildTimes, 0.99) / 1000,
      'average_flutter_raster_time_millis': _average(rasterTimes) / 1000,
      'p50_flutter_raster_time_millis': _percentile(rasterTimes, 0.50) / 1000,
      'p90_flutter_raster_time_millis': _percentile(rasterTimes, 0.90) / 1000,
      'p99_flutter_raster_time_millis': _percentile(rasterTimes, 0.99) / 1000,
      'flutter_janky_frame_count': jankyFlutterFrames,
      'flutter_janky_frame_percent': _frameTimings.isEmpty
          ? 0
          : jankyFlutterFrames * 100 / _frameTimings.length,
    };
  }
}

double _average(List<int> values) => values.isEmpty
    ? 0
    : values.reduce((left, right) => left + right) / values.length;

int _percentile(List<int> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = List.of(values)..sort();

  return sorted[((sorted.length - 1) * percentile).round()];
}
