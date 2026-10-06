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
      final layout = tester.renderObject<RenderBox>(_pathLayout);
      final glyph = tester.renderObject<RenderParagraph>(find.text('B'));
      final originalCenter = tester.getCenter(find.text('B'));
      final originalSemantics = _globalSemanticsRect(
        tester.getSemantics(find.text('B')),
      );

      await tester.pumpWidget(_pathLabel(bend: -10), phase: EnginePhase.build);

      expect(tester.renderObject(_pathLayout), same(layout));
      expect(layout.debugNeedsLayout, isFalse);
      expect(layout.debugNeedsPaint, isTrue);
      tester.binding.scheduleFrame();
      await tester.pump();

      final center = tester.getCenter(find.text('B'));
      expect(center, originalCenter + const Offset(0, -20));
      expect(
        tester
            .hitTestOnBinding(center)
            .path
            .any((entry) => entry.target == glyph),
        isTrue,
      );
      expect(
        tester
            .hitTestOnBinding(originalCenter)
            .path
            .any((entry) => entry.target == glyph),
        isFalse,
      );
      final updatedSemantics = _globalSemanticsRect(
        tester.getSemantics(find.text('B')),
      );
      expect(
        updatedSemantics,
        originalSemantics.shift(
          const Offset(0, -20) * tester.view.devicePixelRatio,
        ),
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
    final layout = tester.renderObject<RenderBox>(_pathLayout);

    await tester.pumpWidget(_pathLabel(bend: 10), phase: EnginePhase.build);

    expect(layout.debugNeedsLayout, isFalse);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed glyph sizes and counts still request layout', (
    tester,
  ) async {
    await tester.pumpWidget(_pathLabel(bend: 10));
    final layout = tester.renderObject<RenderBox>(_pathLayout);
    final originalGlyphSize = tester.getSize(find.text('B'));

    await tester.pumpWidget(
      _pathLabel(bend: 10, fontSize: 24),
      phase: EnginePhase.build,
    );

    expect(layout.debugNeedsLayout, isTrue);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(
      tester.getSize(find.text('B')).height,
      greaterThan(originalGlyphSize.height),
    );

    await tester.pumpWidget(
      _pathLabel(bend: 10, fontSize: 24, text: 'B'),
      phase: EnginePhase.build,
    );

    expect(layout.debugNeedsLayout, isTrue);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(find.text('A'), findsNothing);
    expect(find.text('C'), findsNothing);
    expect(
      tester.getCenter(find.text('B')),
      layout.localToGlobal(layout.size.center(Offset.zero)) +
          const Offset(0, 10),
    );
    expect(tester.takeException(), isNull);
  });
}

final _pathLayout = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_PathGlyphLayout',
);

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
