import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/symbol_profile_counters.dart';

import 'support/symbol_finders.dart';
import 'support/symbol_fixtures.dart';

MapSymbol _symbol(LabelData data, {Offset position = const Offset(150, 150)}) =>
    MapSymbol(
      key: 'cached-label',
      data: data,
      textPos: position,
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

Widget _overlay(MapSymbol symbol) => MapSymbolOverlay(
  symbols: [symbol],
  screenSize: const Size(400, 400),
  fadeDuration: Duration.zero,
  onFadedOut: (_) {},
);

void main() {
  testWidgets('moving a curved label retains glyphs and updates geometry', (
    tester,
  ) async {
    Future<void> pump(List<LabelPathPoint> path) => tester.pumpWidget(
      MaterialApp(
        home: _overlay(
          _symbol(
            symbolLabel(
              'ABC',
              20,
              alongLine: true,
              haloWidth: 1,
              haloA: 1,
              textPath: path,
            ),
          ),
        ),
      ),
    );

    await pump(const [LabelPathPoint(-100, 0), LabelPathPoint(100, 0)]);
    final run = tester.renderObject<RenderSymbolGlyphRun>(
      find.byType(SymbolGlyphRun),
    );
    final before = run.debugFillPainters;
    final firstCenter = run.localToGlobal(run.glyphs.first.center);
    expect(before, hasLength(3));
    expect(find.byType(Text), findsNothing);

    await pump(const [LabelPathPoint(-100, -40), LabelPathPoint(100, 40)]);
    expect(tester.renderObject(find.byType(SymbolGlyphRun)), same(run));
    final after = run.debugFillPainters;
    expect(after, hasLength(before.length));
    for (var index = 0; index < before.length; index++) {
      expect(identical(before[index], after[index]), isTrue);
    }
    expect(run.localToGlobal(run.glyphs.first.center), isNot(firstCenter));
    expect(tester.takeException(), isNull);
  });

  testWidgets('point transformations retain unchanged text content', (
    tester,
  ) async {
    Future<void> pump(double scale, double x, double opacity) =>
        tester.pumpWidget(
          MaterialApp(
            home: _overlay(
              _symbol(
                symbolLabel(
                  'Point label',
                  20,
                  haloWidth: 1,
                  haloA: 1,
                  textOpacity: opacity,
                  textTranslateX: x,
                  textTransform: LabelAffineTransform(xx: scale, yy: scale),
                ),
              ),
            ),
          ),
        );

    await pump(1.1, 10, 0.8);
    final before = symbolTextBlockOf(tester, 'Point label');
    final render = symbolTextRender(tester, 'Point label');
    final firstCenter = tester.getCenter(symbolTextBlock('Point label'));
    final firstSize = tester.getRect(symbolTextBlock('Point label')).size;

    await pump(1.3, 30, 0.4);
    expect(identical(symbolTextBlockOf(tester, 'Point label'), before), isTrue);
    expect(symbolTextRender(tester, 'Point label'), same(render));
    expect(
      tester.getCenter(symbolTextBlock('Point label')) - firstCenter,
      const Offset(20, 0),
    );
    expect(
      tester.getRect(symbolTextBlock('Point label')).width,
      greaterThan(firstSize.width),
    );
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.4);
  });

  for (final alongLine in [false, true]) {
    testWidgets(
      '${alongLine ? 'glyph' : 'point'} cache respects inherited text changes',
      (tester) async {
        final symbol = _symbol(
          symbolLabel(
            'Q',
            20,
            alongLine: alongLine,
            haloWidth: 1,
            haloA: 1,
            textPath: alongLine
                ? const [LabelPathPoint(-80, 0), LabelPathPoint(80, 0)]
                : const [],
          ),
        );
        final overlay = _overlay(symbol);
        Future<void> pump(double scale, double wordSpacing) =>
            tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: DefaultTextStyle(
                    style: TextStyle(wordSpacing: wordSpacing),
                    child: overlay,
                  ),
                ),
              ),
            );
        // Along-line glyphs paint from shared painters that resolve the same
        // inherited settings a Text widget would.
        ({TextScaler scaler, double? wordSpacing}) resolved() {
          if (alongLine) {
            final painter = tester
                .renderObject<RenderSymbolGlyphRun>(find.byType(SymbolGlyphRun))
                .debugFillPainters
                .single!;

            return (
              scaler: painter.textScaler,
              wordSpacing: (painter.text! as TextSpan).style!.wordSpacing,
            );
          }
          final painter = symbolTextRender(tester, 'Q').debugFillPainter;

          return (
            scaler: painter.textScaler,
            wordSpacing: (painter.text! as TextSpan).style!.wordSpacing,
          );
        }

        Widget content() => alongLine
            ? tester.widget<SymbolGlyphRun>(find.byType(SymbolGlyphRun))
            : symbolTextBlockOf(tester, 'Q');

        await pump(1, 2);
        final text = content();
        expect(resolved().scaler.scale(20), 20);
        expect(resolved().wordSpacing, 2);

        await pump(1.5, 4);
        expect(identical(content(), text), isTrue);
        expect(resolved().scaler.scale(20), 30);
        expect(resolved().wordSpacing, 4);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('point text ignores line path and angle changes', (tester) async {
    Future<void> pump(List<LabelPathPoint> path, double angle) =>
        tester.pumpWidget(
          MaterialApp(
            home: _overlay(
              _symbol(symbolLabel('Point', 20, textPath: path, angle: angle)),
            ),
          ),
        );

    await pump(const [], 0);
    final before = symbolTextBlockOf(tester, 'Point');
    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    SymbolProfileCounters.reset();

    await pump(const [LabelPathPoint(-10, 0), LabelPathPoint(10, 0)], 0.3);
    expect(identical(symbolTextBlockOf(tester, 'Point'), before), isTrue);
    expect(
      tester.widgetList<Transform>(find.byType(Transform)).length,
      transforms.length,
    );
    expect(
      SymbolProfileCounters.snapshot()[SymbolProfileCounters.textVisualMisses],
      isNull,
    );
  });

  testWidgets('default labels expose one semantics node per label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final symbol = _symbol(
      symbolLabel(
        'Harbor \u{E000} Road',
        20,
        haloWidth: 1,
        haloA: 1,
        textSections: const [
          LabelTextSection(start: 7, end: 8, imageId: 'pin'),
        ],
      ),
    );

    await tester.pumpWidget(MaterialApp(home: _overlay(symbol)));

    expect(find.bySemanticsLabel('Harbor  Road'), findsOneWidget);
    expect(find.bySemanticsLabel('Harbor \u{E000} Road'), findsNothing);
    final node = tester.getSemantics(find.bySemanticsLabel('Harbor  Road'));
    expect(node.childrenCount, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [symbol],
          screenSize: const Size(400, 400),
          fadeDuration: Duration.zero,
          onFadedOut: (_) {},
          semanticsMode: SymbolSemanticsMode.none,
        ),
      ),
    );

    expect(find.bySemanticsLabel('Harbor  Road'), findsNothing);
    expect(find.textContaining('Road'), findsWidgets);
    semantics.dispose();
  });

  testWidgets('profile counters attribute visual misses to transforms', (
    tester,
  ) async {
    Future<void> pump(String text, double xx) => tester.pumpWidget(
      MaterialApp(
        home: _overlay(
          _symbol(
            symbolLabel(
              text,
              20,
              textTransform: LabelAffineTransform(xx: xx, yy: xx),
            ),
          ),
        ),
      ),
    );

    await pump('Counted', 1);
    SymbolProfileCounters.reset();
    await pump('Counted', 1);
    expect(
      SymbolProfileCounters.snapshot()[SymbolProfileCounters.textVisualMisses],
      isNull,
    );

    await pump('Counted', 1.00002);
    var counters = SymbolProfileCounters.snapshot();
    expect(counters[SymbolProfileCounters.textVisualMisses], 1);
    expect(counters[SymbolProfileCounters.transformOnlyMisses], 1);

    await pump('Changed', 1.00002);
    counters = SymbolProfileCounters.snapshot();
    expect(counters[SymbolProfileCounters.textVisualMisses], 2);
    expect(counters[SymbolProfileCounters.transformOnlyMisses], 1);
    expect(counters[SymbolProfileCounters.overlayBuilds], 3);
    SymbolProfileCounters.reset();
  });

  testWidgets('changing halo style does not mutate an earlier halo paint', (
    tester,
  ) async {
    Future<void> pump(double width, double red, double blur) =>
        tester.pumpWidget(
          MaterialApp(
            home: _overlay(
              _symbol(
                symbolLabel(
                  'Halo label',
                  20,
                  haloWidth: width,
                  haloR: red,
                  haloA: 1,
                  haloBlur: blur,
                ),
              ),
            ),
          ),
        );
    Paint haloPaint() {
      final painter = symbolTextRender(tester, 'Halo label').debugHaloPainter!;

      return (painter.text! as TextSpan).style!.foreground!;
    }

    await pump(1, 0, 0);
    final original = haloPaint();
    expect(original.strokeWidth, 2);
    expect(original.color, const Color(0xFF000000));
    expect(original.maskFilter, isNull);

    await pump(3, 1, 2);
    final updated = haloPaint();
    expect(updated.strokeWidth, 6);
    expect(updated.color, const Color(0xFFFF0000));
    expect(updated.maskFilter, isNotNull);
    expect(original.strokeWidth, 2);
    expect(original.color, const Color(0xFF000000));
    expect(original.maskFilter, isNull);
  });

  testWidgets('a wrapped default builder keeps current positions and taps', (
    tester,
  ) async {
    final relayout = ValueNotifier<int>(0);
    addTearDown(relayout.dispose);
    final seen = <MapSymbol>[];
    final tapped = <MapSymbol>[];
    final data = symbolLabel('Wrapped', 20, haloWidth: 1, haloA: 1);
    var current = _symbol(data, position: const Offset(80, 90));
    Widget? builder(BuildContext context, MapSymbol symbol) {
      seen.add(symbol);
      if (symbol.data.text == 'Hidden') return null;

      return GestureDetector(
        key: const ValueKey('wrapped-label'),
        behavior: HitTestBehavior.opaque,
        onTap: () => tapped.add(symbol),
        child: buildDefaultSymbolText(context, symbol),
      );
    }

    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [current],
          symbolsProvider: () => [current],
          relayout: relayout,
          textBuilder: builder,
          screenSize: const Size(400, 400),
          fadeDuration: Duration.zero,
          onFadedOut: (_) {},
        ),
      ),
    );

    await pump();
    expect(seen.last.textPos, const Offset(80, 90));
    current = _symbol(data, position: const Offset(180, 190));
    relayout.value++;
    await tester.pump();
    expect(seen, hasLength(2));
    expect(seen.last.textPos, const Offset(180, 190));
    await tester.tap(find.byKey(const ValueKey('wrapped-label')));
    expect(tapped.single.textPos, const Offset(180, 190));

    current = _symbol(
      symbolLabel('Updated', 24),
      position: const Offset(200, 210),
    );
    await pump();
    expect(seen.last.data.text, 'Updated');
    expect(seen.last.textPos, const Offset(200, 210));
    expect(symbolTextBlock('Updated'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wrapped-label')));
    expect(tapped.last.data.text, 'Updated');

    current = _symbol(symbolLabel('Hidden', 20));
    await pump();
    expect(find.byKey(const ValueKey('wrapped-label')), findsNothing);
    expect(symbolTextBlock('Hidden'), findsNothing);
  });
}
