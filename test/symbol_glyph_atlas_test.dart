import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';

import 'support/symbol_fixtures.dart';

const _boundaryKey = ValueKey('atlas-boundary');

Widget _pathLabel(String text, {String key = 'path', double bend = 0}) {
  final symbol = MapSymbol(
    key: key,
    data: symbolLabel(
      text,
      20,
      haloWidth: 1,
      haloA: 1,
      alongLine: true,
      textPath: [
        const LabelPathPoint(-100, 0),
        LabelPathPoint(0, bend),
        const LabelPathPoint(100, 0),
      ],
    ),
    textPos: Offset.zero,
    iconPos: null,
    icon: null,
    visible: true,
    fadeIn: false,
  );

  return MaterialApp(
    home: Center(
      child: RepaintBoundary(
        key: _boundaryKey,
        child: ColoredBox(
          color: const Color(0xFFE7EDF3),
          child: Builder(
            builder: (context) => buildDefaultSymbolText(context, symbol)!,
          ),
        ),
      ),
    ),
  );
}

List<Symbol> _paintCalls(WidgetTester tester) {
  final canvas = TestRecordingCanvas();
  tester
      .renderObject<RenderSymbolGlyphRun>(find.byType(SymbolGlyphRun))
      .paint(TestRecordingPaintingContext(canvas), Offset.zero);

  return [for (final call in canvas.invocations) call.invocation.memberName];
}

Future<List<int>> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  addTearDown(image.dispose);
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );

  return bytes!.buffer.asUint8List().toList();
}

void main() {
  setUp(() {
    SymbolGlyphAtlas.enabled = true;
    SymbolGlyphAtlas.pageBudget = 12;
    SymbolGlyphAtlas.painterCapacity = 8192;
    SymbolGlyphAtlas.clear();
  });

  testWidgets('painter eviction never leaves an undrawn glyph behind', (
    tester,
  ) async {
    // Painters evicted while their glyph still waits for a page rebuild must
    // not be painted into the page, or the engine throws and the atlas turns
    // itself off.
    SymbolGlyphAtlas.painterCapacity = 4;
    for (final text in ['ABC', 'DEF', 'GHI', 'JKL', 'MNO']) {
      await tester.pumpWidget(_pathLabel(text, key: text));
    }
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(SymbolGlyphAtlas.enabled, isTrue);
  });

  testWidgets('along-line glyphs paint as one atlas batch', (tester) async {
    await tester.pumpWidget(_pathLabel('ABC'));

    final calls = _paintCalls(tester);
    expect(calls.where((name) => name == #drawRawAtlas), hasLength(1));
    expect(calls, isNot(contains(#drawParagraph)));
    expect(SymbolGlyphAtlas.entryCount, 3);
    expect(SymbolGlyphAtlas.pageCount, 1);
  });

  testWidgets('labels share rasterized glyphs', (tester) async {
    await tester.pumpWidget(_pathLabel('ABC'));
    await tester.pumpWidget(_pathLabel('CAB', key: 'other', bend: 20));

    expect(SymbolGlyphAtlas.entryCount, 3);
    expect(SymbolGlyphAtlas.pageCount, 1);
  });

  testWidgets('a disabled atlas paints text directly', (tester) async {
    SymbolGlyphAtlas.enabled = false;
    await tester.pumpWidget(_pathLabel('ABC'));

    final calls = _paintCalls(tester);
    expect(calls, isNot(contains(#drawRawAtlas)));
    // A halo and a fill paragraph per glyph.
    expect(calls.where((name) => name == #drawParagraph), hasLength(6));
    expect(SymbolGlyphAtlas.entryCount, 0);
  });

  testWidgets('atlas and direct painting agree on pixels', (tester) async {
    await tester.pumpWidget(_pathLabel('ABC', bend: 15));
    final atlas = await _pixels(tester);

    SymbolGlyphAtlas.enabled = false;
    await tester.pumpWidget(_pathLabel('ABC', bend: 15, key: 'direct'));
    final direct = await _pixels(tester);

    expect(atlas.length, direct.length);
    var difference = 0;
    var inkDifference = 0;
    for (var index = 0; index < atlas.length; index++) {
      final delta = (atlas[index] - direct[index]).abs();
      difference += delta;
      if (delta > 64) inkDifference++;
    }
    // Rotated glyphs resample an upright raster, so edge coverage shifts by a
    // texel on a small share of pixels; the ink itself does not move.
    expect(difference / atlas.length, lessThan(2));
    expect(inkDifference / atlas.length, lessThan(0.01));
  });

  testWidgets('the page budget bounds live pages', (tester) async {
    SymbolGlyphAtlas.pageBudget = 1;
    final text = String.fromCharCodes([
      for (var code = 0x4E00; code < 0x4E00 + 400; code++) code,
    ]);

    await tester.pumpWidget(_pathLabel(text));
    await tester.pump();

    expect(SymbolGlyphAtlas.pageCount, lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });
}
