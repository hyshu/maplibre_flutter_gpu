import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';

import 'support/symbol_fixtures.dart';

void main() {
  test('symbol overlay rejects a negative fade duration', () {
    MapSymbolOverlay overlay({
      Duration fadeDuration = Duration.zero,
      EdgeInsets cullingPadding = EdgeInsets.zero,
    }) => MapSymbolOverlay(
      symbols: const [],
      screenSize: const Size(200, 200),
      onFadedOut: (_) {},
      fadeDuration: fadeDuration,
      cullingPadding: cullingPadding,
    );

    expect(
      () => overlay(fadeDuration: const Duration(microseconds: -1)),
      throwsAssertionError,
    );
  });

  testWidgets('null symbol builders hide icon and text', (tester) async {
    final symbol = MapSymbol(
      key: 'hidden',
      data: symbolLabel('hidden', 16),
      textPos: const Offset(100, 100),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [symbol],
          screenSize: const Size(200, 200),
          iconBuilder: null,
          textBuilder: null,
          onFadedOut: (_) {},
        ),
      ),
    );

    expect(find.text('hidden'), findsNothing);
  });

  testWidgets('zero style opacity skips default icon and text visuals', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final image = recorder.endRecording().toImageSync(1, 1);
    addTearDown(image.dispose);
    final symbol = MapSymbol(
      key: 'transparent-defaults',
      data: symbolLabel(
        'transparent text',
        16,
        textOpacity: 0,
        iconPlaced: true,
        icon: 'transparent-icon',
        iconOpacity: 0,
      ),
      textPos: const Offset(50, 50),
      iconPos: const Offset(50, 50),
      icon: SpriteIcon(
        atlas: image,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        pixelRatio: 1,
      ),
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [symbol],
          screenSize: const Size(100, 100),
          fadeDuration: Duration.zero,
          onFadedOut: (_) {},
        ),
      ),
    );

    expect(find.text('transparent text'), findsNothing);
    expect(find.byType(SpriteIconWidget), findsNothing);
  });

  testWidgets('custom builders can ignore zero style opacity', (tester) async {
    var iconBuilds = 0;
    var textBuilds = 0;
    final symbol = MapSymbol(
      key: 'transparent-custom',
      data: symbolLabel('transparent data', 16, textOpacity: 0, iconOpacity: 0),
      textPos: const Offset(40, 50),
      iconPos: const Offset(60, 50),
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [symbol],
          screenSize: const Size(100, 100),
          fadeDuration: Duration.zero,
          iconBuilder: (_, _) {
            iconBuilds++;

            return const Text('custom icon');
          },
          textBuilder: (_, _) {
            textBuilds++;

            return const Text('custom text');
          },
          onFadedOut: (_) {},
        ),
      ),
    );

    expect(iconBuilds, 1);
    expect(textBuilds, 1);
    expect(find.text('custom icon'), findsOneWidget);
    expect(find.text('custom text'), findsOneWidget);
  });

  testWidgets('zero-duration hidden defaults skip their visual subtree', (
    tester,
  ) async {
    final faded = <String>[];
    final data = symbolLabel('removed immediately', 16);

    Future<void> pump(bool visible) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [
            MapSymbol(
              key: 'immediate-default',
              data: data,
              textPos: const Offset(50, 50),
              iconPos: null,
              icon: null,
              visible: visible,
              fadeIn: false,
            ),
          ],
          screenSize: const Size(100, 100),
          fadeDuration: Duration.zero,
          onFadedOut: faded.add,
        ),
      ),
    );

    await pump(true);
    expect(find.text('removed immediately'), findsOneWidget);

    await pump(false);
    expect(find.text('removed immediately'), findsNothing);
    expect(faded, ['immediate-default']);
  });

  testWidgets('zero-duration hidden custom visuals keep their lifecycle', (
    tester,
  ) async {
    var builds = 0;

    Future<void> pump(bool visible) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [
            MapSymbol(
              key: 'immediate-custom',
              data: symbolLabel('custom data', 16),
              textPos: const Offset(50, 50),
              iconPos: null,
              icon: null,
              visible: visible,
              fadeIn: false,
            ),
          ],
          screenSize: const Size(100, 100),
          fadeDuration: Duration.zero,
          textBuilder: (_, _) {
            builds++;

            return const Text('hidden custom');
          },
          onFadedOut: (_) {},
        ),
      ),
    );

    await pump(true);
    await pump(false);
    await tester.pump();

    expect(builds, 2);
    expect(find.text('hidden custom'), findsOneWidget);
  });

  testWidgets('paints native groups with icons before text', (tester) async {
    MapSymbol symbol(String key, int group, int order) => MapSymbol(
      key: key,
      data: symbolLabel(key, 12, renderGroup: group, renderOrder: order),
      textPos: const Offset(50, 50),
      iconPos: const Offset(50, 50),
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [
            symbol('front', 0, 1),
            symbol('later', 1, 0),
            symbol('back', 0, 0),
          ],
          screenSize: const Size(100, 100),
          fadeDuration: Duration.zero,
          onFadedOut: (_) {},
          iconBuilder: (_, symbol) => Text('icon:${symbol.key}'),
          textBuilder: (_, symbol) => Text('text:${symbol.key}'),
        ),
      ),
    );

    final overlay = find.byType(MapSymbolOverlay);
    final boundaries = tester.widgetList<RepaintBoundary>(
      find.descendant(of: overlay, matching: find.byType(RepaintBoundary)),
    );
    expect(
      boundaries.map((boundary) => (boundary.key! as ValueKey<Object>).value),
      <Object>[
        ('back', true),
        ('front', true),
        ('back', false),
        ('front', false),
        ('later', true),
        ('later', false),
      ],
    );
    expect(find.byType(CustomMultiChildLayout), findsNothing);
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(
      tester.allRenderObjects
          .where(
            (renderObject) =>
                renderObject.runtimeType.toString() == '_RenderSymbolBatch',
          )
          .toSet(),
      hasLength(1),
    );
  });

  testWidgets('default symbols share one structural batch per overlay', (
    tester,
  ) async {
    final symbols = [
      for (var i = 0; i < 64; i++)
        MapSymbol(
          key: 'batch:$i',
          data: symbolLabel('label $i', 12, renderOrder: i),
          textPos: Offset(20 + (i % 8) * 40, 20 + (i ~/ 8) * 40),
          iconPos: null,
          icon: null,
          visible: true,
          fadeIn: false,
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: symbols,
          screenSize: const Size(340, 340),
          fadeDuration: Duration.zero,
          cullingPadding: EdgeInsets.zero,
          onFadedOut: (_) {},
        ),
      ),
    );

    final overlay = find.byType(MapSymbolOverlay);
    expect(
      find.descendant(of: overlay, matching: find.byType(Text)),
      findsNWidgets(64),
    );
    expect(
      find.descendant(of: overlay, matching: find.byType(LayoutId)),
      findsNothing,
    );
    expect(
      find.descendant(of: overlay, matching: find.byType(AnimatedOpacity)),
      findsNothing,
    );
    final batches = tester.allRenderObjects
        .where(
          (renderObject) =>
              renderObject.runtimeType.toString() == '_RenderSymbolBatch',
        )
        .toSet();
    expect(batches, hasLength(1));
    expect(batches.single.isRepaintBoundary, isFalse);
    expect(
      find.descendant(of: overlay, matching: find.byType(RepaintBoundary)),
      findsNWidgets(64),
    );
  });

  testWidgets('custom symbols receive taps while defaults pass them through', (
    tester,
  ) async {
    final symbol = MapSymbol(
      key: 'tap-target',
      data: symbolLabel('tap target', 16),
      textPos: const Offset(100, 100),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );
    var mapTaps = 0;
    var symbolTaps = 0;

    Future<void> pump(SymbolWidgetBuilder textBuilder) => tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => mapTaps++,
              ),
            ),
            Positioned.fill(
              child: MapSymbolOverlay(
                symbols: [symbol],
                screenSize: const Size(200, 200),
                onFadedOut: (_) {},
                textBuilder: textBuilder,
              ),
            ),
          ],
        ),
      ),
    );

    await pump(buildDefaultSymbolText);
    await tester.tapAt(tester.getCenter(find.text('tap target')));
    await tester.pump();

    expect(mapTaps, 1);
    expect(symbolTaps, 0);

    await pump(
      (_, _) => GestureDetector(
        key: const ValueKey('custom-symbol'),
        behavior: HitTestBehavior.opaque,
        onTap: () => symbolTaps++,
        child: const SizedBox(width: 80, height: 40),
      ),
    );
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('custom-symbol'))),
    );
    await tester.pump();

    expect(mapTaps, 1);
    expect(symbolTaps, 1);
  });

  testWidgets('hidden custom symbols pass taps through while fading out', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var mapTaps = 0;
    var symbolTaps = 0;

    Future<void> pump(bool visible) => tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => mapTaps++,
              ),
            ),
            Positioned.fill(
              child: MapSymbolOverlay(
                symbols: [
                  MapSymbol(
                    key: 'fading-tap-target',
                    data: symbolLabel('fading tap target', 16),
                    textPos: const Offset(100, 100),
                    iconPos: null,
                    icon: null,
                    visible: visible,
                  ),
                ],
                screenSize: const Size(200, 200),
                fadeDuration: const Duration(seconds: 1),
                onFadedOut: (_) {},
                textBuilder: (_, _) => GestureDetector(
                  key: const ValueKey('fading-custom-symbol'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => symbolTaps++,
                  child: const SizedBox(width: 80, height: 40),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    await pump(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('fading-custom-symbol')))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    await pump(false);

    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('fading-custom-symbol')))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('fading-custom-symbol'))),
    );
    await tester.pump();

    expect(mapTaps, 1);
    expect(symbolTaps, 0);
    semantics.dispose();
  });

  testWidgets('symbol culling padding is configurable', (tester) async {
    final symbol = MapSymbol(
      key: 'outside',
      data: symbolLabel('outside', 16),
      textPos: const Offset(-50, 100),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    Future<void> pump(EdgeInsets padding) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [symbol],
          screenSize: const Size(200, 200),
          cullingPadding: padding,
          onFadedOut: (_) {},
        ),
      ),
    );

    await pump(EdgeInsets.zero);
    expect(find.text('outside'), findsNothing);
    await pump(const EdgeInsets.only(left: 60));
    expect(find.text('outside'), findsOneWidget);
  });

  testWidgets('culls text and icon with their own anchors', (tester) async {
    Future<void> pump({required Offset textPos, required Offset iconPos}) =>
        tester.pumpWidget(
          MaterialApp(
            home: MapSymbolOverlay(
              symbols: [
                MapSymbol(
                  key: 'split',
                  data: symbolLabel('split', 12),
                  textPos: textPos,
                  iconPos: iconPos,
                  icon: null,
                  visible: true,
                  fadeIn: false,
                ),
              ],
              screenSize: const Size(100, 100),
              cullingPadding: EdgeInsets.zero,
              fadeDuration: Duration.zero,
              onFadedOut: (_) {},
              iconBuilder: (_, _) => const Text('inside icon'),
              textBuilder: (_, _) => const Text('inside text'),
            ),
          ),
        );

    await pump(textPos: const Offset(-10, 50), iconPos: const Offset(50, 50));
    expect(find.text('inside icon'), findsOneWidget);
    expect(find.text('inside text'), findsNothing);

    await pump(textPos: const Offset(50, 50), iconPos: const Offset(110, 50));
    expect(find.text('inside icon'), findsNothing);
    expect(find.text('inside text'), findsOneWidget);
  });

  testWidgets('relayout rebuilds a component that enters the culling area', (
    tester,
  ) async {
    final relayout = ValueNotifier<int>(0);
    final data = symbolLabel('moving', 12);
    var current = MapSymbol(
      key: 'moving',
      data: data,
      textPos: const Offset(-10, 50),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [current],
          symbolsProvider: () => [current],
          relayout: relayout,
          screenSize: const Size(100, 100),
          cullingPadding: EdgeInsets.zero,
          fadeDuration: Duration.zero,
          onFadedOut: (_) {},
          textBuilder: (_, _) => const Text('moving child'),
        ),
      ),
    );
    expect(find.text('moving child'), findsNothing);

    current = MapSymbol(
      key: 'moving',
      data: data,
      textPos: const Offset(50, 50),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );
    relayout.value++;
    await tester.pump();

    expect(find.text('moving child'), findsOneWidget);
    relayout.dispose();
  });

  testWidgets('invalid culling padding falls back to zero', (tester) async {
    final symbol = MapSymbol(
      key: 'outside',
      data: symbolLabel('outside', 16),
      textPos: const Offset(250, 100),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    Future<void> pump(EdgeInsets padding) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [symbol],
          screenSize: const Size(200, 200),
          cullingPadding: padding,
          onFadedOut: (_) {},
        ),
      ),
    );

    await pump(const EdgeInsets.only(right: double.infinity));
    expect(find.text('outside'), findsNothing);
    await pump(const EdgeInsets.only(right: -1));
    expect(find.text('outside'), findsNothing);
  });

  testWidgets('culled hidden symbols complete removal without a fade widget', (
    tester,
  ) async {
    final fadedKeys = <String>[];
    final hidden = MapSymbol(
      key: 'labels:gone',
      data: symbolLabel('gone', 12, crossTileId: 7),
      textPos: const Offset(-1000, -1000),
      iconPos: null,
      icon: null,
      visible: false,
      fadeIn: false,
    );
    final visible = MapSymbol(
      key: 'labels:visible',
      data: symbolLabel('visible', 12, crossTileId: 8),
      textPos: const Offset(-1000, -1000),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [hidden, visible],
          screenSize: const Size(200, 200),
          onFadedOut: fadedKeys.add,
        ),
      ),
    );
    await tester.pump();

    expect(fadedKeys, contains('labels:gone'));
    expect(fadedKeys, isNot(contains('labels:visible')));
    expect(find.text('gone'), findsNothing);
  });
}
