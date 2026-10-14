import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';

import 'support/symbol_fixtures.dart';

void main() {
  testWidgets('path offsets repaint and move hit tests and semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_pathLabel(bend: 10));
      final run = _run(tester);
      final originalCenter = _glyphCenter(run, 'B');
      // The label is a single node; its glyphs add none of their own.
      expect(find.bySemanticsLabel('ABC'), findsOneWidget);
      expect(find.bySemanticsLabel('B'), findsNothing);
      final originalSemantics = _globalSemanticsRect(
        tester.getSemantics(find.bySemanticsLabel('ABC')),
      );
      expect(
        originalSemantics.contains(
          originalCenter * tester.view.devicePixelRatio,
        ),
        isTrue,
      );

      await tester.pumpWidget(_pathLabel(bend: -10), phase: EnginePhase.build);

      expect(_run(tester), same(run));
      expect(run.debugNeedsLayout, isFalse);
      expect(run.debugNeedsPaint, isTrue);
      tester.binding.scheduleFrame();
      await tester.pump();

      final center = _glyphCenter(run, 'B');
      expect(center, originalCenter + const Offset(0, -20));
      expect(
        tester
            .hitTestOnBinding(center)
            .path
            .any((entry) => entry.target == run),
        isTrue,
      );
      expect(
        tester
            .hitTestOnBinding(originalCenter)
            .path
            .any((entry) => entry.target == run),
        isFalse,
      );
      final updatedSemantics = _globalSemanticsRect(
        tester.getSemantics(find.bySemanticsLabel('ABC')),
      );
      expect(
        updatedSemantics.contains(center * tester.view.devicePixelRatio),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('equivalent path geometry does not request layout', (
    tester,
  ) async {
    await tester.pumpWidget(_pathLabel(bend: 10));
    final run = _run(tester);

    await tester.pumpWidget(_pathLabel(bend: 10), phase: EnginePhase.build);

    expect(run.debugNeedsLayout, isFalse);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed glyph sizes and counts still request layout', (
    tester,
  ) async {
    await tester.pumpWidget(_pathLabel(bend: 10));
    final run = _run(tester);
    final originalGlyphHeight = _glyph(run, 'B').size.height;

    await tester.pumpWidget(
      _pathLabel(bend: 10, fontSize: 24),
      phase: EnginePhase.build,
    );

    expect(run.debugNeedsLayout, isTrue);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(_glyph(run, 'B').size.height, greaterThan(originalGlyphHeight));

    await tester.pumpWidget(
      _pathLabel(bend: 10, fontSize: 24, text: 'B'),
      phase: EnginePhase.build,
    );

    expect(run.debugNeedsLayout, isTrue);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(run.glyphs.map((glyph) => glyph.text), ['B']);
    expect(
      _glyphCenter(run, 'B'),
      run.localToGlobal(run.size.center(Offset.zero)) + const Offset(0, 10),
    );
    expect(tester.takeException(), isNull);
  });
}

RenderSymbolGlyphRun _run(WidgetTester tester) =>
    tester.renderObject<RenderSymbolGlyphRun>(find.byType(SymbolGlyphRun));

SymbolGlyph _glyph(RenderSymbolGlyphRun run, String text) =>
    run.glyphs.singleWhere((glyph) => glyph.text == text);

Offset _glyphCenter(RenderSymbolGlyphRun run, String text) =>
    run.localToGlobal(_glyph(run, text).center);

Widget _pathLabel({
  required double bend,
  double fontSize = 20,
  String text = 'ABC',
}) {
  final symbol = MapSymbol(
    key: 'path',
    data: symbolLabel(
      text,
      fontSize,
      alongLine: true,
      textPath: [
        const LabelPathPoint(-100, -20),
        const LabelPathPoint(-50, -20),
        LabelPathPoint(-40, bend),
        LabelPathPoint(40, bend),
        const LabelPathPoint(50, -20),
        const LabelPathPoint(100, -20),
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
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Builder(
          builder: (context) => buildDefaultSymbolText(context, symbol)!,
        ),
      ),
    ),
  );
}

Rect _globalSemanticsRect(SemanticsNode node) {
  var rect = node.rect;
  SemanticsNode? current = node;
  while (current != null) {
    final transform = current.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
    current = current.parent;
  }

  return rect;
}
