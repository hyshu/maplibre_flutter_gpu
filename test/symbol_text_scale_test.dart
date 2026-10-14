import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';

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

Finder _fillText(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is Text && widget.data == text && widget.style?.foreground == null,
);

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

  testWidgets('a size change inside a bucket reuses the shaped text', (
    tester,
  ) async {
    final (first, second) = _sameBucketSizes();
    final shaped = DefaultTextScale.snapFontSize(first, _key);

    await tester.pumpWidget(_overlay(_symbol(first)));
    final text = tester.widget<Text>(_fillText('Scaled'));
    expect(text.style?.fontSize, shaped);
    final transform = tester.widget<Transform>(find.byType(Transform));
    expect(transform.transform.storage[0], closeTo(first / shaped, 1e-9));

    await tester.pumpWidget(_overlay(_symbol(second)));
    expect(identical(tester.widget<Text>(_fillText('Scaled')), text), isTrue);
    expect(
      tester.widget<Transform>(find.byType(Transform)).transform.storage[0],
      closeTo(second / shaped, 1e-9),
    );
    expect(tester.widgetList<Text>(find.byType(Text)), hasLength(2));
  });

  testWidgets('a grid-aligned size shapes exactly without a transform', (
    tester,
  ) async {
    await tester.pumpWidget(_overlay(_symbol(20)));

    expect(tester.widget<Text>(_fillText('Scaled')).style?.fontSize, 20);
    expect(find.byType(Transform), findsNothing);
  });
}
