import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const String _visualE2eConfiguredSceneId = String.fromEnvironment(
  'VISUAL_E2E_SCENE',
  defaultValue: 'geometry',
);

const String _visualE2eConfiguredSceneIds = String.fromEnvironment(
  'VISUAL_E2E_SCENES',
);

const String visualE2eRunToken = String.fromEnvironment(
  'VISUAL_E2E_RUN_TOKEN',
  defaultValue: 'local',
);

bool _visualE2eProcessIdentityLogged = false;

/// Scenes compared between maplibre_gl and maplibre_flutter_gpu on mobile.
const List<String> visualE2eParitySceneIds = <String>[
  'geometry',
  'text-symbol',
  'symbol-data-driven-paint',
  'symbol-paint-update',
  'symbol-line-pitch',
  'symbol-icon-effects',
  'symbol-layer-order',
  'symbol-z-order',
  'symbol-text-shaping',
  '3d-buildings',
  'mvt',
  'tilejson-mvt',
  'image-source',
  'geojson-url',
  'raster-jpeg',
  'raster-webp',
  'raster-tms',
  'wmts',
];

/// Offline scenes supported by the maplibre_flutter_gpu desktop fixture.
const List<String> visualE2eDesktopSceneIds = <String>[
  'geometry',
  'text-symbol',
  '3d-buildings',
  'line-variants',
  'raster-pattern',
  'mvt',
  'mlt',
  'tilejson-mvt',
  'pmtiles-raster',
  'mbtiles-raster',
  'image-source',
  'geojson-url',
  'raster-jpeg',
  'raster-webp',
  'raster-tms',
  'wmts',
  'pmtiles-vector',
  'pmtiles-mlt',
  'mbtiles-vector',
  'mbtiles-mlt',
];

/// Desktop scenes that require an exact image baseline and command coverage.
const List<String> visualE2eStrictDesktopSceneIds = <String>[
  'geometry',
  'text-symbol',
  '3d-buildings',
  'line-variants',
  'raster-pattern',
];

final Set<String> _visualE2eSceneIds = <String>{
  ...visualE2eParitySceneIds,
  ...visualE2eDesktopSceneIds,
  'flutter-markers',
};

String? _visualE2eRuntimeSceneId;

/// Active scene selected by an explicit override, launch route, or Dart define.
String get visualE2eSceneId {
  final runtimeSceneId = _visualE2eRuntimeSceneId;
  if (runtimeSceneId != null) return runtimeSceneId;

  final routeSceneId = visualE2eSceneIdFromRoute(
    ui.PlatformDispatcher.instance.defaultRouteName,
  );

  return routeSceneId ?? _visualE2eConfiguredSceneId;
}

/// Ordered scenes configured for the current integration-test process.
///
/// Invalid or duplicate identifiers throw [ArgumentError].
List<String> get visualE2eSuiteSceneIds {
  if (_visualE2eConfiguredSceneIds.trim().isEmpty) {
    return <String>[visualE2eSceneId];
  }

  return parseVisualE2eSceneIds(_visualE2eConfiguredSceneIds);
}

/// Sets the active scene for a test iteration. Passing null clears the override.
///
/// An unsupported identifier throws [ArgumentError].
void setVisualE2eRuntimeSceneId(String? sceneId) {
  if (sceneId != null && !_visualE2eSceneIds.contains(sceneId)) {
    throw ArgumentError.value(sceneId, 'sceneId', 'unknown visual E2E scene');
  }
  _visualE2eRuntimeSceneId = sceneId;
}

/// Parses a comma-separated, unique list of supported scene identifiers.
///
/// Empty, unsupported, or duplicate identifiers throw [ArgumentError].
List<String> parseVisualE2eSceneIds(String value) {
  final sceneIds = value
      .split(',')
      .map((sceneId) => sceneId.trim())
      .toList(growable: false);
  if (sceneIds.isEmpty || sceneIds.any((sceneId) => sceneId.isEmpty)) {
    throw ArgumentError.value(value, 'value', 'visual E2E scene list is empty');
  }
  final seen = <String>{};
  for (final sceneId in sceneIds) {
    if (!_visualE2eSceneIds.contains(sceneId)) {
      throw ArgumentError.value(sceneId, 'value', 'unknown visual E2E scene');
    }
    if (!seen.add(sceneId)) {
      throw ArgumentError.value(sceneId, 'value', 'duplicate visual E2E scene');
    }
  }

  return sceneIds;
}

/// Extracts a supported scene from a platform launch route.
///
/// Both `/visual-e2e/geometry` and `?scene=geometry` forms are accepted.
/// Unsupported or empty routes return null.
String? visualE2eSceneIdFromRoute(String route) {
  final trimmed = route.trim();
  if (trimmed.isEmpty || trimmed == '/') return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  final querySceneId = uri.queryParameters['scene'];
  if (querySceneId != null && _visualE2eSceneIds.contains(querySceneId)) {
    return querySceneId;
  }

  final segments = uri.pathSegments.where((value) => value.isNotEmpty).toList();
  final pathSceneId = segments.isEmpty ? uri.host : segments.last;
  if (_visualE2eSceneIds.contains(pathSceneId)) return pathSceneId;

  if (_visualE2eSceneIds.contains(trimmed)) return trimmed;

  return null;
}

const String _visualE2eZoomValue = String.fromEnvironment('VISUAL_E2E_ZOOM');

double? get visualE2eZoom => double.tryParse(_visualE2eZoomValue);

const String visualE2eReadyPrefix = 'VISUAL_E2E_READY';

const bool visualE2ePerformanceEnabled = bool.fromEnvironment(
  'VISUAL_E2E_PERFORMANCE',
);

const String visualE2ePerformanceEnvironment = String.fromEnvironment(
  'VISUAL_E2E_PERFORMANCE_ENVIRONMENT',
  defaultValue: 'local',
);

final GlobalKey visualE2eRepaintBoundaryKey = GlobalKey(
  debugLabel: 'visual-e2e-repaint-boundary',
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
  return <String, Object?>{
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
  final List<List<int>> _cameraUpdateSegments = <List<int>>[];
  final List<int> _cameraApplyDurationsMicros = <int>[];
  final List<int> _animationDurationsMicros = <int>[];
  final List<ui.FrameTiming> _frameTimings = <ui.FrameTiming>[];
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
    final jankyFlutterFrames = <int>[
      for (var i = 0; i < buildTimes.length; i++)
        if (buildTimes[i] > _frameBudgetMicros ||
            rasterTimes[i] > _frameBudgetMicros)
          i,
    ].length;
    final cameraUpdateCount = _cameraUpdateSegments.fold<int>(
      0,
      (sum, segment) => sum + segment.length,
    );

    return <String, Object?>{
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

double _average(List<int> values) {
  if (values.isEmpty) return 0;

  return values.reduce((left, right) => left + right) / values.length;
}

int _percentile(List<int> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = List<int>.of(values)..sort();

  return sorted[((sorted.length - 1) * percentile).round()];
}

/// Identifies a PNG readback failure after Flutter produced a GPU image.
final class VisualE2eReadbackException implements Exception {
  /// Creates a readback failure that preserves the engine error.
  const VisualE2eReadbackException(this.cause);

  /// Error reported by `ui.Image.toByteData`.
  final Object cause;

  /// Whether Flutter reported the transient empty Impeller command status.
  bool get isTransientImpellerFailure =>
      cause is Exception && cause.toString().trim() == 'Exception:';

  @override
  String toString() => 'VISUAL_E2E_PNG_READBACK_FAILED: $cause';
}

/// Callback invoked before another PNG readback attempt.
typedef VisualE2eReadbackRetry = Future<void> Function(
  int failedAttempt,
  VisualE2eReadbackException error,
  StackTrace stackTrace,
);

/// Captures the visual viewport at the requested pixel ratio.
///
/// Only Flutter's empty transient Impeller readback error is retried. A retry
/// creates a fresh image from the repaint boundary. All other failures retain
/// their original stack trace.
Future<Uint8List> captureVisualE2ePng({
  double? pixelRatio,
  int readbackAttempts = 1,
  VisualE2eReadbackRetry? beforeReadbackRetry,
}) async {
  if (readbackAttempts < 1) {
    throw ArgumentError.value(
      readbackAttempts,
      'readbackAttempts',
      'must be at least one',
    );
  }
  final boundary =
      visualE2eRepaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('visual E2E repaint boundary is not mounted');
  }
  final ratio =
      pixelRatio ??
      WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

  for (var attempt = 1; attempt <= readbackAttempts; attempt += 1) {
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw const VisualE2eReadbackException(
            'PNG encoding returned no data',
          );
        }

        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } on VisualE2eReadbackException {
        rethrow;
      } catch (error, stackTrace) {
        Error.throwWithStackTrace(
          VisualE2eReadbackException(error),
          stackTrace,
        );
      }
    } on VisualE2eReadbackException catch (error, stackTrace) {
      if (!error.isTransientImpellerFailure || attempt == readbackAttempts) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      await beforeReadbackRetry?.call(attempt, error, stackTrace);
    } finally {
      image.dispose();
    }
  }

  throw StateError('visual E2E PNG readback exhausted unexpectedly');
}

typedef VisualMapBuilder = Widget Function(
  VisualScene scene,
  VoidCallback onMapIdle,
);

@immutable
class VisualCamera {
  const VisualCamera({
    required this.latitude,
    required this.longitude,
    required this.zoom,
    required this.bearing,
    required this.tilt,
  });

  final double latitude;
  final double longitude;
  final double zoom;
  final double bearing;
  final double tilt;
}

@immutable
class VisualScene {
  const VisualScene({
    required this.id,
    required this.styleJson,
    required this.camera,
    required this.backgroundColor,
  });

  final String id;
  final String styleJson;
  final VisualCamera camera;
  final Color backgroundColor;
}

class VisualTestStatus {
  VisualTestStatus._();

  static final ValueNotifier<bool> ready = ValueNotifier<bool>(false);
  static Timer? _settleTimer;
  static int _generation = 0;

  static int reset() {
    _settleTimer?.cancel();
    _settleTimer = null;
    ready.value = false;

    return ++_generation;
  }

  static void mapIdle({
    required String implementation,
    required String sceneId,
    required int generation,
  }) {
    if (generation != _generation || ready.value) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 750), () {
      if (generation != _generation) return;
      _settleTimer = null;
      ready.value = true;
      debugPrint('$visualE2eReadyPrefix|$implementation|$sceneId');
    });
  }
}

Future<VisualScene> loadVisualScene() async {
  const cameras = <String, VisualCamera>{
    'geometry': VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 13.25,
      bearing: 17,
      tilt: 28,
    ),
    'text-symbol': VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 0,
      tilt: 0,
    ),
    'symbol-data-driven-paint': VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 0,
      tilt: 0,
    ),
    'symbol-paint-update': VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 0,
      tilt: 0,
    ),
    'symbol-line-pitch': VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 13.9,
      bearing: 32,
      tilt: 45,
    ),
    'symbol-icon-effects': VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 18,
      tilt: 28,
    ),
    'symbol-layer-order': VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 0,
      tilt: 0,
    ),
    'symbol-z-order': VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 0,
      tilt: 0,
    ),
    'symbol-text-shaping': VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 0,
      tilt: 0,
    ),
    '3d-buildings': VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 15.15,
      bearing: 28,
      tilt: 20,
    ),
    'line-variants': VisualCamera(
      latitude: 35.6832,
      longitude: 139.7671,
      zoom: 13.6,
      bearing: 0,
      tilt: 0,
    ),
    'raster-pattern': VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 13.2,
      bearing: 0,
      tilt: 0,
    ),
    'mvt': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'tilejson-mvt': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'mlt': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'pmtiles-raster': VisualCamera(
      latitude: 20,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'mbtiles-raster': VisualCamera(
      latitude: 20,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'image-source': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'geojson-url': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'raster-jpeg': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'raster-webp': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'raster-tms': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 1,
      bearing: 0,
      tilt: 0,
    ),
    'wmts': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'pmtiles-vector': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'pmtiles-mlt': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'mbtiles-vector': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'mbtiles-mlt': VisualCamera(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'flutter-markers': VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 13,
      bearing: 0,
      tilt: 0,
    ),
  };
  final defaultCamera = cameras[visualE2eSceneId];
  if (defaultCamera == null) {
    throw ArgumentError.value(
      visualE2eSceneId,
      'VISUAL_E2E_SCENE',
      'unknown visual E2E scene',
    );
  }
  final zoom = visualE2eZoom;
  final camera = zoom == null
      ? defaultCamera
      : VisualCamera(
          latitude: defaultCamera.latitude,
          longitude: defaultCamera.longitude,
          zoom: zoom,
          bearing: defaultCamera.bearing,
          tilt: defaultCamera.tilt,
        );

  var styleJson = await _loadStyleJson(visualE2eSceneId);
  if (styleJson.contains(_assetBasePlaceholder)) {
    final assetServer = await _VisualAssetServer.start();
    styleJson = styleJson.replaceAll(
      _assetBasePlaceholder,
      assetServer.baseUri.toString().replaceFirst(RegExp(r'/$'), ''),
    );
  }
  for (final entry in _mbtilesPlaceholders.entries) {
    if (styleJson.contains(entry.key)) {
      final url = await _VisualAssetServer.materializeMbtiles(entry.value);
      styleJson = replaceJsonStringPlaceholder(styleJson, entry.key, url);
    }
  }
  return VisualScene(
    id: visualE2eSceneId,
    styleJson: styleJson,
    camera: camera,
    backgroundColor: const Color(0xffe7edf3),
  );
}

@visibleForTesting
String replaceJsonStringPlaceholder(
  String json,
  String placeholder,
  String value,
) {
  final encodedValue = jsonEncode(value);

  return json.replaceAll(
    placeholder,
    encodedValue.substring(1, encodedValue.length - 1),
  );
}

const _openFreeMapLibertyStyle = 'https://tiles.openfreemap.org/styles/liberty';

Future<String> _loadStyleJson(String sceneId) async {
  if (sceneId == 'flutter-markers') {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_openFreeMapLibertyStyle));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'OpenFreeMap Liberty returned HTTP ${response.statusCode}',
          uri: Uri.parse(_openFreeMapLibertyStyle),
        );
      }
      final styleJson = await response.transform(utf8.decoder).join();

      return configureFlutterMarkersSystemFonts(
        styleJson,
        platform: defaultTargetPlatform,
      );
    } finally {
      client.close(force: true);
    }
  }
  return rootBundle.loadString(
    'packages/visual_e2e_shared/assets/scenes/$sceneId.json',
  );
}

/// Replaces Liberty's hosted Noto Sans faces with fonts built into the target
/// OS. Both visual E2E apps receive this same transformed style, so MapLibre's
/// native placement and Flutter's text overlay use matching font metrics.
String configureFlutterMarkersSystemFonts(
  String styleJson, {
  required TargetPlatform platform,
}) {
  final style = jsonDecode(styleJson) as Map<String, dynamic>;
  final fontConfig = switch (platform) {
    TargetPlatform.iOS => _iosSystemFonts,
    TargetPlatform.android => _androidSystemFonts,
    _ => throw UnsupportedError(
      'flutter-markers visual E2E supports iOS and Android only',
    ),
  };

  style['font-faces'] = fontConfig.faces;
  final layers = style['layers'];
  if (layers is List) {
    for (final value in layers) {
      if (value is! Map<String, dynamic> || value['type'] != 'symbol') {
        continue;
      }
      final layout = value['layout'];
      if (layout is! Map<String, dynamic>) continue;
      final textFont = layout['text-font'];
      if (textFont is! List || textFont.isEmpty) continue;
      final sourceFace = textFont.first;
      if (sourceFace is! String) continue;
      layout['text-font'] = <String>[
        _systemFaceName(sourceFace, fontConfig.names),
      ];
    }
  }
  return jsonEncode(style);
}

String _systemFaceName(String source, _SystemFontNames names) {
  final lower = source.toLowerCase();
  if (lower.contains('italic') || lower.contains('oblique')) {
    return names.italic;
  }
  if (lower.contains('bold') ||
      lower.contains('black') ||
      lower.contains('heavy')) {
    return names.bold;
  }
  return names.regular;
}

typedef _SystemFontNames = ({String regular, String bold, String italic});

const _latinRange = <String>['U+0000-2FFF'];
const _cjkRange = <String>['U+3000-10FFFF'];

const _iosSystemFonts = (
  names: (regular: 'Arial', bold: 'Arial Bold', italic: 'Arial Italic'),
  faces: <String, List<Map<String, Object>>>{
    'Arial': <Map<String, Object>>[
      <String, Object>{
        'url': 'file:///System/Library/Fonts/Supplemental/Arial.ttf',
        'unicode-range': _latinRange,
      },
      <String, Object>{
        'url': 'file:///System/Library/Fonts/Supplemental/Arial%20Unicode.ttf',
        'unicode-range': _cjkRange,
      },
    ],
    'Arial Bold': <Map<String, Object>>[
      <String, Object>{
        'url': 'file:///System/Library/Fonts/Supplemental/Arial%20Bold.ttf',
        'unicode-range': _latinRange,
      },
      <String, Object>{
        'url': 'file:///System/Library/Fonts/Supplemental/Arial%20Unicode.ttf',
        'unicode-range': _cjkRange,
      },
    ],
    'Arial Italic': <Map<String, Object>>[
      <String, Object>{
        'url': 'file:///System/Library/Fonts/Supplemental/Arial%20Italic.ttf',
        'unicode-range': _latinRange,
      },
      <String, Object>{
        'url': 'file:///System/Library/Fonts/Supplemental/Arial%20Unicode.ttf',
        'unicode-range': _cjkRange,
      },
    ],
  },
);

const _androidSystemFonts = (
  names: (
    regular: 'source-sans-pro Regular',
    bold: 'source-sans-pro Bold',
    italic: 'source-sans-pro Italic',
  ),
  faces: <String, List<Map<String, Object>>>{
    'source-sans-pro Regular': <Map<String, Object>>[
      <String, Object>{
        'url': 'file:///system/fonts/SourceSansPro-Regular.ttf',
        'unicode-range': _latinRange,
      },
      <String, Object>{
        'url': 'file:///system/fonts/NotoSansCJK-Regular.ttc',
        'unicode-range': _cjkRange,
      },
    ],
    'source-sans-pro Bold': <Map<String, Object>>[
      <String, Object>{
        'url': 'file:///system/fonts/SourceSansPro-Bold.ttf',
        'unicode-range': _latinRange,
      },
      <String, Object>{
        'url': 'file:///system/fonts/NotoSansCJK-Regular.ttc',
        'unicode-range': _cjkRange,
      },
    ],
    'source-sans-pro Italic': <Map<String, Object>>[
      <String, Object>{
        'url': 'file:///system/fonts/SourceSansPro-Italic.ttf',
        'unicode-range': _latinRange,
      },
      <String, Object>{
        'url': 'file:///system/fonts/NotoSansCJK-Regular.ttc',
        'unicode-range': _cjkRange,
      },
    ],
  },
);

Future<void> stopVisualE2eAssetServer() => _VisualAssetServer.stop();

const _assetBasePlaceholder = '__VISUAL_E2E_ASSET_BASE__';
const _mbtilesPlaceholders = <String, String>{
  '__VISUAL_E2E_MBTILES_URL__': 'map.mbtiles',
  '__VISUAL_E2E_MBTILES_VECTOR_URL__': 'map-vector.mbtiles',
  '__VISUAL_E2E_MBTILES_MLT_URL__': 'map-mlt.mbtiles',
};

final _rasterTilePattern = RegExp(r'^/raster/\d+/\d+/\d+\.png$');
final _jpegTilePattern = RegExp(r'^/raster-jpeg/\d+/\d+/\d+\.jpg$');
final _webpTilePattern = RegExp(r'^/raster-webp/\d+/\d+/\d+\.webp$');
final _tmsTilePattern = RegExp(r'^/tms/\d+/\d+/([01])\.png$');
final _wmtsTilePattern = RegExp(r'^/wmts/\d+/\d+/\d+\.png$');
final _pmtilesArchivePattern = RegExp(
  r'^/archives/(map(?:-vector|-mlt)?\.pmtiles)$',
);
final _vectorTilePattern = RegExp(
  r'^/vector/(point|line|polygon|map)/\d+/\d+/\d+\.pbf$',
);
final _mltTilePattern = RegExp(r'^/vector/map/\d+/\d+/\d+\.mlt$');
final _glyphPattern = RegExp(r'^/glyphs/([^/]+)/(\d+-\d+)\.pbf$');

@visibleForTesting
String? visualE2eGlyphAssetPath(String requestPath) {
  final normalized = requestPath.replaceFirst('@2x', '');
  final match = _glyphPattern.firstMatch(normalized);
  if (match == null) return null;
  final fontStack = Uri.decodeComponent(match.group(1)!);
  final fixtureFont = fontStack == 'Noto Sans Regular,Noto Sans Hebrew Regular'
      ? 'NotoSansHebrew'
      : 'NotoCJK';

  return 'packages/visual_e2e_shared/assets/resources/glyphs/$fixtureFont/'
      '${match.group(2)}.pbf';
}

@visibleForTesting
String? visualE2eSpriteAssetPath(String requestPath) {
  final normalized = requestPath.replaceFirst('@2x', '');

  return switch (normalized) {
    '/sprite.json' || '/sprite-alt.json' =>
      'packages/visual_e2e_shared/assets/resources/sprite.json',
    '/sprite.png' || '/sprite-alt.png' =>
      'packages/visual_e2e_shared/assets/resources/sprite.png',
    _ => null,
  };
}

class _VisualAssetServer {
  _VisualAssetServer._(this._server);

  static _VisualAssetServer? _instance;
  static final Map<String, File> _materializedMbtiles = <String, File>{};

  final HttpServer _server;

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}/');

  static Future<_VisualAssetServer> start() async {
    final existing = _instance;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = _VisualAssetServer._(server);
    _instance = instance;
    unawaited(instance._serve());

    return instance;
  }

  static Future<void> stop() async {
    final instance = _instance;
    _instance = null;
    await instance?._server.close(force: true);
    final materialized = _materializedMbtiles.values.toList();
    _materializedMbtiles.clear();
    for (final mbtiles in materialized) {
      try {
        if (await mbtiles.exists()) await mbtiles.delete();
      } on FileSystemException {
        // Teardown remains best-effort if the temporary fixture is gone.
      }
    }
  }

  static Future<String> materializeMbtiles(String name) async {
    final existing = _materializedMbtiles[name];
    if (existing != null) return 'mbtiles://${existing.path}';
    final data = await rootBundle.load(
      'packages/visual_e2e_shared/assets/resources/archives/$name',
    );
    final file = File(
      '${Directory.systemTemp.path}/maplibre-flutter-gpu-visual-$pid-$name',
    );
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    _materializedMbtiles[name] = file;

    return 'mbtiles://${file.path}';
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      try {
        final archiveMatch = _pmtilesArchivePattern.firstMatch(
          request.uri.path,
        );
        if (archiveMatch != null) {
          final name = archiveMatch.group(1)!;
          await _serveRangeAsset(
            request,
            'packages/visual_e2e_shared/assets/resources/archives/$name',
          );
          continue;
        }
        if (request.uri.path == '/tilejson/vector.json') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object>{
              'tilejson': '3.0.0',
              'tiles': <String>[
                '${baseUri.toString().replaceFirst(RegExp(r'/$'), '')}'
                    '/vector/map/{z}/{x}/{y}.pbf',
              ],
              'minzoom': 0,
              'maxzoom': 0,
            }),
          );
          continue;
        }
        if (request.uri.path == '/geojson/features.json') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object>{
              'type': 'FeatureCollection',
              'features': <Object>[
                <String, Object>{
                  'type': 'Feature',
                  'properties': <String, Object>{'kind': 'url-fixture'},
                  'geometry': <String, Object>{
                    'type': 'Polygon',
                    'coordinates': <Object>[
                      <Object>[
                        <double>[-100, -45],
                        <double>[100, -45],
                        <double>[100, 45],
                        <double>[-100, 45],
                        <double>[-100, -45],
                      ],
                    ],
                  },
                },
              ],
            }),
          );
          continue;
        }
        final asset = _assetForPath(request.uri.path);
        if (asset == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          final data = await rootBundle.load(asset.path);
          request.response.headers
            ..contentType = asset.contentType
            ..set(HttpHeaders.cacheControlHeader, 'public, max-age=3600');
          request.response.add(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        }
      } catch (error, stackTrace) {
        debugPrint('visual asset server error: $error\n$stackTrace');
        request.response.statusCode = HttpStatus.internalServerError;
      } finally {
        await request.response.close();
      }
    }
  }

  Future<void> _serveRangeAsset(HttpRequest request, String asset) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    request.response.headers
      ..contentType = ContentType.binary
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.cacheControlHeader, 'public, max-age=3600');
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range == null) {
      request.response.contentLength = bytes.length;
      request.response.add(bytes);

      return;
    }
    final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
    if (match == null) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */${bytes.length}',
      );

      return;
    }
    final start = int.parse(match.group(1)!);
    final requestedEnd = match.group(2)!.isEmpty
        ? bytes.length - 1
        : int.parse(match.group(2)!);
    if (start >= bytes.length || requestedEnd < start) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */${bytes.length}',
      );

      return;
    }
    final end = requestedEnd.clamp(start, bytes.length - 1);
    request.response
      ..statusCode = HttpStatus.partialContent
      ..contentLength = end - start + 1;
    request.response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/${bytes.length}',
    );
    request.response.add(bytes.sublist(start, end + 1));
  }

  ({String path, ContentType contentType})? _assetForPath(String path) {
    final normalized = path.replaceFirst('@2x', '');
    final glyphAsset = visualE2eGlyphAssetPath(normalized);
    if (glyphAsset != null) {
      return (path: glyphAsset, contentType: ContentType.binary);
    }
    final spriteAsset = visualE2eSpriteAssetPath(normalized);
    if (spriteAsset != null) {
      return (
        path: spriteAsset,
        contentType: normalized.endsWith('.json')
            ? ContentType.json
            : ContentType('image', 'png'),
      );
    }

    return switch (normalized) {
      // Every {z}/{x}/{y} serves the same tile. The scene only needs the
      // raster pipeline exercised with a real texture, and a single asymmetric
      // tile makes a flipped or transposed UV visible in the baseline.
      _ when _rasterTilePattern.hasMatch(normalized) => (
        path: 'packages/visual_e2e_shared/assets/resources/raster-tile.png',
        contentType: ContentType('image', 'png'),
      ),
      _ when _jpegTilePattern.hasMatch(normalized) => (
        path: 'packages/visual_e2e_shared/assets/resources/raster-tile.jpg',
        contentType: ContentType('image', 'jpeg'),
      ),
      _ when _webpTilePattern.hasMatch(normalized) => (
        path: 'packages/visual_e2e_shared/assets/resources/raster-tile.webp',
        contentType: ContentType('image', 'webp'),
      ),
      _ when _tmsTilePattern.hasMatch(normalized) => (
        path:
            'packages/visual_e2e_shared/assets/resources/'
            'tms-${_tmsTilePattern.firstMatch(normalized)!.group(1)}.png',
        contentType: ContentType('image', 'png'),
      ),
      _ when _wmtsTilePattern.hasMatch(normalized) => (
        path: 'packages/visual_e2e_shared/assets/resources/raster-tile.png',
        contentType: ContentType('image', 'png'),
      ),
      _ when _vectorTilePattern.hasMatch(normalized) => (
        path:
            'packages/visual_e2e_shared/assets/resources/vector/'
            '${_vectorTilePattern.firstMatch(normalized)!.group(1)}.pbf',
        contentType: ContentType.binary,
      ),
      _ when _mltTilePattern.hasMatch(normalized) => (
        path: 'packages/visual_e2e_shared/assets/resources/vector/map.mlt',
        contentType: ContentType.binary,
      ),
      _ => null,
    };
  }
}

Future<void> runVisualE2eApp({
  required String implementation,
  required VisualMapBuilder mapBuilder,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!_visualE2eProcessIdentityLogged) {
    _visualE2eProcessIdentityLogged = true;
    debugPrint(
      'VISUAL_E2E_PROCESS|$implementation|$visualE2eRunToken|$pid|'
      '${visualE2eSuiteSceneIds.join(',')}',
    );
  }
  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      systemNavigationBarColor: Color(0x00000000),
    ),
  );

  final generation = VisualTestStatus.reset();
  final scene = await loadVisualScene();
  runApp(
    _VisualE2eApp(
      implementation: implementation,
      scene: scene,
      mapBuilder: mapBuilder,
      generation: generation,
    ),
  );
}

class _VisualE2eApp extends StatelessWidget {
  const _VisualE2eApp({
    required this.implementation,
    required this.scene,
    required this.mapBuilder,
    required this.generation,
  });

  final String implementation;
  final VisualScene scene;
  final VisualMapBuilder mapBuilder;
  final int generation;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: scene.backgroundColor,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      pageRouteBuilder: _buildPageRoute,
      home: ColoredBox(
        color: scene.backgroundColor,
        child: _VisualViewport(
          implementation: implementation,
          scene: scene,
          mapBuilder: mapBuilder,
          generation: generation,
        ),
      ),
    );
  }
}

PageRoute<T> _buildPageRoute<T>(RouteSettings settings, WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) => builder(context),
  );
}

class _VisualViewport extends StatelessWidget {
  const _VisualViewport({
    required this.implementation,
    required this.scene,
    required this.mapBuilder,
    required this.generation,
  });

  // Keep native ornaments outside the captured viewport without pushing the
  // z2 camera past the antimeridian. On iOS, maplibre_gl constrains the whole
  // visible screen to [-180, 180] when CameraTargetBounds is unbounded.
  static const double _controlOverscan = 24;

  final String implementation;
  final VisualScene scene;
  final VisualMapBuilder mapBuilder;
  final int generation;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: VisualTestStatus.ready,
      builder: (BuildContext context, bool ready, Widget? child) {
        return Semantics(
          container: true,
          label: ready
              ? '$visualE2eReadyPrefix|${scene.id}'
              : 'VISUAL_E2E_LOADING|${scene.id}',
          child: child,
        );
      },
      child: RepaintBoundary(
        key: visualE2eRepaintBoundaryKey,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              Positioned(
                left: -_controlOverscan,
                top: -_controlOverscan,
                right: -_controlOverscan,
                bottom: -_controlOverscan,
                child: mapBuilder(
                  scene,
                  () => VisualTestStatus.mapIdle(
                    implementation: implementation,
                    sceneId: scene.id,
                    generation: generation,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
