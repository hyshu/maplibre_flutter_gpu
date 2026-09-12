import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/path_glyph_layout.dart';

import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';

import 'support/symbol_fixtures.dart';

void main() {
  test('line glyph layout follows path distance and stays upright', () {
    final forward = layoutSymbolGlyphsAlongPath(
      const [Offset(0, 0), Offset(50, 0), Offset(100, 50)],
      const [20, 20, 20],
    );
    final reverse = layoutSymbolGlyphsAlongPath(
      const [Offset(100, 50), Offset(50, 0), Offset(0, 0)],
      const [20, 20, 20],
    );

    expect(forward, hasLength(3));
    expect(forward.first.position.dx, lessThan(forward.last.position.dx));
    expect(forward.every((glyph) => glyph.angle.abs() <= math.pi / 2), isTrue);
    expect(reverse, hasLength(3));
    expect(reverse.first.position.dx, lessThan(reverse.last.position.dx));
    expect(reverse.every((glyph) => glyph.angle.abs() <= math.pi / 2), isTrue);
  });

  test('line glyph layout advances across many path segments', () {
    final placements = layoutSymbolGlyphsAlongPath([
      for (var i = 0; i <= 128; i++) Offset(i.toDouble(), 0),
    ], List<double>.filled(128, 1));

    expect(placements, hasLength(128));
    for (var i = 0; i < placements.length; i++) {
      expect(placements[i].position, Offset(i + 0.5, 0));
      expect(placements[i].angle, 0);
    }
  });

  testWidgets('symbol text keeps the MapLibre evaluated font size', (
    tester,
  ) async {
    final symbols = [
      MapSymbol(
        key: 'small',
        data: symbolLabel('small', 4),
        textPos: const Offset(50, 50),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
      MapSymbol(
        key: 'large',
        data: symbolLabel('large', 64),
        textPos: const Offset(150, 150),
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
          screenSize: const Size(200, 200),
          onFadedOut: (_) {},
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('small')).style?.fontSize, 4);
    expect(tester.widget<Text>(find.text('large')).style?.fontSize, 64);
    expect(find.byType(AnimatedOpacity), findsNothing);
  });

  testWidgets('point labels keep every MapLibre-shaped line', (tester) async {
    final symbol = MapSymbol(
      key: 'place:1',
      data: symbolLabel('KANDA-OGAWAMACHI\n3-CHOME\n神田小川町', 12),
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
          onFadedOut: (_) {},
        ),
      ),
    );

    final text = tester.widget<Text>(find.text(symbol.data.text));
    expect(text.maxLines, isNull);
    expect(text.softWrap, isFalse);
  });

  testWidgets('point text uses the exact native collision width', (
    tester,
  ) async {
    final symbols = [
      MapSymbol(
        key: 'left',
        data: symbolLabel(
          'left',
          20,
          textW: 40,
          textJustify: LabelTextJustify.left,
        ),
        textPos: const Offset(50, 50),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
      MapSymbol(
        key: 'right',
        data: symbolLabel(
          'right',
          20,
          textW: 40,
          textJustify: LabelTextJustify.right,
        ),
        textPos: const Offset(150, 50),
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
          screenSize: const Size(200, 100),
          onFadedOut: (_) {},
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('left')).textAlign, TextAlign.left);
    expect(tester.widget<Text>(find.text('right')).textAlign, TextAlign.right);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 40,
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('symbol text applies evaluated font and shaping properties', (
    tester,
  ) async {
    final symbol = MapSymbol(
      key: 'place:2',
      data: symbolLabel(
        'Tokyo',
        20,
        textFont: 'Noto Sans Bold Italic',
        letterSpacing: 0.1,
        lineHeight: 1.3,
        maxWidth: 6.25,
      ),
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
          onFadedOut: (_) {},
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Tokyo'));
    expect(text.style?.fontFamily, 'Noto Sans');
    expect(text.style?.fontWeight, FontWeight.w700);
    expect(text.style?.fontStyle, FontStyle.italic);
    expect(text.style?.letterSpacing, 2);
    expect(text.style?.height, 1.3);
    expect(tester.widget<SizedBox>(find.byType(SizedBox).last).width, 125);
  });

  testWidgets('formatted text preserves run styles, fallback, and justify', (
    tester,
  ) async {
    final data = symbolLabel(
      'SMALL FORMAT',
      20,
      textFonts: const ['Missing Face Regular', 'Noto Sans Regular'],
      textJustify: LabelTextJustify.left,
      textSections: const [
        LabelTextSection(
          start: 0,
          end: 6,
          fontScale: 0.7,
          color: Color(0xFFBE123C),
        ),
        LabelTextSection(
          start: 6,
          end: 12,
          fontScale: 1.35,
          fonts: ['Display Face Bold', 'Fallback Face Regular'],
          color: Color(0xFF0F766E),
        ),
      ],
    );
    final symbol = MapSymbol(
      key: 'formatted',
      data: data,
      textPos: Offset.zero,
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildDefaultSymbolText(context, symbol)!,
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.textAlign, TextAlign.left);
    expect(text.textDirection, TextDirection.ltr);
    final root = text.textSpan! as TextSpan;
    final first = root.children![0] as TextSpan;
    final second = root.children![1] as TextSpan;
    expect(first.text, 'SMALL ');
    expect(first.style?.fontSize, closeTo(14, 0.001));
    expect(first.style?.fontFamily, 'Missing Face');
    expect(first.style?.fontFamilyFallback, ['Noto Sans']);
    expect(first.style?.color, const Color(0xFFBE123C));
    expect(second.text, 'FORMAT');
    expect(second.style?.fontSize, closeTo(27, 0.001));
    expect(second.style?.fontFamily, 'Display Face');
    expect(second.style?.fontFamilyFallback, ['Fallback Face']);
    expect(second.style?.fontWeight, FontWeight.w700);
    expect(second.style?.color, const Color(0xFF0F766E));
  });

  testWidgets('point text uses logical BiDi order and resolved direction', (
    tester,
  ) async {
    final data = symbolLabel(
      'שלום',
      20,
      visualText: 'םולש',
      textDirection: TextDirection.rtl,
    );
    final symbol = MapSymbol(
      key: 'rtl-point',
      data: data,
      textPos: Offset.zero,
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildDefaultSymbolText(context, symbol)!,
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('שלום'));
    expect(text.textDirection, TextDirection.rtl);
    expect(find.text('םולש'), findsNothing);
  });

  testWidgets('formatted RTL line text uses visual-order section ranges', (
    tester,
  ) async {
    final data = symbolLabel(
      'אבCD',
      20,
      visualText: 'CDבא',
      textDirection: TextDirection.rtl,
      textSections: const [
        LabelTextSection(start: 0, end: 2, color: Color(0xFFFF0000)),
        LabelTextSection(start: 2, end: 4, color: Color(0xFF0000FF)),
      ],
      visualTextSections: const [
        LabelTextSection(start: 0, end: 2, color: Color(0xFF0000FF)),
        LabelTextSection(start: 2, end: 4, color: Color(0xFFFF0000)),
      ],
      alongLine: true,
      textPath: const [
        LabelPathPoint(-60, 0),
        LabelPathPoint(0, 0),
        LabelPathPoint(60, 0),
      ],
    );
    final symbol = MapSymbol(
      key: 'rtl-line',
      data: data,
      textPos: Offset.zero,
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildDefaultSymbolText(context, symbol)!,
        ),
      ),
    );

    final glyphs = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(glyphs.map((widget) => widget.data).join(), 'CDבא');
    expect(glyphs.map((widget) => widget.style?.color), const [
      Color(0xFF0000FF),
      Color(0xFF0000FF),
      Color(0xFFFF0000),
      Color(0xFFFF0000),
    ]);
  });

  testWidgets('formatted inline images resolve through the symbol atlas', (
    tester,
  ) async {
    final loaded = await tester.runAsync(loadTestSpriteAtlas);
    final fixture = loaded!;
    addTearDown(() {
      fixture.atlas.dispose();

      return fixture.directory.delete(recursive: true);
    });
    final data = symbolLabel(
      '\uE000 label',
      20,
      haloWidth: 1,
      textSections: const [
        LabelTextSection(start: 0, end: 1, imageId: 'pin', fontScale: 2),
        LabelTextSection(start: 1, end: 7),
      ],
    );
    final symbol = MapSymbol(
      key: 'inline-image',
      data: data,
      textPos: Offset.zero,
      iconPos: null,
      icon: null,
      spriteAtlas: fixture.atlas,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildDefaultSymbolText(context, symbol)!,
        ),
      ),
    );

    expect(find.byType(SpriteIconWidget), findsOneWidget);
    expect(
      tester.widget<SpriteIconWidget>(find.byType(SpriteIconWidget)).scale,
      2,
    );
  });

  testWidgets('formatted SDF inline images use the text halo', (tester) async {
    final loaded = await tester.runAsync(() => loadTestSpriteAtlas(sdf: true));
    final fixture = loaded!;
    addTearDown(() {
      fixture.atlas.dispose();

      return fixture.directory.delete(recursive: true);
    });
    final data = symbolLabel(
      '\uE000 label',
      20,
      haloR: 1,
      haloG: 0.5,
      haloA: 1,
      haloWidth: 3,
      haloBlur: 2,
      textSections: const [
        LabelTextSection(start: 0, end: 1, imageId: 'pin', fontScale: 2),
        LabelTextSection(start: 1, end: 7),
      ],
    );
    final symbol = MapSymbol(
      key: 'inline-sdf-image',
      data: data,
      textPos: Offset.zero,
      iconPos: null,
      icon: null,
      spriteAtlas: fixture.atlas,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildDefaultSymbolText(context, symbol)!,
        ),
      ),
    );

    final images = tester.widgetList<SpriteIconWidget>(
      find.byType(SpriteIconWidget),
    );
    expect(images, hasLength(2));
    final halo = images.singleWhere((image) => image.haloWidth > 0);
    expect(halo.tint, const Color(0x00000000));
    expect(halo.haloColor, const Color(0xFFFF8000));
    expect(halo.haloWidth, 3);
    expect(halo.haloBlur, 2);
  });

  testWidgets('vertical text uses one widget per grapheme', (tester) async {
    final data = symbolLabel('東京A', 24, vertical: true);
    final symbol = MapSymbol(
      key: 'vertical',
      data: data,
      textPos: Offset.zero,
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildDefaultSymbolText(context, symbol)!,
        ),
      ),
    );

    expect(find.text('東'), findsOneWidget);
    expect(find.text('京'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.byType(Column), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Column),
        matching: find.byType(Transform),
      ),
      findsOneWidget,
    );
  });

  testWidgets('curved text keeps graphemes and applies rotation once', (
    tester,
  ) async {
    const rotation = 0.3;
    final data = symbolLabel(
      'A👨‍👩‍👧‍👦B',
      20,
      alongLine: true,
      textRotation: rotation,
      textPath: const [
        LabelPathPoint(-80, 0),
        LabelPathPoint(0, 0),
        LabelPathPoint(80, 0),
      ],
      textTransform: LabelAffineTransform(
        xx: math.cos(rotation),
        xy: math.sin(rotation),
        yx: -math.sin(rotation),
        yy: math.cos(rotation),
      ),
    );
    final symbol = MapSymbol(
      key: 'curved',
      data: data,
      textPos: Offset.zero,
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildDefaultSymbolText(context, symbol)!,
        ),
      ),
    );

    expect(find.text('A'), findsOneWidget);
    expect(find.text('👨‍👩‍👧‍👦'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    expect(transforms, hasLength(3));
    final singleRotations = transforms.where(
      (widget) =>
          (widget.transform.storage[0] - math.cos(rotation)).abs() < 0.001 &&
          (widget.transform.storage[1] - math.sin(rotation)).abs() < 0.001,
    );
    final doubleRotations = transforms.where(
      (widget) =>
          (widget.transform.storage[0] - math.cos(rotation * 2)).abs() <
              0.001 &&
          (widget.transform.storage[1] - math.sin(rotation * 2)).abs() < 0.001,
    );
    expect(singleRotations, hasLength(3));
    expect(doubleRotations, isEmpty);
  });

  testWidgets('curved text ignores scale when either axis is non-finite', (
    tester,
  ) async {
    const rotation = 0.3;
    final symbol = MapSymbol(
      key: 'non-finite-path-scale',
      data: symbolLabel(
        'A',
        20,
        alongLine: true,
        textRotation: rotation,
        textPath: const [LabelPathPoint(-40, 0), LabelPathPoint(40, 0)],
        textTransform: const LabelAffineTransform(
          xx: 2,
          xy: 0,
          yx: 0,
          yy: double.nan,
        ),
      ),
      textPos: Offset.zero,
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildDefaultSymbolText(context, symbol)!,
        ),
      ),
    );

    final transform = tester.widget<Transform>(find.byType(Transform));
    expect(transform.transform.storage[0], closeTo(math.cos(rotation), 0.001));
    expect(transform.transform.storage[1], closeTo(math.sin(rotation), 0.001));
    expect(transform.transform.storage[4], closeTo(-math.sin(rotation), 0.001));
    expect(transform.transform.storage[5], closeTo(math.cos(rotation), 0.001));
  });

  testWidgets('line text keeps pitch compression in screen vertical axis', (
    tester,
  ) async {
    final symbol = MapSymbol(
      key: 'pitched-line',
      data: symbolLabel(
        'platform',
        20,
        alongLine: true,
        textPath: const [LabelPathPoint(-80, 0), LabelPathPoint(80, 0)],
        textTransform: const LabelAffineTransform(
          xx: 0,
          xy: 0.5,
          yx: -1,
          yy: 0,
        ),
      ),
      textPos: Offset.zero,
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildDefaultSymbolText(context, symbol)!,
        ),
      ),
    );

    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    expect(transforms, isNotEmpty);
    for (final transform in transforms) {
      expect(transform.transform.storage[0], closeTo(1, 0.001));
      expect(transform.transform.storage[5], closeTo(0.5, 0.001));
    }
  });

  testWidgets('point text uses final affine transform and screen translation', (
    tester,
  ) async {
    const rotation = 0.4;
    final data = symbolLabel(
      'point',
      20,
      textRotation: rotation,
      textTranslateX: 12,
      textTranslateY: -7,
      textTransform: LabelAffineTransform(
        xx: math.cos(rotation),
        xy: math.sin(rotation),
        yx: -math.sin(rotation),
        yy: math.cos(rotation),
      ),
    );
    final symbol = MapSymbol(
      key: 'point-transform',
      data: data,
      textPos: Offset.zero,
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildDefaultSymbolText(context, symbol)!,
        ),
      ),
    );

    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    expect(
      transforms.any(
        (widget) =>
            (widget.transform.storage[12] - 12).abs() < 0.001 &&
            (widget.transform.storage[13] + 7).abs() < 0.001,
      ),
      isTrue,
    );
    expect(
      transforms.any(
        (widget) =>
            (widget.transform.storage[0] - math.cos(rotation)).abs() < 0.001 &&
            (widget.transform.storage[1] - math.sin(rotation)).abs() < 0.001,
      ),
      isTrue,
    );
    expect(
      transforms.any(
        (widget) =>
            (widget.transform.storage[0] - math.cos(rotation * 2)).abs() <
            0.001,
      ),
      isFalse,
    );
  });
}
