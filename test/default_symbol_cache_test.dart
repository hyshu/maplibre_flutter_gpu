import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';

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

Finder _fillText(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is Text && widget.data == text && widget.style?.foreground == null,
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
    final before = tester.widgetList<Text>(find.byType(Text)).toList();
    final firstCenter = tester.getCenter(_fillText('A'));
    expect(before, hasLength(6));

    await pump(const [LabelPathPoint(-100, -40), LabelPathPoint(100, 40)]);
    final after = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(after, hasLength(before.length));
    for (var index = 0; index < before.length; index++) {
      expect(identical(before[index], after[index]), isTrue);
    }
    expect(tester.getCenter(_fillText('A')), isNot(firstCenter));
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
    final before = tester.widgetList<Text>(find.text('Point label')).toList();
    final firstCenter = tester.getCenter(_fillText('Point label'));
    final firstSize = tester.getRect(_fillText('Point label')).size;

    await pump(1.3, 30, 0.4);
    final after = tester.widgetList<Text>(find.text('Point label')).toList();
    expect(after, hasLength(2));
    for (var index = 0; index < before.length; index++) {
      expect(identical(before[index], after[index]), isTrue);
    }
    expect(
      tester.getCenter(_fillText('Point label')) - firstCenter,
      const Offset(20, 0),
    );
    expect(
      tester.getRect(_fillText('Point label')).width,
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
        RenderParagraph paragraph() => tester.renderObject<RenderParagraph>(
          find.descendant(of: _fillText('Q'), matching: find.byType(RichText)),
        );

        await pump(1, 2);
        final text = tester.widget<Text>(_fillText('Q'));
        expect(paragraph().textScaler.scale(20), 20);
        expect((paragraph().text as TextSpan).style!.wordSpacing, 2);

        await pump(1.5, 4);
        expect(identical(tester.widget<Text>(_fillText('Q')), text), isTrue);
        expect(paragraph().textScaler.scale(20), 30);
        expect((paragraph().text as TextSpan).style!.wordSpacing, 4);
        expect(tester.takeException(), isNull);
      },
    );
  }

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
    Paint haloPaint() => tester
        .widgetList<Text>(find.text('Halo label'))
        .map((text) => text.style!.foreground)
        .whereType<Paint>()
        .single;

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
    expect(find.text('Updated'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wrapped-label')));
    expect(tapped.last.data.text, 'Updated');

    current = _symbol(symbolLabel('Hidden', 20));
    await pump();
    expect(find.byKey(const ValueKey('wrapped-label')), findsNothing);
    expect(find.text('Hidden'), findsNothing);
  });
}
