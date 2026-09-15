import 'dart:collection' show ListBase;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/map_symbol.dart';

import 'support/symbol_fixtures.dart';

class _IdentityProbe extends StatefulWidget {
  final String value;

  const _IdentityProbe(this.value);

  @override
  State<_IdentityProbe> createState() => _IdentityProbeState();
}

class _IdentityProbeState extends State<_IdentityProbe> {
  @override
  Widget build(BuildContext context) => Text(widget.value);
}

class _CountingSymbolPositionList(final List<MapSymbol> _symbols)
    extends ListBase<MapSymbol>
    implements SymbolPositionList {
  var textPosition = Offset.zero;
  var indexedReads = 0;
  var positionedReads = 0;
  var anchorReads = 0;

  @override
  int get length => _symbols.length;

  @override
  set length(int value) => throw UnsupportedError('immutable symbol view');

  @override
  MapSymbol operator [](int index) {
    indexedReads++;

    return _symbols[index];
  }

  @override
  void operator []=(int index, MapSymbol value) =>
      throw UnsupportedError('immutable symbol view');

  @override
  Offset? anchorFor(String key, {required bool icon}) {
    anchorReads++;
    if (key != _symbols.single.key || icon) return null;

    return textPosition;
  }

  @override
  MapSymbol positioned(MapSymbol symbol) {
    positionedReads++;

    return MapSymbol(
      key: symbol.key,
      data: symbol.data,
      textPos: textPosition,
      iconPos: null,
      icon: symbol.icon,
      spriteAtlas: symbol.spriteAtlas,
      visible: symbol.visible,
      fadeIn: symbol.fadeIn,
    );
  }
}

void main() {
  testWidgets('stable symbol key preserves widget state while data moves', (
    tester,
  ) async {
    Future<void> pump(MapSymbol symbol) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [symbol],
          screenSize: const Size(200, 200),
          fadeDuration: Duration.zero,
          onFadedOut: (_) {},
          textBuilder: (_, symbol) => _IdentityProbe(symbol.data.text),
        ),
      ),
    );

    await pump(
      MapSymbol(
        key: 'roads:42',
        data: symbolLabel('old', 12, crossTileId: 42),
        textPos: const Offset(20, 30),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
    );
    final originalState = tester.state<_IdentityProbeState>(
      find.byType(_IdentityProbe),
    );

    await pump(
      MapSymbol(
        key: 'roads:42',
        data: symbolLabel('new', 12, crossTileId: 42),
        textPos: const Offset(120, 130),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
    );

    expect(
      identical(
        tester.state<_IdentityProbeState>(find.byType(_IdentityProbe)),
        originalState,
      ),
      isTrue,
    );
    expect(find.text('new'), findsOneWidget);
    expect(
      tester.getCenter(find.byType(_IdentityProbe)),
      const Offset(120, 130),
    );
  });

  testWidgets('position-only notifications rebuild and relayout symbols', (
    tester,
  ) async {
    final relayout = ValueNotifier<int>(0);
    final data = symbolLabel('stable', 16, crossTileId: 11);
    var symbols = [
      MapSymbol(
        key: 'places:11',
        data: data,
        textPos: const Offset(40, 50),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
    ];
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: symbols,
          symbolsProvider: () => symbols,
          relayout: relayout,
          screenSize: const Size(300, 300),
          onFadedOut: (_) {},
          textBuilder: (_, _) {
            builds++;

            return const Text('stable');
          },
        ),
      ),
    );
    expect(builds, 1);
    expect(tester.getCenter(find.text('stable')), const Offset(40, 50));

    symbols = [
      MapSymbol(
        key: 'places:11',
        data: data,
        textPos: const Offset(140, 150),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
    ];
    relayout.value++;
    await tester.pump();

    expect(builds, 2);
    expect(tester.getCenter(find.text('stable')), const Offset(140, 150));
    relayout.dispose();
  });

  testWidgets('default position updates repaint without overlay layout', (
    tester,
  ) async {
    final relayout = ValueNotifier<int>(0);
    final data = symbolLabel('layout only', 16, crossTileId: 12);
    var symbols = [
      MapSymbol(
        key: 'places:12',
        data: data,
        textPos: const Offset(40, 50),
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
          symbolsProvider: () => symbols,
          relayout: relayout,
          screenSize: const Size(300, 300),
          onFadedOut: (_) {},
        ),
      ),
    );
    final originalTextElement = tester.element(find.text('layout only'));
    final textBoundary = tester.renderObject<RenderRepaintBoundary>(
      find.descendant(
        of: find.byType(MapSymbolOverlay),
        matching: find.byType(RepaintBoundary),
      ),
    );
    final symbolBatch = textBoundary.parent!;
    expect(symbolBatch.runtimeType.toString(), '_RenderSymbolBatch');
    textBoundary.debugResetMetrics();

    symbols = [
      MapSymbol(
        key: 'places:12',
        data: data,
        textPos: const Offset(140, 150),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
    ];
    relayout.value++;
    expect(symbolBatch.debugNeedsLayout, isFalse);
    expect(symbolBatch.debugNeedsPaint, isTrue);
    await tester.pump();

    expect(
      identical(tester.element(find.text('layout only')), originalTextElement),
      isTrue,
    );
    expect(tester.getCenter(find.text('layout only')), const Offset(140, 150));
    expect(textBoundary.debugAsymmetricPaintCount, greaterThan(0));
    expect(textBoundary.debugSymmetricPaintCount, 0);
    relayout.dispose();
  });

  testWidgets('live default positions avoid symbol materialization', (
    tester,
  ) async {
    final relayout = ValueNotifier<int>(0);
    final symbol = MapSymbol(
      key: 'places:live',
      data: symbolLabel('live', 16),
      textPos: const Offset(40, 50),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );
    final positions = _CountingSymbolPositionList([symbol])
      ..textPosition = symbol.textPos!;

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [symbol],
          symbolsProvider: () => positions,
          relayout: relayout,
          screenSize: const Size(300, 300),
          onFadedOut: (_) {},
        ),
      ),
    );
    final originalTextElement = tester.element(find.text('live'));
    positions
      ..indexedReads = 0
      ..positionedReads = 0
      ..anchorReads = 0;

    for (var index = 1; index <= 100; index++) {
      positions.textPosition = Offset(40 + index.toDouble(), 50);
      relayout.value++;
    }
    await tester.pump();

    expect(positions.indexedReads, 0);
    expect(positions.positionedReads, 0);
    expect(positions.anchorReads, greaterThan(0));
    expect(
      identical(tester.element(find.text('live')), originalTextElement),
      isTrue,
    );
    expect(tester.getCenter(find.text('live')), const Offset(140, 50));
    relayout.dispose();
  });

  testWidgets('moving a symbol reuses its unchanged default text widget', (
    tester,
  ) async {
    final data = symbolLabel('cached', 16, crossTileId: 9);
    Future<void> pump(LabelData nextData, Offset position) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [
            MapSymbol(
              key: 'places:9',
              data: nextData,
              textPos: position,
              iconPos: null,
              icon: null,
              visible: true,
              fadeIn: false,
            ),
          ],
          screenSize: const Size(300, 300),
          onFadedOut: (_) {},
        ),
      ),
    );

    await pump(data, const Offset(20, 30));
    final originalText = tester.widget<Text>(find.text('cached'));

    await pump(
      symbolLabel('cached', 16, crossTileId: 9),
      const Offset(120, 130),
    );
    expect(
      identical(tester.widget<Text>(find.text('cached')), originalText),
      isTrue,
    );

    await pump(
      symbolLabel('cached', 18, crossTileId: 9),
      const Offset(120, 130),
    );
    final resizedText = tester.widget<Text>(find.text('cached'));
    expect(identical(resizedText, originalText), isFalse);
    expect(resizedText.style!.fontSize, 18);

    await pump(
      symbolLabel('updated', 16, crossTileId: 9),
      const Offset(120, 130),
    );
    expect(find.text('cached'), findsNothing);
    expect(find.text('updated'), findsOneWidget);
  });

  testWidgets('a custom builder still observes position-only updates', (
    tester,
  ) async {
    final data = symbolLabel('custom', 16, crossTileId: 10);
    Future<void> pump(double x) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [
            MapSymbol(
              key: 'places:10',
              data: data,
              textPos: Offset(x, 50),
              iconPos: null,
              icon: null,
              visible: true,
              fadeIn: false,
            ),
          ],
          screenSize: const Size(300, 300),
          onFadedOut: (_) {},
          textBuilder: (_, symbol) => Text('${symbol.textPos!.dx}'),
        ),
      ),
    );

    await pump(20);
    expect(find.text('20.0'), findsOneWidget);
    await pump(120);
    expect(find.text('20.0'), findsNothing);
    expect(find.text('120.0'), findsOneWidget);
  });
}
