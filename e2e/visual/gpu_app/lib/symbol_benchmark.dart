import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
// ignore: implementation_imports
import 'package:maplibre_flutter_gpu/src/widgets/symbols/map_symbol.dart';

const _counts = String.fromEnvironment('PROBE_COUNTS', defaultValue: '200,800');
const _filter = String.fromEnvironment('PROBE_CASES');
const _measureMs = int.fromEnvironment('PROBE_MEASURE_MS', defaultValue: 2000);
const _warmupMs = int.fromEnvironment('PROBE_WARMUP_MS', defaultValue: 750);
const _repeats = int.fromEnvironment('PROBE_REPEATS', defaultValue: 3);
const _variant = String.fromEnvironment(
  'PROBE_VARIANT',
  defaultValue: 'current',
);
const _output = String.fromEnvironment('PROBE_OUTPUT');
const _frameVariants = 48;

Future<void> main() async {
  if (!kProfileMode) {
    stderr.writeln('SYMBOL_PROBE_ERROR Run this benchmark in profile mode.');
    exit(64);
  }
  WidgetsFlutterBinding.ensureInitialized();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(
    const Offset(9, 9),
    8,
    Paint()..color = const Color(0xff2196f3),
  );
  canvas.drawCircle(
    const Offset(9, 9),
    3,
    Paint()..color = const Color(0xffffffff),
  );
  final picture = recorder.endRecording();
  final spriteImage = await picture.toImage(18, 18);
  picture.dispose();
  final icon = SpriteIcon(
    atlas: spriteImage,
    x: 0,
    y: 0,
    width: 18,
    height: 18,
    pixelRatio: 1,
  );
  runApp(
    MediaQuery.fromView(
      view: WidgetsBinding.instance.platformDispatcher.views.first,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xff111111), fontSize: 14),
          child: _Probe(icon: icon),
        ),
      ),
    ),
  );
}

class _Probe extends StatefulWidget {
  const _Probe({required this.icon});

  final SpriteIcon icon;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _relayout = _RelayoutNotifier();
  final _overlayKey = GlobalKey();
  final _timings = <FrameTiming>[];
  late final Ticker _ticker;
  _ProbeCase? _case;
  Size _size = Size.zero;
  var _running = false;
  var _frame = 0;
  var _lifecycleEpoch = 0;
  Completer<void>? _resumed;
  final _results = <Map<String, Object>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_recordTimings);
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_recordTimings);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _relayout.dispose();
    super.dispose();
  }

  void _recordTimings(List<FrameTiming> timings) => _timings.addAll(timings);

  void _tick(Duration elapsed) {
    final active = _case;
    if (active == null) return;
    _frame = (_frame + 1) % _frameVariants;
    active.positions.frame = _frame;
    if (active.visual) {
      setState(() => active.symbols = active.variants[_frame]);
    } else {
      _relayout.notify();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    stdout.writeln('SYMBOL_PROBE_LIFECYCLE ${state.name}');
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
    stdout.writeln('SYMBOL_PROBE_WAITING_FOR_FOREGROUND');
    _resumed ??= Completer<void>();
    await _resumed!.future.timeout(const Duration(minutes: 2));
  }

  Future<void> _run() async {
    try {
      await _runCases();
      if (_output.isNotEmpty) {
        await File(
          _output,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(_results));
      }
      stdout.writeln('SYMBOL_PROBE_DONE');
      await stdout.flush();
      exit(0);
    } catch (error, stack) {
      stderr.writeln('SYMBOL_PROBE_ERROR $error\n$stack');
      await stderr.flush();
      exit(1);
    }
  }

  Future<void> _runCases() async {
    final devicePixelRatio = View.of(context).devicePixelRatio;
    final counts = _counts.split(',').map(int.parse).toList();
    const names = [
      'empty',
      'point_positions',
      'point_halo_positions',
      'path_positions',
      'path_halo_positions',
      'icons_positions',
      'point_transform',
      'point_halo_transform',
      'point_refresh',
      'point_halo_refresh',
      'path_shape',
      'path_halo_shape',
      'path_offsets',
      'path_halo_offsets',
    ];
    final filters = _filter.isEmpty ? null : _filter.split(',').toSet();
    if (_repeats < 1 ||
        _measureMs < 100 ||
        _warmupMs < 0 ||
        counts.any((count) => count < 1) ||
        (filters != null && !names.toSet().containsAll(filters))) {
      throw ArgumentError('Invalid benchmark configuration');
    }
    for (var repeat = 1; repeat <= _repeats; repeat++) {
      for (final count in counts) {
        for (final name in names) {
          if (filters != null && !filters.contains(name)) continue;
          if (name == 'empty' && count != counts.first) continue;
          var accepted = false;
          for (var attempt = 1; attempt <= 3 && !accepted; attempt++) {
            await _waitForForeground();
            final epoch = _lifecycleEpoch;
            final active = _createCase(name, name == 'empty' ? 0 : count);
            setState(() {
              _case = active;
              _frame = 0;
            });
            await Future<void>.delayed(Duration(milliseconds: _warmupMs));
            final tree = _treeCounts();
            _timings.clear();
            final start = SchedulerBinding.instance.currentSystemFrameTimeStamp;
            await Future<void>.delayed(Duration(milliseconds: _measureMs));
            final end = SchedulerBinding.instance.currentSystemFrameTimeStamp;
            // Profile frame timings arrive in batches after the frame finishes.
            await Future<void>.delayed(const Duration(milliseconds: 1100));
            final timings = _timings.where((timing) {
              final buildStart = timing.timestampInMicroseconds(
                ui.FramePhase.buildStart,
              );

              return buildStart >= start.inMicroseconds &&
                  buildStart < end.inMicroseconds;
            }).toList();
            if (epoch != _lifecycleEpoch || timings.length < 5) {
              stdout.writeln(
                'SYMBOL_PROBE_RETRY ${jsonEncode({'case': name, 'repeat': repeat, 'attempt': attempt, 'frames': timings.length, 'foregroundInterrupted': epoch != _lifecycleEpoch})}',
              );
              continue;
            }
            final result = <String, Object>{
              'variant': _variant,
              'case': name,
              'count': active.symbols.length,
              'repeat': repeat,
              'frames': timings.length,
              'semanticsEnabled': WidgetsBinding.instance.semanticsEnabled,
              'measureMs': _measureMs,
              'size': [_size.width, _size.height],
              'devicePixelRatio': devicePixelRatio,
              'ui_ms': _stats(timings.map((t) => t.buildDuration)),
              'raster_ms': _stats(timings.map((t) => t.rasterDuration)),
              'total_ms': _stats(timings.map((t) => t.totalSpan)),
              'tree': tree,
              'fixture':
                  'Precomputed symbols and anchors, no native map, no fades',
            };
            _results.add(result);
            stdout.writeln('SYMBOL_PROBE ${jsonEncode(result)}');
            accepted = true;
          }
          if (!accepted) {
            throw StateError('No valid frames for $name at count $count');
          }
        }
      }
    }
  }

  _ProbeCase _createCase(String name, int count) {
    final transform = name.endsWith('transform');
    final shape = name.endsWith('shape');
    final offsets = name.endsWith('offsets');
    final visual = transform || shape || offsets || name.endsWith('refresh');
    final halo = name.contains('halo');
    final path = name.startsWith('path');
    final icons = name.startsWith('icons');
    final columns = math.sqrt(count * _size.width / _size.height).ceil();
    final rows = columns == 0 ? 0 : (count / columns).ceil();
    final anchors = List.generate(_frameVariants, (frame) {
      final phase = frame * 2 * math.pi / _frameVariants;
      final offset = Offset(math.sin(phase) * 6, math.cos(phase) * 6);

      return List.generate(count, (index) {
        final column = index % columns;
        final row = index ~/ columns;

        return Offset(
              75 + column * (_size.width - 150) / math.max(1, columns - 1),
              40 + row * (_size.height - 80) / math.max(1, rows - 1),
            ) +
            offset;
      }, growable: false);
    }, growable: false);
    final variants = List.generate(visual ? _frameVariants : 1, (frame) {
      final phase = frame * 2 * math.pi / _frameVariants;
      final angle = transform ? 0.1 + math.sin(phase) * 0.04 : 0.0;
      final bend = shape || offsets ? math.sin(phase) * 8 : 0.0;
      final data = LabelData(
        lat: 0,
        lon: 0,
        fontSize: 13,
        textR: 0.12,
        textG: 0.12,
        textB: 0.12,
        textA: 1,
        haloR: 1,
        haloG: 1,
        haloB: 1,
        haloA: halo ? 1 : 0,
        haloWidth: halo ? 1.5 : 0,
        text: icons ? '' : 'Maple Road',
        textPlaced: !icons,
        iconPlaced: icons,
        icon: icons ? 'dot' : '',
        textW: 100,
        alongLine: path,
        textPath: offsets
            ? [
                const LabelPathPoint(-70, -12),
                const LabelPathPoint(-65, -12),
                LabelPathPoint(-60, bend),
                LabelPathPoint(60, bend),
                const LabelPathPoint(65, -12),
                const LabelPathPoint(70, -12),
              ]
            : path
            ? [
                LabelPathPoint(-70, -bend),
                const LabelPathPoint(0, 0),
                LabelPathPoint(70, bend),
              ]
            : const [],
        textTransform: LabelAffineTransform(
          xx: math.cos(angle),
          xy: math.sin(angle),
          yx: -math.sin(angle),
          yy: math.cos(angle),
        ),
        layer: 'probe',
      );

      return List.generate(
        count,
        (index) => MapSymbol(
          key: 'symbol-$index',
          data: data,
          textPos: icons ? null : anchors[frame][index],
          iconPos: icons ? anchors[frame][index] : null,
          icon: icons ? widget.icon : null,
          visible: true,
          fadeIn: false,
        ),
        growable: false,
      );
    }, growable: false);
    final positions = _LivePositions(variants.first, anchors, icons);

    return _ProbeCase(
      name: name,
      visual: visual,
      variants: variants,
      positions: positions,
    );
  }

  Map<String, Object> _treeCounts() {
    final context = _overlayKey.currentContext!;
    final elementTypes = <String, int>{};
    final renderTypes = <String, int>{};
    final layerTypes = <String, int>{};
    void walkElements(Element element) {
      final name = element.widget.runtimeType.toString();
      elementTypes.update(name, (n) => n + 1, ifAbsent: () => 1);
      element.visitChildren(walkElements);
    }

    void walkRender(RenderObject render) {
      final name = render.runtimeType.toString();
      renderTypes.update(name, (n) => n + 1, ifAbsent: () => 1);
      render.visitChildren(walkRender);
    }

    void walkLayers(Layer layer) {
      final name = layer.runtimeType.toString();
      layerTypes.update(name, (n) => n + 1, ifAbsent: () => 1);
      if (layer is ContainerLayer) {
        var child = layer.firstChild;
        while (child != null) {
          walkLayers(child);
          child = child.nextSibling;
        }
      }
    }

    walkElements(context as Element);
    walkRender(context.findRenderObject()!);
    for (final renderView in RendererBinding.instance.renderViews) {
      // Layer access remains available when debug getters are disabled.
      // ignore: invalid_use_of_protected_member
      final layer = renderView.layer;
      if (layer != null) walkLayers(layer);
    }

    return {
      'elements': elementTypes.values.fold<int>(0, (a, b) => a + b),
      'renderObjects': renderTypes.values.fold<int>(0, (a, b) => a + b),
      'elementTypes': elementTypes,
      'renderTypes': renderTypes,
      'wholeAppLayers': layerTypes.values.fold<int>(0, (a, b) => a + b),
      'wholeAppLayerTypes': layerTypes,
    };
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xffdedbd5),
    child: LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        if (!_running) {
          _running = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => unawaited(_run()),
          );
        }
        final active = _case;

        return SizedBox.expand(
          key: _overlayKey,
          child: active == null
              ? const SizedBox.shrink()
              : MapSymbolOverlay(
                  key: ValueKey(active.name),
                  symbols: active.symbols,
                  symbolsProvider: () => active.positions,
                  relayout: _relayout,
                  screenSize: _size,
                  onFadedOut: (_) {},
                  fadeDuration: Duration.zero,
                ),
        );
      },
    ),
  );
}

class _ProbeCase {
  _ProbeCase({
    required this.name,
    required this.visual,
    required this.variants,
    required this.positions,
  }) : symbols = variants.first;

  final String name;
  final bool visual;
  final List<List<MapSymbol>> variants;
  final _LivePositions positions;
  List<MapSymbol> symbols;
}

class _RelayoutNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

// ignore: invalid_use_of_internal_member
class _LivePositions extends ListBase<MapSymbol> implements SymbolPositionList {
  _LivePositions(this.symbols, this.anchors, this.icons)
    : indices = {for (var i = 0; i < symbols.length; i++) symbols[i].key: i};

  final List<MapSymbol> symbols;
  final List<List<Offset>> anchors;
  final Map<String, int> indices;
  final bool icons;
  int frame = 0;

  @override
  int get length => symbols.length;

  @override
  set length(int value) => throw UnsupportedError('Immutable membership');

  @override
  MapSymbol operator [](int index) => symbols[index];

  @override
  void operator []=(int index, MapSymbol value) =>
      throw UnsupportedError('Immutable membership');

  @override
  Offset? anchorFor(String key, {required bool icon}) {
    if (icon != icons) return null;
    final index = indices[key];

    return index == null ? null : anchors[frame][index];
  }

  @override
  MapSymbol positioned(MapSymbol symbol) => symbol;
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
