import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/labels/label_data.dart';
import 'package:maplibre_flutter_gpu/src/labels/label_source.dart';
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart'
    hide LabelData;
import 'package:maplibre_flutter_gpu/src/sprites/sprite_atlas.dart';
import 'package:maplibre_flutter_gpu/src/widgets/map/map_render_freeze.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/map_symbol.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/map_symbol_layer.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/symbol_overlay.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/symbol_profile_counters.dart';

import 'support/symbol_finders.dart';

LabelData _label({
  int id = 42,
  int layer = 1,
  String text = 'A',
  double x = 60,
  double y = 70,
  double iconX = 120,
  double iconY = 130,
  double offset = 0,
  double translateX = 0,
  double translateY = 0,
  double size = 16,
  double opacity = 1,
  int order = 0,
  bool icon = false,
  LabelAffineTransform transform = const LabelAffineTransform(),
  List<String> fonts = const [],
  List<LabelPathPoint> path = const [],
}) => LabelData(
  crossTileId: id,
  lat: y,
  lon: x,
  iconLat: iconY,
  iconLon: iconX,
  textOffsetX: offset,
  textTranslateX: translateX,
  textTranslateY: translateY,
  fontSize: size,
  textR: 0,
  textG: 0,
  textB: 0,
  textA: 1,
  haloR: 0,
  haloG: 0,
  haloB: 0,
  haloA: 0,
  haloWidth: 0,
  textOpacity: opacity,
  textTransform: transform,
  textFonts: fonts,
  textPath: path,
  iconPlaced: icon,
  icon: icon ? 'pin' : '',
  text: text,
  layer: 'places-$layer',
  layerIndex: layer,
  renderOrder: order,
);

class _Bridge implements MaplibreBridge {
  var version = 0;
  var labels = <LabelData>[];
  var translation = Offset.zero;

  @override
  int getLabelsVersion() => version;

  @override
  List<LabelData> getPlacedLabels() => labels;

  @override
  List<Offset> wrappedLatLonsToScreen(
    List<({double latitude, double longitude, int tileWrap})> coordinates,
  ) => [
    for (final coordinate in coordinates)
      Offset(coordinate.longitude, coordinate.latitude) + translation,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _Scene {
  final labels = MapLabelSource();
  final bridge = _Bridge();
  SpriteAtlas? atlas;

  void publish(List<LabelData> data, {bool settleFade = false}) {
    bridge.version++;
    bridge.labels = data;
    labels.syncFromNative(bridge);
    labels.cacheScreenPositions(bridge, atlas);
    if (settleFade) labels.cacheScreenPositions(bridge, atlas);
  }

  void project(Offset translation) {
    bridge.translation = translation;
    labels.cacheScreenPositions(bridge, atlas);
  }
}

class _Atlas(final SpriteIcon? icon) implements SpriteAtlas {
  @override
  SpriteIcon? operator [](String name) => name == 'pin' ? icon : null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _TrackedNotifier extends ChangeNotifier {
  var listeners = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }
}

class _CustomChild extends StatefulWidget {
  const _CustomChild(this.symbol, this.onTap);

  final MapSymbol symbol;
  final VoidCallback onTap;

  @override
  State<_CustomChild> createState() => _CustomChildState();
}

class _CustomChildState extends State<_CustomChild> {
  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('custom-label'),
    onTap: widget.onTap,
    behavior: HitTestBehavior.opaque,
    child: Text('${widget.symbol.data.lon}'),
  );
}

Widget _view(Widget child, {double textScale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 300, height: 300, child: child),
    ),
  ),
);

Finder _overlay(int layer) => find.descendant(
  of: find.byKey(ValueKey('layer:$layer')),
  matching: find.byType(MapSymbolOverlay),
);

int _counter(String key) => SymbolProfileCounters.snapshot()[key] ?? 0;

Widget _layer(
  _Scene scene,
  Listenable relayout, {
  int layer = 1,
  Size size = const Size(300, 300),
  Duration fade = Duration.zero,
  EdgeInsets padding = EdgeInsets.zero,
  SymbolSemanticsMode semantics = SymbolSemanticsMode.labels,
  SymbolWidgetBuilder? textBuilder = buildDefaultSymbolText,
  SymbolWidgetBuilder? iconBuilder = buildDefaultSymbolIcon,
}) => MapSymbolLayer(
  key: ValueKey('layer:$layer'),
  labels: scene.labels,
  layerIndex: layer,
  symbols: scene.labels.symbolsForLayer(layer),
  relayout: relayout,
  screenSize: size,
  fadeDuration: fade,
  cullingPadding: padding,
  semanticsMode: semantics,
  textBuilder: textBuilder,
  iconBuilder: iconBuilder,
);

const _reuseFlag = bool.fromEnvironment('MAPLIBRE_REUSE_SYMBOL_LAYERS');

void _testWidgets(
  String description,
  Future<void> Function(WidgetTester) body, {
  bool skip = false,
}) => testWidgets(description, (tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    await body(tester);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}, skip: skip);

void main() {
  test('reuse flag only enables the Android path', () {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(symbolLayerReuseEnabled, _reuseFlag);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(symbolLayerReuseEnabled, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    _testWidgets('direct layer honors the flag and $platform gate', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final scene = _Scene()..publish([_label()], settleFade: true);
      final relayout = ChangeNotifier();
      addTearDown(relayout.dispose);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      final original = tester.widget<MapSymbolOverlay>(_overlay(1));
      final builds = _counter(SymbolProfileCounters.overlayBuilds);
      scene.publish([_label(x: 120)]);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      final enabled = _reuseFlag && platform == TargetPlatform.android;
      expect(
        identical(tester.widget<MapSymbolOverlay>(_overlay(1)), original),
        enabled,
      );
      expect(
        _counter(SymbolProfileCounters.overlayBuilds),
        builds + (enabled ? 0 : 1),
      );
      expect(tester.getCenter(symbolTextBlock('A')), const Offset(120, 70));
    });
  }

  _testWidgets(
    'retains the built baseline across cumulative native anchor updates',
    (tester) async {
      final scene = _Scene()..publish([_label()], settleFade: true);
      final relayout = ChangeNotifier();
      addTearDown(relayout.dispose);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      final original = tester.widget<MapSymbolOverlay>(_overlay(1));
      final state = tester.state(_overlay(1));
      final textElement = tester.element(symbolTextBlock('A'));
      final builds = _counter(SymbolProfileCounters.overlayBuilds);
      final layouts = _counter(SymbolProfileCounters.batchLayouts);

      for (final x in [90.0, 120.0, 150.0]) {
        scene.publish([_label(x: x, offset: 3)]);
        await tester.pumpWidget(_view(_layer(scene, relayout)));
        expect(tester.widget<MapSymbolOverlay>(_overlay(1)), same(original));
        expect(original.symbols.single.data.lon, 60);
        expect(original.symbols.single.textPos, const Offset(60, 70));
        expect(tester.element(symbolTextBlock('A')), same(textElement));
        expect(tester.getCenter(symbolTextBlock('A')), Offset(x + 3, 70));
      }
      expect(_counter(SymbolProfileCounters.overlayBuilds), builds);
      expect(_counter(SymbolProfileCounters.batchLayouts), layouts);

      scene.publish([_label(text: 'Changed', x: 180)]);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      final replacement = tester.widget<MapSymbolOverlay>(_overlay(1));
      expect(replacement, isNot(same(original)));
      expect(tester.state(_overlay(1)), same(state));
      expect(symbolTextBlock('Changed'), findsOneWidget);
      scene.publish([_label(text: 'Changed', x: 210)]);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      expect(tester.widget<MapSymbolOverlay>(_overlay(1)), same(replacement));
      expect(replacement.symbols.single.textPos, const Offset(180, 70));
      expect(
        tester.getCenter(symbolTextBlock('Changed')),
        const Offset(210, 70),
      );
    },
    skip: !_reuseFlag,
  );

  _testWidgets(
    'native center offsets reuse while paint translation requires a new child',
    (tester) async {
      final scene = _Scene()..publish([_label(offset: 2)], settleFade: true);
      final relayout = ChangeNotifier();
      addTearDown(relayout.dispose);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      var previous = tester.widget<MapSymbolOverlay>(_overlay(1));
      scene.publish([_label(offset: 8)]);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      expect(tester.widget<MapSymbolOverlay>(_overlay(1)), same(previous));
      expect(tester.getCenter(symbolTextBlock('A')), const Offset(68, 70));
      for (final translation in [(2.0, 0.0), (2.0, 3.0)]) {
        scene.publish([
          _label(
            offset: 8,
            translateX: translation.$1,
            translateY: translation.$2,
          ),
        ]);
        await tester.pumpWidget(_view(_layer(scene, relayout)));
        final current = tester.widget<MapSymbolOverlay>(_overlay(1));
        expect(current, isNot(same(previous)));
        expect(current.symbols.single.data.textTranslateX, translation.$1);
        expect(current.symbols.single.data.textTranslateY, translation.$2);
        previous = current;
      }
    },
    skip: !_reuseFlag,
  );

  _testWidgets(
    'one layer retains its child while another layer changes paint',
    (tester) async {
      final scene = _Scene()
        ..publish([
          _label(),
          _label(id: 43, layer: 2, text: 'B'),
        ], settleFade: true);
      final relayout = _TrackedNotifier();
      addTearDown(relayout.dispose);
      Widget content() => _view(
        Stack(
          children: [
            _layer(scene, relayout),
            _layer(scene, relayout, layer: 2),
          ],
        ),
      );
      await tester.pumpWidget(content());
      final first = tester.widget<MapSymbolOverlay>(_overlay(1));
      final second = tester.widget<MapSymbolOverlay>(_overlay(2));
      final firstState = tester.state(_overlay(1));
      final secondState = tester.state(_overlay(2));
      expect(relayout.listeners, 2);
      final builds = _counter(SymbolProfileCounters.overlayBuilds);
      scene.publish([
        _label(x: 100),
        _label(id: 43, layer: 2, text: 'B', opacity: .5),
      ]);
      await tester.pumpWidget(content());
      expect(tester.widget<MapSymbolOverlay>(_overlay(1)), same(first));
      expect(tester.widget<MapSymbolOverlay>(_overlay(2)), isNot(same(second)));
      expect(_counter(SymbolProfileCounters.overlayBuilds), builds + 1);
      expect(tester.getCenter(symbolTextBlock('A')), const Offset(100, 70));
      await tester.pumpWidget(
        _view(
          Stack(
            children: [
              _layer(scene, relayout, layer: 2),
              _layer(scene, relayout),
            ],
          ),
        ),
      );
      expect(tester.state(_overlay(1)), same(firstState));
      expect(tester.state(_overlay(2)), same(secondState));
      await tester.pumpWidget(
        _view(Stack(children: [_layer(scene, relayout, layer: 2)])),
      );
      expect(relayout.listeners, 1);
      expect(tester.state(_overlay(2)), same(secondState));
      await tester.pumpWidget(const SizedBox());
      expect(relayout.listeners, 0);
    },
    skip: !_reuseFlag,
  );

  _testWidgets(
    'culling changes during an ancestor update rebuild the retained overlay',
    (tester) async {
      final scene = _Scene()..publish([_label(x: -20)], settleFade: true);
      final relayout = ChangeNotifier();
      addTearDown(relayout.dispose);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      final original = tester.widget<MapSymbolOverlay>(_overlay(1));
      expect(symbolTextBlock('A'), findsNothing);
      scene.publish([_label(x: 100)]);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      expect(tester.takeException(), isNull);
      expect(tester.widget<MapSymbolOverlay>(_overlay(1)), same(original));
      expect(symbolTextBlock('A'), findsOneWidget);
      expect(tester.getCenter(symbolTextBlock('A')), const Offset(100, 70));
      scene.publish([_label(x: 320)]);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      expect(tester.takeException(), isNull);
      expect(symbolTextBlock('A'), findsNothing);
    },
    skip: !_reuseFlag,
  );

  _testWidgets('retained symbols move text and icon anchors independently', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(2, 2);
    picture.dispose();
    addTearDown(image.dispose);
    final sprite = SpriteIcon(
      atlas: image,
      x: 0,
      y: 0,
      width: 2,
      height: 2,
      pixelRatio: 1,
    );
    final scene = _Scene()..atlas = _Atlas(sprite);
    scene.publish([_label(icon: true)], settleFade: true);
    final relayout = ChangeNotifier();
    addTearDown(relayout.dispose);
    await tester.pumpWidget(_view(_layer(scene, relayout)));
    final original = tester.widget<MapSymbolOverlay>(_overlay(1));
    scene.publish([_label(icon: true, x: 95, y: 105, iconX: 190, iconY: 200)]);
    await tester.pumpWidget(_view(_layer(scene, relayout)));
    expect(tester.widget<MapSymbolOverlay>(_overlay(1)), same(original));
    expect(tester.getCenter(symbolTextBlock('A')), const Offset(95, 105));
    expect(
      tester.getCenter(find.byType(SpriteIconWidget)),
      const Offset(190, 200),
    );
    await tester.pumpWidget(const SizedBox());
  }, skip: !_reuseFlag);

  _testWidgets(
    'visual changes and reordered membership replace child configuration',
    (tester) async {
      final scene = _Scene()..publish([_label()], settleFade: true);
      final relayout = ChangeNotifier();
      addTearDown(relayout.dispose);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      final state = tester.state(_overlay(1));
      var previous = tester.widget<MapSymbolOverlay>(_overlay(1));
      for (final next in [
        _label(opacity: .5),
        _label(transform: const LabelAffineTransform(xy: .2)),
        _label(size: 18),
        _label(fonts: ['Another font']),
        _label(path: [const LabelPathPoint(1, 2)]),
        _label(icon: true),
        _label(text: 'Other content'),
      ]) {
        scene.publish([next]);
        await tester.pumpWidget(_view(_layer(scene, relayout)));
        final current = tester.widget<MapSymbolOverlay>(_overlay(1));
        expect(current, isNot(same(previous)));
        expect(tester.state(_overlay(1)), same(state));
        previous = current;
      }
      scene.publish([
        _label(),
        _label(id: 43, text: 'B', order: 1),
      ], settleFade: true);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      previous = tester.widget<MapSymbolOverlay>(_overlay(1));
      scene.publish([_label(order: 1), _label(id: 43, text: 'B')]);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      final reordered = tester.widget<MapSymbolOverlay>(_overlay(1));
      expect(reordered, isNot(same(previous)));
      expect(reordered.symbols.map((symbol) => symbol.data.text), ['B', 'A']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  _testWidgets('overlay options, atlas and source changes use normal updates', (
    tester,
  ) async {
    var scene = _Scene()..publish([_label()], settleFade: true);
    final relayout = ChangeNotifier();
    addTearDown(relayout.dispose);
    await tester.pumpWidget(_view(_layer(scene, relayout)));
    final state = tester.state(_overlay(1));
    var previous = tester.widget<MapSymbolOverlay>(_overlay(1));
    for (final layer in [
      _layer(scene, relayout, size: const Size(280, 260)),
      _layer(scene, relayout, padding: const EdgeInsets.all(30)),
      _layer(scene, relayout, fade: const Duration(milliseconds: 180)),
      _layer(scene, relayout, semantics: SymbolSemanticsMode.none),
    ]) {
      await tester.pumpWidget(_view(layer));
      final current = tester.widget<MapSymbolOverlay>(_overlay(1));
      expect(current, isNot(same(previous)));
      expect(tester.state(_overlay(1)), same(state));
      previous = current;
    }
    await tester.pumpWidget(_view(_layer(scene, relayout)));
    previous = tester.widget<MapSymbolOverlay>(_overlay(1));
    scene.atlas = _Atlas(null);
    scene.publish([_label()]);
    await tester.pumpWidget(_view(_layer(scene, relayout)));
    expect(tester.widget<MapSymbolOverlay>(_overlay(1)), isNot(same(previous)));
    previous = tester.widget<MapSymbolOverlay>(_overlay(1));
    final atlas = scene.atlas;
    scene = _Scene()..atlas = atlas;
    scene.publish([_label()], settleFade: true);
    await tester.pumpWidget(_view(_layer(scene, relayout)));
    expect(tester.widget<MapSymbolOverlay>(_overlay(1)), isNot(same(previous)));
    expect(tester.state(_overlay(1)), same(state));
  });

  _testWidgets(
    'deferred native updates compare against the installed child baseline',
    (tester) async {
      final scene = _Scene()..publish([_label()], settleFade: true);
      final relayout = ChangeNotifier();
      addTearDown(relayout.dispose);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      final original = tester.widget<MapSymbolOverlay>(_overlay(1));
      scene.publish([_label(opacity: .5)]);
      scene.publish([_label(opacity: .5, x: 130)]);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      final changed = tester.widget<MapSymbolOverlay>(_overlay(1));
      expect(changed, isNot(same(original)));
      expect(changed.symbols.single.data.textOpacity, .5);
      expect(tester.getCenter(symbolTextBlock('A')), const Offset(130, 70));

      scene.publish([_label(opacity: .8, x: 150)]);
      scene.publish([_label(opacity: .5, x: 180)]);
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      expect(tester.widget<MapSymbolOverlay>(_overlay(1)), same(changed));
      expect(changed.symbols.single.textPos, const Offset(130, 70));
      expect(tester.getCenter(symbolTextBlock('A')), const Offset(180, 70));
    },
    skip: !_reuseFlag,
  );

  _testWidgets(
    'upstream listener replacement and disposal stop obsolete updates',
    (tester) async {
      final scene = _Scene()..publish([_label()], settleFade: true);
      final first = _TrackedNotifier();
      final second = _TrackedNotifier();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(_view(_layer(scene, first)));
      expect(first.listeners, 1);
      await tester.pumpWidget(_view(_layer(scene, second)));
      expect(first.listeners, 0);
      expect(second.listeners, 1);

      scene.project(const Offset(30, 40));
      first.notifyListeners();
      await tester.pump();
      expect(tester.getCenter(symbolTextBlock('A')), const Offset(60, 70));
      second.notifyListeners();
      await tester.pump();
      expect(tester.getCenter(symbolTextBlock('A')), const Offset(90, 110));
      await tester.pumpWidget(const SizedBox());
      expect(second.listeners, 0);
      second.notifyListeners();
      first.notifyListeners();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  _testWidgets(
    'builder transitions preserve overlay state and custom data and taps',
    (tester) async {
      final scene = _Scene()..publish([_label()], settleFade: true);
      final relayout = ChangeNotifier();
      addTearDown(relayout.dispose);
      final seen = <MapSymbol>[];
      final tapped = <MapSymbol>[];
      Widget custom(BuildContext context, MapSymbol symbol) {
        seen.add(symbol);

        return _CustomChild(symbol, () => tapped.add(symbol));
      }

      await tester.pumpWidget(_view(_layer(scene, relayout)));
      final overlayState = tester.state(_overlay(1));
      await tester.pumpWidget(
        _view(_layer(scene, relayout, textBuilder: custom)),
      );
      expect(tester.state(_overlay(1)), same(overlayState));
      final customState = tester.state(find.byType(_CustomChild));
      final before = tester.widget<MapSymbolOverlay>(_overlay(1));
      scene.publish([_label(x: 140, offset: 5)]);
      await tester.pumpWidget(
        _view(_layer(scene, relayout, textBuilder: custom)),
      );
      expect(tester.widget<MapSymbolOverlay>(_overlay(1)), isNot(same(before)));
      expect(tester.state(find.byType(_CustomChild)), same(customState));
      expect(seen.last.data.lon, 140);
      expect(seen.last.data.textOffsetX, 5);
      expect(seen.last.textPos, const Offset(145, 70));
      await tester.tap(find.byKey(const ValueKey('custom-label')));
      expect(tapped.single.data.lon, 140);
      expect(tapped.single.textPos, const Offset(145, 70));
      await tester.pumpWidget(_view(_layer(scene, relayout)));
      expect(tester.state(_overlay(1)), same(overlayState));
      expect(symbolTextBlock('A'), findsOneWidget);
      expect(find.byType(_CustomChild), findsNothing);
    },
  );

  _testWidgets('retained descendants still respond to ambient text scaling', (
    tester,
  ) async {
    final scene = _Scene()..publish([_label()], settleFade: true);
    final relayout = ChangeNotifier();
    addTearDown(relayout.dispose);
    await tester.pumpWidget(_view(_layer(scene, relayout)));
    final original = tester.widget<MapSymbolOverlay>(_overlay(1));
    final before = tester.getSize(symbolTextBlock('A'));
    await tester.pumpWidget(_view(_layer(scene, relayout), textScale: 2));
    expect(tester.widget<MapSymbolOverlay>(_overlay(1)), same(original));
    expect(
      tester.getSize(symbolTextBlock('A')).height,
      greaterThan(before.height),
    );
    expect(tester.getCenter(symbolTextBlock('A')), const Offset(60, 70));
  }, skip: !_reuseFlag);

  _testWidgets('text settling continues after an eligible retained update', (
    tester,
  ) async {
    final scene = _Scene()..publish([_label(size: 13.1)], settleFade: true);
    final relayout = ChangeNotifier();
    addTearDown(relayout.dispose);
    await tester.pumpWidget(_view(_layer(scene, relayout)));
    scene.publish([_label(size: 13.11)]);
    await tester.pumpWidget(_view(_layer(scene, relayout)));
    final original = tester.widget<MapSymbolOverlay>(_overlay(1));
    expect(symbolTextStyle(tester, 'A')?.fontSize, 13.1);
    scene.publish([_label(size: 13.11, x: 110)]);
    await tester.pumpWidget(_view(_layer(scene, relayout)));
    expect(tester.widget<MapSymbolOverlay>(_overlay(1)), same(original));
    await tester.pump(const Duration(milliseconds: 150));
    expect(symbolTextStyle(tester, 'A')?.fontSize, 13.11);
    expect(tester.getCenter(symbolTextBlock('A')), const Offset(110, 70));
    await tester.pumpWidget(const SizedBox());
  }, skip: !_reuseFlag);

  _testWidgets(
    'pause retains the painted content and resume adopts latest data',
    (tester) async {
      final scene = _Scene()..publish([_label()], settleFade: true);
      final relayout = ChangeNotifier();
      final freeze = MapRenderFreezeController();
      addTearDown(relayout.dispose);
      addTearDown(freeze.dispose);
      Widget content() => _view(
        MapRenderFreeze(controller: freeze, child: _layer(scene, relayout)),
      );
      await tester.pumpWidget(content());
      freeze.pause(1);
      scene.publish([_label(text: 'Paused change', x: 110)]);
      await tester.pumpWidget(content());
      scene.publish([_label(text: 'Paused change', x: 160)]);
      await tester.pumpWidget(content());
      relayout.notifyListeners();
      await tester.pump(const Duration(seconds: 1));
      expect(symbolTextBlock('A'), findsOneWidget);
      expect(symbolTextBlock('Paused change'), findsNothing);
      expect(tester.getCenter(symbolTextBlock('A')), const Offset(60, 70));
      freeze.resume();
      freeze.reveal();
      await tester.pump();
      expect(symbolTextBlock('Paused change'), findsOneWidget);
      expect(
        tester.getCenter(symbolTextBlock('Paused change')),
        const Offset(160, 70),
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  _testWidgets(
    'fade changes replace configuration and completion removes hidden entries',
    (tester) async {
      final scene = _Scene()..publish([_label()], settleFade: true);
      final relayout = ChangeNotifier();
      addTearDown(relayout.dispose);
      Widget content() => _view(
        _layer(scene, relayout, fade: const Duration(milliseconds: 100)),
      );
      await tester.pumpWidget(content());
      final original = tester.widget<MapSymbolOverlay>(_overlay(1));
      final key = original.symbols.single.key;
      scene.publish([]);
      await tester.pumpWidget(content());
      final hidden = tester.widget<MapSymbolOverlay>(_overlay(1));
      expect(hidden, isNot(same(original)));
      expect(hidden.symbols.single.visible, isFalse);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(scene.labels.entries.containsKey(key), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
