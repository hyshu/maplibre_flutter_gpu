// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;
import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

const _output = String.fromEnvironment('MAP_PROBE_OUTPUT');
const _seconds = int.fromEnvironment('MAP_PROBE_SECONDS', defaultValue: 3);
const _repeats = int.fromEnvironment('MAP_PROBE_REPEATS', defaultValue: 3);
const _filter = String.fromEnvironment('MAP_PROBE_CASES');
const _variant = String.fromEnvironment(
  'MAP_PROBE_VARIANT',
  defaultValue: 'current',
);

Future<void> main() async {
  if (!kProfileMode) {
    stderr.writeln('MAP_PROBE_ERROR Run this benchmark in profile mode.');
    exit(64);
  }
  WidgetsFlutterBinding.ensureInitialized();
  setVisualE2eRuntimeSceneId('text-symbol');
  final source =
      jsonDecode((await loadVisualScene()).styleJson) as Map<String, dynamic>;
  runApp(
    MediaQuery.fromView(
      view: WidgetsBinding.instance.platformDispatcher.views.first,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xff111111), fontSize: 14),
          child: _Probe(glyphs: source['glyphs'] as String),
        ),
      ),
    ),
  );
}

class _Probe extends StatefulWidget {
  const _Probe({required this.glyphs});

  final String glyphs;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with WidgetsBindingObserver {
  final _created = Completer<gpu.MapLibreMapController>();
  Completer<void>? _styleReady;
  final _results = <Map<String, Object>>[];
  final _frames = <FrameTiming>[];
  bool _hidden = false;
  String _label = 'Loading point labels';
  late final String _initialStyle;
  var _lifecycleEpoch = 0;
  Completer<void>? _resumed;

  @override
  void initState() {
    super.initState();
    _initialStyle = _style(false);
    _styleReady = Completer<void>();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run());
  }

  void _timings(List<FrameTiming> timings) {
    _frames.addAll(timings);
  }

  gpu.CameraPosition _camera({double phase = 0, bool rotate = false}) =>
      gpu.CameraPosition(
        target: gpu.LatLng(
          35.6812 + .0007 * math.sin(phase),
          139.7671 + .0012 * math.cos(phase),
        ),
        zoom: 14.1,
        bearing: rotate ? 20 + 18 * math.sin(phase) : 0,
        tilt: rotate ? 25 + 15 * math.cos(phase) : 0,
      );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    stdout.writeln('MAP_PROBE_LIFECYCLE ${state.name}');
    if (state != AppLifecycleState.resumed) {
      _lifecycleEpoch++;
    } else {
      _resumed?.complete();
      _resumed = null;
    }
  }

  Future<void> _waitForForeground() async {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    stdout.writeln('MAP_PROBE_WAITING_FOR_FOREGROUND');
    _resumed ??= Completer<void>();
    await _resumed!.future.timeout(const Duration(minutes: 2));
  }

  Future<void> _run() async {
    try {
      final controller = await _created.future.timeout(
        const Duration(seconds: 30),
      );
      await _styleReady!.future.timeout(const Duration(seconds: 30));
      final filters = _filter.isEmpty ? null : _filter.split(',').toSet();
      final names = {
        for (final kind in ['point320', 'line224'])
          for (final mode in ['default', 'hidden'])
            for (final motion in ['pan', 'rotateTilt'])
              '${kind}_${mode}_$motion',
      };
      if (_repeats < 1 ||
          _seconds < 1 ||
          (filters != null && !names.containsAll(filters))) {
        throw ArgumentError('Invalid benchmark configuration');
      }
      for (var repeat = 1; repeat <= _repeats; repeat++) {
        for (final line in [false, true]) {
          await _waitForForeground();
          _styleReady = Completer<void>();
          await controller.setStyle(_style(line));
          await _styleReady!.future.timeout(const Duration(seconds: 30));
          await Future<void>.delayed(const Duration(seconds: 2));
          for (final hidden in [false, true]) {
            setState(() => _hidden = hidden);
            for (final rotate in [false, true]) {
              final name =
                  '${line ? 'line224' : 'point320'}_'
                  '${hidden ? 'hidden' : 'default'}_${rotate ? 'rotateTilt' : 'pan'}';
              if (filters != null && !filters.contains(name)) continue;
              var accepted = false;
              for (var attempt = 1; attempt <= 3 && !accepted; attempt++) {
                await _waitForForeground();
                final epoch = _lifecycleEpoch;
                setState(() => _label = '$name, repeat $repeat');
                await controller.moveCamera(
                  gpu.CameraUpdate.newCameraPosition(_camera(rotate: rotate)),
                );
                await Future<void>.delayed(const Duration(milliseconds: 750));
                final labelsBefore = _placedTextCount(controller);
                _frames.clear();
                final start =
                    SchedulerBinding.instance.currentSystemFrameTimeStamp;
                final watch = Stopwatch()..start();
                var steps = 0;
                while (watch.elapsedMilliseconds < _seconds * 1000 &&
                    epoch == _lifecycleEpoch) {
                  final phase = watch.elapsedMicroseconds / 1000000 * 1.8;
                  await controller.moveCamera(
                    gpu.CameraUpdate.newCameraPosition(
                      _camera(phase: phase, rotate: rotate),
                    ),
                  );
                  steps++;
                  await Future<void>.delayed(const Duration(milliseconds: 16));
                }
                final elapsed = watch.elapsedMicroseconds;
                final end =
                    SchedulerBinding.instance.currentSystemFrameTimeStamp;
                // Profile frame timings arrive in batches after the frame finishes.
                await Future<void>.delayed(const Duration(milliseconds: 1100));
                final timings = _frames.where((timing) {
                  final frameStart = timing.timestampInMicroseconds(
                    ui.FramePhase.buildStart,
                  );

                  return frameStart >= start.inMicroseconds &&
                      frameStart < end.inMicroseconds;
                }).toList();
                final labelsAfter = _placedTextCount(controller);
                if (epoch != _lifecycleEpoch ||
                    timings.length < 5 ||
                    labelsBefore == 0 ||
                    labelsAfter == 0) {
                  stdout.writeln(
                    'MAP_PROBE_RETRY ${jsonEncode({'case': name, 'repeat': repeat, 'attempt': attempt, 'frames': timings.length, 'foregroundInterrupted': epoch != _lifecycleEpoch, 'labelsBefore': labelsBefore, 'labelsAfter': labelsAfter})}',
                  );
                  continue;
                }
                if (!mounted) return;
                final result = <String, Object>{
                  'variant': _variant,
                  'case': name,
                  'repeat': repeat,
                  'frames': timings.length,
                  'semanticsEnabled': WidgetsBinding.instance.semanticsEnabled,
                  'elapsedUs': elapsed,
                  'cameraSteps': steps,
                  'size': [
                    MediaQuery.sizeOf(context).width,
                    MediaQuery.sizeOf(context).height,
                  ],
                  'devicePixelRatio': MediaQuery.devicePixelRatioOf(context),
                  'labelsBefore': labelsBefore,
                  'labelsAfter': labelsAfter,
                  'ui_ms': _stats(timings.map((frame) => frame.buildDuration)),
                  'raster_ms': _stats(
                    timings.map((frame) => frame.rasterDuration),
                  ),
                  'total_ms': _stats(timings.map((frame) => frame.totalSpan)),
                  'fixture': 'Inline GeoJSON and bundled glyphs over loopback, no fades',
                };
                _results.add(result);
                stdout.writeln('MAP_PROBE ${jsonEncode(result)}');
                accepted = true;
              }
              if (!accepted) {
                throw StateError('No valid frames or labels for $name');
              }
            }
          }
        }
      }
      if (_output.isNotEmpty) {
        await File(
          _output,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(_results));
      }
      stdout.writeln('MAP_PROBE_DONE');
      await stdout.flush();
      exit(0);
    } catch (error, stack) {
      stderr.writeln('MAP_PROBE_ERROR $error\n$stack');
      await stderr.flush();
      exit(1);
    }
  }

  int _placedTextCount(gpu.MapLibreMapController controller) =>
      controller.getPlacedLabels().where((label) => label.textPlaced).length;

  String _style(bool line) {
    final columns = line ? 16 : 20;
    final rows = line ? 14 : 16;
    final features = <Map<String, Object>>[];
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final index = row * columns + column;
        final lon = 139.7671 + (column / (columns - 1) - .5) * .020;
        final lat = 35.6812 + (row / (rows - 1) - .5) * .012;
        features.add({
          'type': 'Feature',
          'id': index,
          'properties': {'name': line ? 'Road $index' : 'S$index'},
          'geometry': {
            'type': line ? 'LineString' : 'Point',
            'coordinates': line
                ? [
                    [lon - .0018, lat - .00015],
                    [lon, lat + .00015],
                    [lon + .0018, lat],
                  ]
                : [lon, lat],
          },
        });
      }
    }

    return jsonEncode({
      'version': 8,
      'glyphs': widget.glyphs,
      'sources': {
        'symbols': {
          'type': 'geojson',
          'data': {'type': 'FeatureCollection', 'features': features},
        },
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': '#dce8e2'},
        },
        {
          'id': 'labels',
          'type': 'symbol',
          'source': 'symbols',
          'layout': {
            'text-field': ['get', 'name'],
            'text-font': ['NotoCJK'],
            'text-size': 13,
            'text-allow-overlap': true,
            'text-ignore-placement': true,
            'text-padding': 0,
            'symbol-placement': line ? 'line-center' : 'point',
            'text-rotation-alignment': line ? 'map' : 'viewport',
            'text-pitch-alignment': line ? 'map' : 'viewport',
          },
          'paint': {
            'text-color': '#16262a',
            'text-halo-color': '#ffffff',
            'text-halo-width': 1,
          },
        },
      ],
    });
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: gpu.MapLibreMap(
          styleString: _initialStyle,
          initialCameraPosition: _camera(),
          trackCameraPosition: true,
          compassEnabled: false,
          logoEnabled: false,
          attributionButtonEnabled: false,
          scaleControlEnabled: false,
          symbolFadeDuration: Duration.zero,
          symbolTextBuilder: _hidden ? null : buildDefaultSymbolText,
          symbolIconBuilder: _hidden ? null : buildDefaultSymbolIcon,
          onMapCreated: (controller) => _created.complete(controller),
          onStyleLoadedCallback: () {
            final ready = _styleReady;
            if (ready != null && !ready.isCompleted) ready.complete();
          },
        ),
      ),
      Positioned(top: 12, left: 12, child: Text(_label)),
    ],
  );
}

Map<String, Object> _stats(Iterable<Duration> durations) {
  final values = durations.map((d) => d.inMicroseconds / 1000).toList()..sort();
  if (values.isEmpty) return {'median': 0, 'p95': 0, 'max': 0};

  return {
    'median': values[values.length ~/ 2],
    'p95': values[((values.length - 1) * .95).round()],
    'max': values.last,
    'over16_7ms': values.where((v) => v > 16.7).length,
  };
}
