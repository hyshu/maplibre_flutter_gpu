import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';

import 'support/symbol_finders.dart';
import 'support/symbol_fixtures.dart';

const _key = 'scaled-label';

MapSymbol _symbol(double fontSize, {double haloWidth = 1, double textW = 0}) =>
    MapSymbol(
      key: _key,
      data: symbolLabel(
        'Scaled',
        fontSize,
        haloWidth: haloWidth,
        haloA: haloWidth > 0 ? 1 : 0,
        textW: textW,
      ),
      textPos: const Offset(150, 150),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

Widget _overlay(MapSymbol symbol) => MaterialApp(
  home: MapSymbolOverlay(
    symbols: [symbol],
    screenSize: const Size(400, 400),
    fadeDuration: Duration.zero,
    onFadedOut: (_) {},
  ),
);

/// The horizontal scale the overlay applies to the label.
double _pointScale(WidgetTester tester) =>
    tester.widget<Transform>(find.byType(Transform)).transform.storage[0];

/// Two sizes between grid lines that share one shaped size for [_key].
(double, double) _sameBucketSizes() {
  final first = 13.1;
  final snapped = DefaultTextScale.snapFontSize(first, _key);
  for (final second in [13.11, 13.09, 13.12, 13.08]) {
    if (DefaultTextScale.snapFontSize(second, _key) == snapped) {
      return (first, second);
    }
  }
  throw StateError('no neighbouring size shares the bucket');
}

void main() {
  test('integer and grid-aligned sizes shape exactly', () {
    for (final size in [4.0, 12.0, 13.0, 13.25, 16.0, 23.0, 64.0, 100.0]) {
      expect(DefaultTextScale.snapFontSize(size, _key), size);
      expect(DefaultTextScale.snapFontSize(size, 'other'), size);
    }
  });

  test(
    'sizes between grid lines stay within two percent of the shaped size',
    () {
      for (var size = 6.0; size < 80; size += 0.173) {
        for (final key in [_key, 'another', 'third']) {
          final snapped = DefaultTextScale.snapFontSize(size, key);
          expect((size / snapped - 1).abs(), lessThan(0.02), reason: '$size');
        }
      }
    },
  );

  test('symbols cross grid lines in different frames', () {
    // With a shared grid every label would re-shape at the same size.
    final boundaries = <String, double>{};
    for (final key in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) {
      var previous = DefaultTextScale.snapFontSize(13.01, key);
      for (var size = 13.01; size < 13.3; size += 0.001) {
        final snapped = DefaultTextScale.snapFontSize(size, key);
        if (snapped != previous) {
          boundaries[key] = size;
          break;
        }
        previous = snapped;
      }
    }
    expect(boundaries.values.toSet().length, greaterThan(1));
  });

  test('halo and collision widths are quantized in shaped units', () {
    final (first, second) = _sameBucketSizes();
    final a = DefaultTextScale.of(
      symbolLabel('x', first, haloWidth: 1, textW: 80),
      _key,
    );
    final b = DefaultTextScale.of(
      symbolLabel('x', second, haloWidth: 1, textW: 80 * second / first),
      _key,
    );
    expect(a.shapesLike(b), isTrue);
    expect(a.haloWidth, 1);
    expect(a.ratio, isNot(b.ratio));
  });

  test('a spent re-shape budget keeps the previous shaped size', () {
    final budget = DefaultTextReshapeBudget(1);
    final resting = DefaultTextScale.of(symbolLabel('x', 13), _key);
    final first = DefaultTextScale.of(
      symbolLabel('x', 14),
      _key,
      previous: resting,
      budget: budget,
    );
    final second = DefaultTextScale.of(
      symbolLabel('x', 15),
      'other',
      previous: resting,
      budget: budget,
    );
    final unchanged = DefaultTextScale.of(
      symbolLabel('x', 13),
      'third',
      previous: resting,
      budget: budget,
    );

    expect(first.fontSize, 14);
    expect(second.fontSize, 13);
    expect(second.ratio, closeTo(15 / 13, 1e-9));
    expect(unchanged.fontSize, 13);
    expect(budget.deferred, 1);
  });

  testWidgets('deferred re-shapes follow in later builds', (tester) async {
    Widget overlay(double fontSize) => MaterialApp(
      home: MapSymbolOverlay(
        symbols: [
          for (var index = 0; index < 40; index++)
            MapSymbol(
              key: 'label-$index',
              data: symbolLabel('L$index', fontSize),
              textPos: Offset(20 + index * 9.0, 200),
              iconPos: null,
              icon: null,
              visible: true,
              fadeIn: false,
            ),
        ],
        screenSize: const Size(400, 400),
        fadeDuration: Duration.zero,
        onFadedOut: (_) {},
      ),
    );
    int shapedAt(double fontSize) => tester
        .widgetList<SymbolTextBlock>(find.byType(SymbolTextBlock))
        .where((block) => (block.span as TextSpan).style!.fontSize == fontSize)
        .length;

    await tester.pumpWidget(overlay(13));
    expect(shapedAt(13), 40);

    // Every label crosses the grid, but only a budget of them re-shapes.
    await tester.pumpWidget(overlay(14.5));
    expect(shapedAt(14.5), 32);
    expect(shapedAt(13), 8);

    // The overlay schedules the remaining labels itself once no build came.
    await tester.pump(const Duration(milliseconds: 20));
    expect(shapedAt(14.5), 32);
    await tester.pump(const Duration(milliseconds: 10));
    expect(shapedAt(14.5), 40);

    // Settling to the exact size is spread the same way.
    await tester.pumpWidget(overlay(14.6));
    await tester.pump(const Duration(milliseconds: 150));
    expect(shapedAt(14.6), lessThan(40));
    await tester.pump(const Duration(milliseconds: 30));
    expect(shapedAt(14.6), 40);
  });

  testWidgets('a settled label keeps its exact text when a zoom begins', (
    tester,
  ) async {
    await tester.pumpWidget(_overlay(_symbol(13.1)));
    expect(symbolTextStyle(tester, 'Scaled')?.fontSize, 13.1);
    expect(_pointScale(tester), 1);
    final render = symbolTextRender(tester, 'Scaled');
    final painter = render.debugFillPainter;

    await tester.pumpWidget(_overlay(_symbol(13.11)));
    expect(symbolTextRender(tester, 'Scaled'), same(render));
    expect(identical(render.debugFillPainter, painter), isTrue);
    expect(symbolTextStyle(tester, 'Scaled')?.fontSize, 13.1);
    expect(_pointScale(tester), closeTo(13.11 / 13.1, 1e-9));
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('a zoom past the tolerance snaps the shaped size to the grid', (
    tester,
  ) async {
    await tester.pumpWidget(_overlay(_symbol(13.1)));
    await tester.pumpWidget(_overlay(_symbol(13.6)));

    final shaped = DefaultTextScale.snapFontSize(13.6, _key);
    expect(shaped, isNot(13.6));
    expect(symbolTextStyle(tester, 'Scaled')?.fontSize, shaped);
    expect(_pointScale(tester), closeTo(13.6 / shaped, 1e-9));
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('labels shape exactly once their sizes settle', (tester) async {
    await tester.pumpWidget(_overlay(_symbol(13.1)));
    await tester.pumpWidget(_overlay(_symbol(13.6)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(symbolTextStyle(tester, 'Scaled')?.fontSize, isNot(13.6));

    // Each size change restarts the settle delay.
    await tester.pumpWidget(_overlay(_symbol(13.7)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(symbolTextStyle(tester, 'Scaled')?.fontSize, isNot(13.7));

    await tester.pump(const Duration(milliseconds: 50));
    expect(symbolTextStyle(tester, 'Scaled')?.fontSize, 13.7);
    expect(_pointScale(tester), 1);
  });

  testWidgets('culled labels do not unsettle the labels on screen', (
    tester,
  ) async {
    Widget overlay(double fontSize, {required bool secondVisible}) =>
        MaterialApp(
          home: MapSymbolOverlay(
            symbols: [
              MapSymbol(
                key: 'first',
                data: symbolLabel('First', fontSize),
                textPos: const Offset(100, 100),
                iconPos: null,
                icon: null,
                visible: true,
                fadeIn: false,
              ),
              MapSymbol(
                key: 'second',
                data: symbolLabel('Second', fontSize),
                textPos: secondVisible
                    ? const Offset(200, 100)
                    : const Offset(-500, 100),
                iconPos: null,
                icon: null,
                visible: true,
                fadeIn: false,
              ),
            ],
            screenSize: const Size(400, 400),
            fadeDuration: Duration.zero,
            onFadedOut: (_) {},
          ),
        );

    await tester.pumpWidget(overlay(13, secondVisible: true));
    await tester.pumpWidget(overlay(14.1, secondVisible: false));
    await tester.pump(const Duration(milliseconds: 150));
    expect(symbolTextStyle(tester, 'First')?.fontSize, 14.1);

    // The second label comes back with a stale cache entry at size 13.
    await tester.pumpWidget(overlay(14.1, secondVisible: true));
    expect(symbolTextStyle(tester, 'First')?.fontSize, 14.1);
    expect(symbolTextStyle(tester, 'Second')?.fontSize, 14.1);
  });

  testWidgets('a grid-aligned size shapes exactly without scaling', (
    tester,
  ) async {
    await tester.pumpWidget(_overlay(_symbol(20)));

    expect(symbolTextStyle(tester, 'Scaled')?.fontSize, 20);
    expect(_pointScale(tester), 1);
  });
}
