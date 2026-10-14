// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;
import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/symbol_profile_counters.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

const _output = String.fromEnvironment('MAP_PROBE_OUTPUT');
const _seconds = int.fromEnvironment('MAP_PROBE_SECONDS', defaultValue: 3);
const _repeats = int.fromEnvironment('MAP_PROBE_REPEATS', defaultValue: 3);
const _filter = String.fromEnvironment('MAP_PROBE_CASES');
const _variant = String.fromEnvironment(
  'MAP_PROBE_VARIANT',
  defaultValue: 'current',
);
const _haloWidthOption = String.fromEnvironment(
  'MAP_PROBE_HALO_WIDTH',
  defaultValue: '1',
);
const _haloBlurOption = String.fromEnvironment(
  'MAP_PROBE_HALO_BLUR',
  defaultValue: '0',
);
const _fadeMs = int.fromEnvironment('MAP_PROBE_FADE_MS', defaultValue: 0);
const _text = String.fromEnvironment('MAP_PROBE_TEXT', defaultValue: 'latin');
const _layers = int.fromEnvironment('MAP_PROBE_LAYERS', defaultValue: 1);
const _icons = bool.fromEnvironment('MAP_PROBE_ICONS');
const _iconOpacityOption = String.fromEnvironment(
  'MAP_PROBE_ICON_OPACITY',
  defaultValue: '1',
);
const _semantics = bool.fromEnvironment('MAP_PROBE_SEMANTICS');
const _tap = bool.fromEnvironment('MAP_PROBE_TAP');
const _maxAttempts = 6;

final _haloWidth = double.parse(_haloWidthOption);
final _haloBlur = double.parse(_haloBlurOption);
final _iconOpacity = double.parse(_iconOpacityOption);

/// Camera routes. Zoom routes use a zoom-interpolated text size so every
/// zoom frame re-evaluates the label font size, as real styles do.
enum _Motion {
  pan,
  rotateTilt,
  zoom,
  pitchOnly,
  tiltZoom;

  bool get interpolatesTextSize => this == zoom || this == tiltZoom;
}

/// Code point ranges of the bundled NotoCJK glyph fixture.
const _cjkRanges = [(19968, 20223), (26368, 26623), (39168, 39423)];

Future<void> main() async {
  if (!kProfileMode) {
    stderr.writeln('MAP_PROBE_ERROR Run this benchmark in profile mode.');
    exit(64);
  }
  WidgetsFlutterBinding.ensureInitialized();
  if (_semantics) SemanticsBinding.instance.ensureSemantics();
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
          child: _Probe(
            glyphs: source['glyphs'] as String,
            sprite: source['sprite'] as String,
          ),
        ),
      ),
    ),
  );
}

class _Probe extends StatefulWidget {
  const _Probe({required this.glyphs, required this.sprite});

  final String glyphs;
  final String sprite;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with WidgetsBindingObserver {
  final _created = Completer<gpu.MapLibreMapController>();
  Completer<void>? _styleReady;
  final _results = <Map<String, Object>>[];
  final _frames = <FrameTiming>[];
  var _hidden = false;
  var _label = 'Loading point labels';
  late final String _initialStyle;
  var _lifecycleEpoch = 0;
  Completer<void>? _resumed;
  final _lifecycleStates = <String>{};

  @override
  void initState() {
    super.initState();
    _initialStyle = _style(line: false, interpolatedTextSize: false);
    _styleReady = Completer<void>();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run());
  }

  void _timings(List<FrameTiming> timings) => _frames.addAll(timings);

  gpu.CameraPosition _camera(_Motion motion, {double phase = 0}) {
    final pans = motion == .pan || motion == .rotateTilt;
    final zooms = motion.interpolatesTextSize;

    return gpu.CameraPosition(
      target: gpu.LatLng(
        35.6812 + (pans ? .0007 * math.sin(phase) : 0),
        139.7671 + (pans ? .0012 * math.cos(phase) : 0),
      ),
      zoom: zooms ? 14 + .5 * math.sin(phase) : 14.1,
      bearing: motion == .rotateTilt ? 20 + 18 * math.sin(phase) : 0,
      tilt: switch (motion) {
        .rotateTilt => 25 + 15 * math.cos(phase),
        .pitchOnly => 30 + 15 * math.sin(phase),
        .tiltZoom => 30 + 15 * math.cos(phase),
        .pan || .zoom => 0,
      },
    );
  }

  // An inactive window still renders every frame. Only an occluded or paused
  // app stops producing frames and invalidates a sample.
  static bool _isVisible(AppLifecycleState? state) =>
      state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    stdout.writeln('MAP_PROBE_LIFECYCLE ${state.name}');
    _lifecycleStates.add(state.name);
    if (!_isVisible(state)) {
      _lifecycleEpoch++;
    } else {
      _resumed?.complete();
      _resumed = null;
    }
  }

  Future<void> _waitForForeground() async {
    if (_isVisible(WidgetsBinding.instance.lifecycleState)) return;
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
            for (final motion in _Motion.values)
              '${kind}_${mode}_${motion.name}',
      };
      if (_repeats < 1 ||
          _seconds < 1 ||
          _layers < 1 ||
          _fadeMs < 0 ||
          !_haloWidth.isFinite ||
          !_haloBlur.isFinite ||
          !_iconOpacity.isFinite ||
          !const ['latin', 'cjk', 'cjk-vertical'].contains(_text) ||
          (filters != null && !names.containsAll(filters))) {
        throw ArgumentError('Invalid benchmark configuration');
      }
      var currentStyle = _initialStyle;
      for (var repeat = 1; repeat <= _repeats; repeat++) {
        for (final line in [false, true]) {
          for (final interpolated in [false, true]) {
            final motions = [
              for (final motion in _Motion.values)
                if (motion.interpolatesTextSize == interpolated) motion,
            ];
            final selected = [
              for (final hidden in [false, true])
                for (final motion in motions)
                  if (filters == null ||
                      filters.contains(_caseName(line, hidden, motion)))
                    (hidden: hidden, motion: motion),
            ];
            if (selected.isEmpty) continue;
            final style = _style(
              line: line,
              interpolatedTextSize: interpolated,
            );
            if (style != currentStyle) {
              await _waitForForeground();
              _styleReady = Completer<void>();
              await controller.setStyle(style);
              await _styleReady!.future.timeout(const Duration(seconds: 30));
              await Future<void>.delayed(const Duration(seconds: 2));
              currentStyle = style;
            }
            for (final (:hidden, :motion) in selected) {
              setState(() => _hidden = hidden);
              await _measure(
                controller,
                _caseName(line, hidden, motion),
                motion,
                repeat,
              );
            }
          }
        }
      }
      await _writeOutput();
      stdout.writeln('MAP_PROBE_DONE');
      await stdout.flush();
      exit(0);
    } catch (error, stack) {
      stderr.writeln('MAP_PROBE_ERROR $error\n$stack');
      await stderr.flush();
      exit(1);
    }
  }

  String _caseName(bool line, bool hidden, _Motion motion) =>
      '${line ? 'line224' : 'point320'}_'
      '${hidden ? 'hidden' : 'default'}_${motion.name}';

  Future<void> _measure(
    gpu.MapLibreMapController controller,
    String name,
    _Motion motion,
    int repeat,
  ) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      await _waitForForeground();
      final epoch = _lifecycleEpoch;
      setState(() => _label = '$name, repeat $repeat');
      await controller.moveCamera(
        gpu.CameraUpdate.newCameraPosition(_camera(motion)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 750));
      final labelsBefore = _placedSymbolCount(controller);
      _frames.clear();
      _lifecycleStates.clear();
      SymbolProfileCounters.reset();
      final start = SchedulerBinding.instance.currentSystemFrameTimeStamp;
      final watch = Stopwatch()..start();
      var steps = 0;
      while (watch.elapsedMilliseconds < _seconds * 1000 &&
          epoch == _lifecycleEpoch) {
        final phase = watch.elapsedMicroseconds / 1000000 * 1.8;
        await controller.moveCamera(
          gpu.CameraUpdate.newCameraPosition(_camera(motion, phase: phase)),
        );
        steps++;
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      final elapsed = watch.elapsedMicroseconds;
      final end = SchedulerBinding.instance.currentSystemFrameTimeStamp;
      final counters = SymbolProfileCounters.snapshot();
      // Profile frame timings arrive in batches after the frame finishes.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final timings = _frames.where((timing) {
        final frameStart = timing.timestampInMicroseconds(
          ui.FramePhase.buildStart,
        );

        return frameStart >= start.inMicroseconds &&
            frameStart < end.inMicroseconds;
      }).toList();
      final labelsAfter = _placedSymbolCount(controller);
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
        'lifecycleStates': _lifecycleStates.toList(),
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
        'raster_ms': _stats(timings.map((frame) => frame.rasterDuration)),
        'total_ms': _stats(timings.map((frame) => frame.totalSpan)),
        'vsyncOverhead_ms': _stats(timings.map((frame) => frame.vsyncOverhead)),
        'counters': counters,
        'style': {
          'haloWidth': _haloWidth,
          'haloBlur': _haloBlur,
          'fadeMs': _fadeMs,
          'text': _text,
          'layers': _layers,
          'icons': _icons,
          'iconOpacity': _iconOpacity,
          'interpolatedTextSize': motion.interpolatesTextSize,
          'tap': _tap,
        },
        'fixture':
            'Inline GeoJSON, bundled glyphs and sprite over loopback'
            '${_fadeMs > 0 ? ', collision placement with fades' : ', no fades'}',
      };
      _results.add(result);
      await _writeOutput();
      stdout.writeln('MAP_PROBE ${jsonEncode(result)}');

      return;
    }
    stdout.writeln(
      'MAP_PROBE_SKIPPED ${jsonEncode({'case': name, 'repeat': repeat})}',
    );
  }

  // Every accepted record is persisted so an interrupted run keeps its data.
  Future<void> _writeOutput() async {
    if (_output.isEmpty) return;
    await File(_output)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(_results));
  }

  int _placedSymbolCount(gpu.MapLibreMapController controller) => controller
      .getPlacedLabels()
      .where((label) => label.textPlaced || label.iconPlaced)
      .length;

  static String _cjkName(int index) {
    final codePoints = <int>[];
    for (final range in _cjkRanges) {
      codePoints.addAll([for (var c = range.$1; c <= range.$2; c++) c]);
    }
    final n = codePoints.length;

    return String.fromCharCodes([
      codePoints[index % n],
      codePoints[(index * 7 + 3) % n],
      codePoints[(index * 13 + 5) % n],
    ]);
  }

  String _style({required bool line, required bool interpolatedTextSize}) {
    final columns = line ? 16 : 20;
    final rows = line ? 14 : 16;
    final features = <Map<String, Object>>[];
    const lonSpan = .020;
    const latSpan = .012;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final index = row * columns + column;
        final lon = 139.7671 + (column / (columns - 1) - .5) * lonSpan;
        final lat = 35.6812 + (row / (rows - 1) - .5) * latSpan;
        final name = switch (_text) {
          'latin' => line ? 'Road $index' : 'S$index',
          _ => _cjkName(index),
        };
        features.add({
          'type': 'Feature',
          'id': index,
          'properties': {'name': name, 'layer': index % _layers},
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
    // Native layers between symbol layers keep each symbol layer in its own
    // GPU stratum in interleaved compositing.
    final gridLines = <Map<String, Object>>[
      for (var row = 0; row < rows; row++)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [
                139.7671 - lonSpan * .55,
                35.6812 + (row / (rows - 1) - .5) * latSpan,
              ],
              [
                139.7671 + lonSpan * .55,
                35.6812 + (row / (rows - 1) - .5) * latSpan,
              ],
            ],
          },
        },
    ];
    final collisions = _fadeMs > 0;
    final layers = <Map<String, Object>>[
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': '#dce8e2'},
      },
    ];
    for (var index = 0; index < _layers; index++) {
      if (index > 0) {
        layers.add({
          'id': 'grid-$index',
          'type': 'line',
          'source': 'grid',
          'paint': {'line-color': '#9db5ad', 'line-width': 1.5},
        });
      }
      layers.add({
        'id': _layers == 1 ? 'labels' : 'labels-$index',
        'type': 'symbol',
        'source': 'symbols',
        if (_layers > 1)
          'filter': [
            '==',
            ['get', 'layer'],
            index,
          ],
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': ['NotoCJK'],
          'text-size': interpolatedTextSize
              ? [
                  'interpolate',
                  ['linear'],
                  ['zoom'],
                  13,
                  11,
                  15,
                  16,
                ]
              : 13,
          'text-allow-overlap': !collisions,
          'text-ignore-placement': !collisions,
          'text-padding': 0,
          'symbol-placement': line ? 'line-center' : 'point',
          'text-rotation-alignment': line ? 'map' : 'viewport',
          'text-pitch-alignment': line ? 'map' : 'viewport',
          if (_text == 'cjk-vertical') 'text-writing-mode': ['vertical'],
          if (_icons) ...{
            'icon-image': 'circle_15',
            'icon-allow-overlap': !collisions,
            'icon-ignore-placement': !collisions,
            'text-anchor': 'top',
            'text-offset': [0, .8],
          },
        },
        'paint': {
          'text-color': '#16262a',
          'text-halo-color': '#ffffff',
          'text-halo-width': _haloWidth,
          'text-halo-blur': _haloBlur,
          if (_icons) ...{
            'icon-color': '#2f6fd6',
            'icon-halo-color': '#ffffff',
            'icon-halo-width': 1.5,
            'icon-opacity': _iconOpacity,
          },
        },
      });
    }

    return jsonEncode({
      'version': 8,
      'glyphs': widget.glyphs,
      if (_icons) 'sprite': widget.sprite,
      'sources': {
        'symbols': {
          'type': 'geojson',
          'data': {'type': 'FeatureCollection', 'features': features},
        },
        'grid': {
          'type': 'geojson',
          'data': {'type': 'FeatureCollection', 'features': gridLines},
        },
      },
      'layers': layers,
    });
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(context) => Stack(
    children: [
      Positioned.fill(
        child: gpu.MapLibreMap(
          styleString: _initialStyle,
          initialCameraPosition: _camera(.pan),
          trackCameraPosition: true,
          compassEnabled: false,
          logoEnabled: false,
          attributionButtonEnabled: false,
          scaleControlEnabled: false,
          symbolFadeDuration: Duration(milliseconds: _fadeMs),
          symbolTextBuilder: _hidden ? null : buildDefaultSymbolText,
          symbolIconBuilder: _hidden ? null : buildDefaultSymbolIcon,
          onMapClick: _tap ? (_, _) {} : null,
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
