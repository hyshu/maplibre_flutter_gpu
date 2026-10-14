import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';

import 'support/symbol_fixtures.dart';

const _boundaryKey = ValueKey('block-boundary');
const _text = 'ABC\nDEFGH';
const _width = 120.0;

MapSymbol _symbol({
  String text = _text,
  LabelTextJustify justify = .center,
  LabelAffineTransform transform = const LabelAffineTransform(),
  double width = _width,
  bool alongLine = false,
  double angle = 0,
}) => MapSymbol(
  key: 'point',
  data: symbolLabel(
    text,
    20,
    haloWidth: 1,
    haloR: 1,
    haloA: 1,
    textW: width,
    textJustify: justify,
    textTransform: transform,
    alongLine: alongLine,
    angle: angle,
  ),
  textPos: Offset.zero,
  iconPos: null,
  icon: null,
  visible: true,
  fadeIn: false,
);

Widget _harness(Widget child) => MaterialApp(
  home: Center(
    child: RepaintBoundary(
      key: _boundaryKey,
      child: ColoredBox(color: const Color(0xFFE7EDF3), child: child),
    ),
  ),
);

Widget _label(MapSymbol symbol) => _harness(
  Builder(builder: (context) => buildDefaultSymbolText(context, symbol)!),
);

/// A [Text] based tree whose raster the block must reproduce.
Widget _textReference(MapSymbol symbol) {
  final data = symbol.data;
  final style = TextStyle(
    fontSize: 20,
    color: data.textColor,
    letterSpacing: 0,
    height: data.lineHeight,
  );
  final align = switch (data.textJustify) {
    .left => TextAlign.left,
    .right => TextAlign.right,
    .auto || .center => TextAlign.center,
  };
  Text text(TextStyle style) => Text(
    data.text,
    style: style,
    textAlign: align,
    textDirection: data.textDirection,
    softWrap: false,
    overflow: TextOverflow.visible,
  );

  return _harness(
    SizedBox(
      width: _width,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          text(
            style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..strokeJoin = StrokeJoin.round
                ..color = data.haloColor,
            ),
          ),
          text(style),
        ],
      ),
    ),
  );
}

List<RecordedInvocation> _paintCalls(WidgetTester tester) {
  final canvas = TestRecordingCanvas();
  tester
      .renderObject<RenderSymbolTextBlock>(find.byType(SymbolTextBlock))
      .paint(TestRecordingPaintingContext(canvas), Offset.zero);

  return canvas.invocations.toList();
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
    SymbolGlyphAtlas.clear();
  });

  testWidgets('a point label paints as one atlas image', (tester) async {
    await tester.pumpWidget(_label(_symbol()));

    final calls = _paintCalls(tester).map((call) => call.invocation);
    expect(calls.where((call) => call.memberName == #drawImageRect), [
      isA<Invocation>().having(
        (call) => (call.positionalArguments.last as Paint).filterQuality,
        'filterQuality',
        FilterQuality.none,
      ),
    ]);
    expect(
      calls.map((call) => call.memberName),
      isNot(contains(#drawParagraph)),
    );
    expect(SymbolGlyphAtlas.entryCount, 1);
  });

  testWidgets('a scaled label samples its raster bilinearly', (tester) async {
    await tester.pumpWidget(
      _label(_symbol(transform: const LabelAffineTransform(xx: 1.2, yy: 1.2))),
    );

    final draw = _paintCalls(tester)
        .map((call) => call.invocation)
        .singleWhere((call) => call.memberName == #drawImageRect);
    expect(
      (draw.positionalArguments.last as Paint).filterQuality,
      FilterQuality.low,
    );
  });

  testWidgets('a disabled atlas paints the paragraphs directly', (
    tester,
  ) async {
    SymbolGlyphAtlas.enabled = false;
    await tester.pumpWidget(_label(_symbol()));

    final names = _paintCalls(tester).map((call) => call.invocation.memberName);
    expect(names, isNot(contains(#drawImageRect)));
    // The halo and the fill paragraph.
    expect(names.where((name) => name == #drawParagraph), hasLength(2));
  });

  testWidgets('the block spans its box width and its lines', (tester) async {
    await tester.pumpWidget(_label(_symbol()));

    expect(
      tester.getSize(find.byType(SymbolTextBlock)),
      const Size(_width, 48),
    );
    final painter = tester
        .renderObject<RenderSymbolTextBlock>(find.byType(SymbolTextBlock))
        .debugFillPainter;
    expect(painter.width, 100);
    expect(painter.computeLineMetrics(), hasLength(2));
  });

  for (final justify in LabelTextJustify.values) {
    testWidgets('$justify lines land where a Text widget puts them', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      SymbolGlyphAtlas.enabled = false;
      await tester.pumpWidget(_label(_symbol(justify: justify)));
      final block = await _pixels(tester);

      await tester.pumpWidget(_textReference(_symbol(justify: justify)));
      final reference = await _pixels(tester);

      expect(block, reference);
    });
  }

  testWidgets('atlas and direct painting agree on pixels', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_label(_symbol()));
    await tester.pump();
    final atlas = await _pixels(tester);

    SymbolGlyphAtlas.enabled = false;
    await tester.pumpWidget(_label(_symbol()));
    final direct = await _pixels(tester);

    // Both rasters land on the same device pixels, so only the rounding of
    // the premultiplied page texels may differ.
    expect(atlas.length, direct.length);
    var maxDelta = 0;
    for (var index = 0; index < atlas.length; index++) {
      maxDelta = math.max(maxDelta, (atlas[index] - direct[index]).abs());
    }
    expect(maxDelta, lessThanOrEqualTo(2));
  });

  testWidgets('overflowing lines keep their alignment on the box', (
    tester,
  ) async {
    Rect destination() =>
        _paintCalls(tester)
                .map((call) => call.invocation)
                .singleWhere((call) => call.memberName == #drawImageRect)
                .positionalArguments[2]
            as Rect;

    await tester.pumpWidget(_label(_symbol(width: 60)));
    expect(tester.getSize(find.byType(SymbolTextBlock)), const Size(60, 48));
    expect(destination().center.dx, closeTo(30, 1e-6));

    await tester.pumpWidget(_label(_symbol(width: 60, justify: .right)));
    final render = tester.renderObject<RenderSymbolTextBlock>(
      find.byType(SymbolTextBlock),
    );
    final inset = destination().width - render.debugFillPainter.width;
    expect(destination().right - inset / 2, closeTo(60, 1e-6));
  });

  testWidgets('a rotated line label without a path samples bilinearly', (
    tester,
  ) async {
    await tester.pumpWidget(_label(_symbol(alongLine: true, angle: 0.3)));

    expect(
      tester.widget<SymbolTextBlock>(find.byType(SymbolTextBlock)).pixelAligned,
      isFalse,
    );
    expect(find.byType(Transform), findsWidgets);
  });

  testWidgets('inherited text settings resolve where the block is mounted', (
    tester,
  ) async {
    final symbol = _symbol(text: 'Q');
    Future<void> pump(double scale) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            devicePixelRatio: 2,
          ),
          child: Center(
            child: Builder(
              builder: (context) => buildDefaultSymbolText(context, symbol)!,
            ),
          ),
        ),
      ),
    );

    await pump(1);
    final render = tester.renderObject<RenderSymbolTextBlock>(
      find.byType(SymbolTextBlock),
    );
    expect(render.debugFillPainter.textScaler.scale(20), 20);
    final height = tester.getSize(find.byType(SymbolTextBlock)).height;

    await pump(1.5);
    expect(render.debugFillPainter.textScaler.scale(20), 30);
    expect(tester.getSize(find.byType(SymbolTextBlock)).height, height * 1.5);
  });
}
