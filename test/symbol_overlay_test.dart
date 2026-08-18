import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/sprites/sprite_atlas.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbol_overlay.dart'
    show
        buildDefaultSymbolIcon,
        buildDefaultSymbolText,
        layoutSymbolGlyphsAlongPath;

LabelData _label(
  String text,
  double fontSize, {
  String? visualText,
  TextDirection textDirection = TextDirection.ltr,
  int crossTileId = 0,
  String textFont = '',
  double letterSpacing = 0,
  double lineHeight = 1.2,
  double maxWidth = 10,
  List<String> textFonts = const [],
  List<LabelTextSection> textSections = const [],
  List<LabelTextSection> visualTextSections = const [],
  List<LabelPathPoint> textPath = const [],
  List<LabelPathPoint> iconPath = const [],
  LabelTextJustify textJustify = LabelTextJustify.center,
  LabelAffineTransform textTransform = const LabelAffineTransform(),
  LabelAffineTransform iconTransform = const LabelAffineTransform(),
  bool vertical = false,
  bool alongLine = false,
  bool iconAlongLine = false,
  bool iconRotationWithMap = false,
  bool textKeepUpright = true,
  bool iconKeepUpright = false,
  double textRotation = 0,
  double iconRotation = 0,
  double textTranslateX = 0,
  double textTranslateY = 0,
  double iconTranslateX = 0,
  double iconTranslateY = 0,
  double haloR = 0,
  double haloG = 0,
  double haloB = 0,
  double haloA = 0,
  double haloWidth = 0,
  double haloBlur = 0,
  bool textPlaced = true,
  bool iconPlaced = false,
  String icon = '',
  double iconScale = 1,
  double iconOpacity = 1,
  double iconHaloR = 0,
  double iconHaloG = 0,
  double iconHaloB = 0,
  double iconHaloA = 0,
  double iconHaloWidth = 0,
  double iconHaloBlur = 0,
  double iconFitWidth = 0,
  double iconFitHeight = 0,
  double textW = 0,
  int layerIndex = 0,
  int renderGroup = 0,
  int renderOrder = 0,
}) => LabelData(
  crossTileId: crossTileId,
  lat: 0,
  lon: 0,
  fontSize: fontSize,
  textR: 0,
  textG: 0,
  textB: 0,
  textA: 1,
  haloR: haloR,
  haloG: haloG,
  haloB: haloB,
  haloA: haloA,
  haloWidth: haloWidth,
  haloBlur: haloBlur,
  textFont: textFont,
  textFonts: textFonts,
  textSections: textSections,
  visualTextSections: visualTextSections,
  textPath: textPath,
  iconPath: iconPath,
  letterSpacing: letterSpacing,
  lineHeight: lineHeight,
  maxWidth: maxWidth,
  textJustify: textJustify,
  textTransform: textTransform,
  iconTransform: iconTransform,
  vertical: vertical,
  alongLine: alongLine,
  iconAlongLine: iconAlongLine,
  iconRotationWithMap: iconRotationWithMap,
  textKeepUpright: textKeepUpright,
  iconKeepUpright: iconKeepUpright,
  textRotation: textRotation,
  iconRotation: iconRotation,
  textTranslateX: textTranslateX,
  textTranslateY: textTranslateY,
  iconTranslateX: iconTranslateX,
  iconTranslateY: iconTranslateY,
  textPlaced: textPlaced,
  iconPlaced: iconPlaced,
  icon: icon,
  iconScale: iconScale,
  iconOpacity: iconOpacity,
  iconHaloR: iconHaloR,
  iconHaloG: iconHaloG,
  iconHaloB: iconHaloB,
  iconHaloA: iconHaloA,
  iconHaloWidth: iconHaloWidth,
  iconHaloBlur: iconHaloBlur,
  iconFitWidth: iconFitWidth,
  iconFitHeight: iconFitHeight,
  textW: textW,
  text: text,
  visualText: visualText,
  textDirection: textDirection,
  layer: 'labels',
  layerIndex: layerIndex,
  renderGroup: renderGroup,
  renderOrder: renderOrder,
);

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

Future<({SpriteAtlas atlas, Directory directory})> _loadTestSpriteAtlas({
  bool sdf = false,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'maplibre-symbol-widget-',
  );
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  await File('${directory.path}/sprite.json').writeAsString(
    jsonEncode({
      'pin': {
        'x': 0,
        'y': 0,
        'width': 1,
        'height': 1,
        'pixelRatio': 1,
        'sdf': sdf,
      },
    }),
  );
  await File('${directory.path}/sprite.png').writeAsBytes(png);
  final atlas = await SpriteAtlas.load(
    jsonEncode({'version': 8, 'sprite': '${directory.uri}sprite'}),
  );
  if (atlas == null) {
    await directory.delete(recursive: true);
    throw StateError('test sprite atlas did not load');
  }

  return (atlas: atlas, directory: directory);
}

void main() {
  test('symbol overlay rejects a negative fade duration', () {
    MapSymbolOverlay overlay({
      Duration fadeDuration = Duration.zero,
      EdgeInsets cullingPadding = EdgeInsets.zero,
    }) => MapSymbolOverlay(
      symbols: const [],
      screenSize: const Size(200, 200),
      onFadedOut: (_) {},
      fadeDuration: fadeDuration,
      cullingPadding: cullingPadding,
    );

    expect(
      () => overlay(fadeDuration: const Duration(microseconds: -1)),
      throwsAssertionError,
    );
  });

  testWidgets('null symbol builders hide icon and text', (tester) async {
    final symbol = MapSymbol(
      key: 'hidden',
      data: _label('hidden', 16),
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
          iconBuilder: null,
          textBuilder: null,
          onFadedOut: (_) {},
        ),
      ),
    );

    expect(find.text('hidden'), findsNothing);
  });

  testWidgets('paints native groups with icons before text', (tester) async {
    MapSymbol symbol(String key, int group, int order) => MapSymbol(
      key: key,
      data: _label(key, 12, renderGroup: group, renderOrder: order),
      textPos: const Offset(50, 50),
      iconPos: const Offset(50, 50),
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [
            symbol('front', 0, 1),
            symbol('later', 1, 0),
            symbol('back', 0, 0),
          ],
          screenSize: const Size(100, 100),
          fadeDuration: Duration.zero,
          onFadedOut: (_) {},
          iconBuilder: (_, symbol) => Text('icon:${symbol.key}'),
          textBuilder: (_, symbol) => Text('text:${symbol.key}'),
        ),
      ),
    );

    final layout = tester.widget<CustomMultiChildLayout>(
      find.byType(CustomMultiChildLayout),
    );
    expect(layout.children.map((child) => (child as LayoutId).id), <Object>[
      ('back', true),
      ('front', true),
      ('back', false),
      ('front', false),
      ('later', true),
      ('later', false),
    ]);
  });

  testWidgets('custom symbols receive taps while defaults pass them through', (
    tester,
  ) async {
    final symbol = MapSymbol(
      key: 'tap-target',
      data: _label('tap target', 16),
      textPos: const Offset(100, 100),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );
    var mapTaps = 0;
    var symbolTaps = 0;

    Future<void> pump(SymbolWidgetBuilder textBuilder) => tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => mapTaps++,
              ),
            ),
            Positioned.fill(
              child: MapSymbolOverlay(
                symbols: [symbol],
                screenSize: const Size(200, 200),
                onFadedOut: (_) {},
                textBuilder: textBuilder,
              ),
            ),
          ],
        ),
      ),
    );

    await pump(buildDefaultSymbolText);
    await tester.tapAt(tester.getCenter(find.text('tap target')));
    await tester.pump();

    expect(mapTaps, 1);
    expect(symbolTaps, 0);

    await pump(
      (_, _) => GestureDetector(
        key: const ValueKey('custom-symbol'),
        behavior: HitTestBehavior.opaque,
        onTap: () => symbolTaps++,
        child: const SizedBox(width: 80, height: 40),
      ),
    );
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('custom-symbol'))),
    );
    await tester.pump();

    expect(mapTaps, 1);
    expect(symbolTaps, 1);
  });

  testWidgets('hidden custom symbols pass taps through while fading out', (
    tester,
  ) async {
    var mapTaps = 0;
    var symbolTaps = 0;

    Future<void> pump(bool visible) => tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => mapTaps++,
              ),
            ),
            Positioned.fill(
              child: MapSymbolOverlay(
                symbols: [
                  MapSymbol(
                    key: 'fading-tap-target',
                    data: _label('fading tap target', 16),
                    textPos: const Offset(100, 100),
                    iconPos: null,
                    icon: null,
                    visible: visible,
                  ),
                ],
                screenSize: const Size(200, 200),
                fadeDuration: const Duration(seconds: 1),
                onFadedOut: (_) {},
                textBuilder: (_, _) => GestureDetector(
                  key: const ValueKey('fading-custom-symbol'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => symbolTaps++,
                  child: const SizedBox(width: 80, height: 40),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    await pump(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await pump(false);

    expect(find.byType(AnimatedOpacity), findsOneWidget);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('fading-custom-symbol'))),
    );
    await tester.pump();

    expect(mapTaps, 1);
    expect(symbolTaps, 0);
  });

  testWidgets('symbol culling padding is configurable', (tester) async {
    final symbol = MapSymbol(
      key: 'outside',
      data: _label('outside', 16),
      textPos: const Offset(-50, 100),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    Future<void> pump(EdgeInsets padding) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [symbol],
          screenSize: const Size(200, 200),
          cullingPadding: padding,
          onFadedOut: (_) {},
        ),
      ),
    );

    await pump(EdgeInsets.zero);
    expect(find.text('outside'), findsNothing);
    await pump(const EdgeInsets.only(left: 60));
    expect(find.text('outside'), findsOneWidget);
  });

  testWidgets('culls text and icon with their own anchors', (tester) async {
    Future<void> pump({required Offset textPos, required Offset iconPos}) =>
        tester.pumpWidget(
          MaterialApp(
            home: MapSymbolOverlay(
              symbols: [
                MapSymbol(
                  key: 'split',
                  data: _label('split', 12),
                  textPos: textPos,
                  iconPos: iconPos,
                  icon: null,
                  visible: true,
                  fadeIn: false,
                ),
              ],
              screenSize: const Size(100, 100),
              cullingPadding: EdgeInsets.zero,
              fadeDuration: Duration.zero,
              onFadedOut: (_) {},
              iconBuilder: (_, _) => const Text('inside icon'),
              textBuilder: (_, _) => const Text('inside text'),
            ),
          ),
        );

    await pump(textPos: const Offset(-10, 50), iconPos: const Offset(50, 50));
    expect(find.text('inside icon'), findsOneWidget);
    expect(find.text('inside text'), findsNothing);

    await pump(textPos: const Offset(50, 50), iconPos: const Offset(110, 50));
    expect(find.text('inside icon'), findsNothing);
    expect(find.text('inside text'), findsOneWidget);
  });

  testWidgets('relayout rebuilds a component that enters the culling area', (
    tester,
  ) async {
    final relayout = ValueNotifier<int>(0);
    final data = _label('moving', 12);
    var current = MapSymbol(
      key: 'moving',
      data: data,
      textPos: const Offset(-10, 50),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [current],
          symbolsProvider: () => [current],
          relayout: relayout,
          screenSize: const Size(100, 100),
          cullingPadding: EdgeInsets.zero,
          fadeDuration: Duration.zero,
          onFadedOut: (_) {},
          textBuilder: (_, _) => const Text('moving child'),
        ),
      ),
    );
    expect(find.text('moving child'), findsNothing);

    current = MapSymbol(
      key: 'moving',
      data: data,
      textPos: const Offset(50, 50),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );
    relayout.value++;
    await tester.pump();

    expect(find.text('moving child'), findsOneWidget);
    relayout.dispose();
  });

  testWidgets('invalid culling padding falls back to zero', (tester) async {
    final symbol = MapSymbol(
      key: 'outside',
      data: _label('outside', 16),
      textPos: const Offset(250, 100),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    Future<void> pump(EdgeInsets padding) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [symbol],
          screenSize: const Size(200, 200),
          cullingPadding: padding,
          onFadedOut: (_) {},
        ),
      ),
    );

    await pump(const EdgeInsets.only(right: double.infinity));
    expect(find.text('outside'), findsNothing);
    await pump(const EdgeInsets.only(right: -1));
    expect(find.text('outside'), findsNothing);
  });

  test('SDF sprite opacity is applied once through its tint', () {
    final tinted = spritePaintColors(0.5, const Color(0x80FF0000));
    final plain = spritePaintColors(0.5, null);

    expect(tinted.imageColor.a, 1);
    expect(tinted.filterColor?.a, closeTo(0.25, 0.001));
    expect(plain.imageColor.a, closeTo(0.5, 0.001));
    expect(plain.filterColor, isNull);
  });

  test('SDF coverage follows the MapLibre smooth edge', () {
    expect(spriteSdfCoverage(0.6, 0.75, 0.1), 0);
    expect(spriteSdfCoverage(0.75, 0.75, 0.1), closeTo(0.5, 0.0001));
    expect(spriteSdfCoverage(0.9, 0.75, 0.1), 1);
    expect(spriteSdfCoverage(0.74, 0.75, 0), 0);
    expect(spriteSdfCoverage(0.75, 0.75, 0), 1);
  });

  testWidgets('SDF icon opacity composites fill and halo after coverage', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final haloDistance = Paint()
      ..color = const Color.fromARGB(189, 255, 255, 255);
    final fillDistance = Paint()..color = const Color(0xFFFFFFFF);
    canvas
      ..drawRect(const Rect.fromLTWH(0, 0, 1, 1), haloDistance)
      ..drawRect(const Rect.fromLTWH(1, 0, 1, 1), fillDistance)
      ..drawRect(const Rect.fromLTWH(2, 0, 1, 1), haloDistance);
    final atlas = recorder.endRecording().toImageSync(3, 1);
    addTearDown(atlas.dispose);
    final icon = SpriteIcon(
      atlas: atlas,
      x: 0,
      y: 0,
      width: 3,
      height: 1,
      pixelRatio: 1,
      sdf: true,
    );
    const boundaryKey = ValueKey('sdf-opacity-boundary');
    const background = Color(0xFFE7EDF3);
    const fill = Color(0xFF2563EB);
    const halo = Color(0xFFF97316);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: ColoredBox(
              color: background,
              child: SizedBox(
                width: 120,
                height: 60,
                child: Center(
                  child: SpriteIconWidget(
                    icon: icon,
                    scale: 30,
                    opacity: 0.5,
                    tint: fill,
                    haloColor: halo,
                    haloWidth: 3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final rendered = await tester.runAsync(boundary.toImage);
    expect(rendered, isNotNull);
    final image = rendered!;
    addTearDown(image.dispose);
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(bytes, isNotNull);

    Color pixel(int x, int y) {
      final offset = (y * image.width + x) * 4;

      return Color.fromARGB(
        bytes!.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    }

    void expectHalfComposite(Color actual, Color foreground) {
      expect(actual.r * 255, closeTo((background.r + foreground.r) * 127.5, 4));
      expect(actual.g * 255, closeTo((background.g + foreground.g) * 127.5, 4));
      expect(actual.b * 255, closeTo((background.b + foreground.b) * 127.5, 4));
    }

    expectHalfComposite(pixel(60, 30), fill);
    expectHalfComposite(pixel(30, 30), halo);
  });

  test('sprite arrays retain every valid namespace', () {
    expect(
      spriteSources([
        {'id': 'default', 'url': 'default/sprite'},
        {'id': 'hiking', 'url': 'hiking/sprite'},
        {'id': 'cycling', 'url': 'hiking/sprite'},
        {'id': '', 'url': 'invalid'},
        {'id': 'hiking', 'url': 'duplicate'},
      ]),
      [
        (id: 'default', url: 'default/sprite'),
        (id: 'hiking', url: 'hiking/sprite'),
        (id: 'cycling', url: 'hiking/sprite'),
      ],
    );
    expect(spriteImageName('default', 'pin'), 'pin');
    expect(spriteImageName('hiking', 'pin'), 'hiking:pin');
  });

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

  test('sprite atlas loads every source in a sprite array', () async {
    final directory = await Directory.systemTemp.createTemp(
      'maplibre-sprite-array-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    for (final name in ['default', 'hiking']) {
      await File('${directory.path}/$name.json').writeAsString(
        jsonEncode({
          'pin': {'x': 0, 'y': 0, 'width': 1, 'height': 1, 'pixelRatio': 1},
        }),
      );
      await File('${directory.path}/$name.png').writeAsBytes(png);
    }
    final atlas = await SpriteAtlas.load(
      jsonEncode({
        'version': 8,
        'sprite': [
          {'id': 'default', 'url': '${directory.uri}default'},
          {'id': 'hiking', 'url': '${directory.uri}hiking'},
        ],
      }),
    );
    addTearDown(() => atlas?.dispose());

    expect(atlas, isNotNull);
    expect(atlas?['pin'], isNotNull);
    expect(atlas?['hiking:pin'], isNotNull);
    expect(atlas?['default:pin'], isNull);
  });

  test('relative sprite assets resolve against the style URL', () {
    expect(
      spriteAssetUri(
        'https://tiles.example/styles/basic/style.json',
        '../../sprites/basic?key=abc',
        '@2x',
        'json',
      ).toString(),
      'https://tiles.example/sprites/basic@2x.json?key=abc',
    );
    expect(
      spriteAssetUri(
        'https://tiles.example/styles/basic/style.json',
        'https://cdn.example/sprite',
        '',
        'png',
      ).toString(),
      'https://cdn.example/sprite.png',
    );
  });

  testWidgets('symbol text keeps the MapLibre evaluated font size', (
    tester,
  ) async {
    final symbols = [
      MapSymbol(
        key: 'small',
        data: _label('small', 4),
        textPos: const Offset(50, 50),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
      MapSymbol(
        key: 'large',
        data: _label('large', 64),
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

  testWidgets('completed symbol fade drops its compositing widget', (
    tester,
  ) async {
    final symbol = MapSymbol(
      key: 'places:fade',
      data: _label('fade', 16),
      textPos: const Offset(100, 100),
      iconPos: null,
      icon: null,
      visible: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [symbol],
          screenSize: const Size(200, 200),
          fadeDuration: const Duration(milliseconds: 150),
          onFadedOut: (_) {},
        ),
      ),
    );
    expect(find.byType(AnimatedOpacity), findsOneWidget);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedOpacity), findsNothing);
  });

  testWidgets('point labels keep every MapLibre-shaped line', (tester) async {
    final symbol = MapSymbol(
      key: 'place:1',
      data: _label('KANDA-OGAWAMACHI\n3-CHOME\n神田小川町', 12),
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
        data: _label('left', 20, textW: 40, textJustify: LabelTextJustify.left),
        textPos: const Offset(50, 50),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
      MapSymbol(
        key: 'right',
        data: _label(
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
      data: _label(
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
    final data = _label(
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
    final data = _label(
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
    final data = _label(
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
    final loaded = await tester.runAsync(_loadTestSpriteAtlas);
    final fixture = loaded!;
    addTearDown(() {
      fixture.atlas.dispose();

      return fixture.directory.delete(recursive: true);
    });
    final data = _label(
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
    final loaded = await tester.runAsync(() => _loadTestSpriteAtlas(sdf: true));
    final fixture = loaded!;
    addTearDown(() {
      fixture.atlas.dispose();

      return fixture.directory.delete(recursive: true);
    });
    final data = _label(
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
    final data = _label('東京A', 24, vertical: true);
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
    final data = _label(
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

  testWidgets('point text uses final affine transform and screen translation', (
    tester,
  ) async {
    const rotation = 0.4;
    final data = _label(
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

  testWidgets('default SDF icon applies fit, halo, affine, and translation', (
    tester,
  ) async {
    final loaded = await tester.runAsync(() => _loadTestSpriteAtlas(sdf: true));
    final fixture = loaded!;
    addTearDown(() {
      fixture.atlas.dispose();

      return fixture.directory.delete(recursive: true);
    });
    const rotation = 0.25;
    final data = _label(
      '',
      16,
      textPlaced: false,
      iconPlaced: true,
      icon: 'pin',
      iconScale: 4,
      iconOpacity: 0.75,
      iconHaloR: 0.5,
      iconHaloA: 0.5,
      iconHaloWidth: 3,
      iconHaloBlur: 1,
      iconFitWidth: 30,
      iconFitHeight: 18,
      iconRotation: rotation,
      iconTranslateX: -8,
      iconTranslateY: 5,
      iconTransform: LabelAffineTransform(
        xx: math.cos(rotation),
        xy: math.sin(rotation),
        yx: -math.sin(rotation),
        yy: math.cos(rotation),
      ),
    );
    final symbol = MapSymbol(
      key: 'sdf-icon',
      data: data,
      textPos: null,
      iconPos: Offset.zero,
      icon: fixture.atlas['pin'],
      spriteAtlas: fixture.atlas,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildDefaultSymbolIcon(context, symbol)!,
        ),
      ),
    );

    final icon = tester.widget<SpriteIconWidget>(find.byType(SpriteIconWidget));
    expect(icon.fitSize, const Size(30, 18));
    expect(icon.scale, 4);
    expect(icon.opacity, 0.75);
    expect(icon.haloColor, const Color(0x80FF0000));
    expect(icon.haloWidth, 3);
    expect(icon.haloBlur, 1);
    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    expect(
      transforms.any(
        (widget) =>
            (widget.transform.storage[12] + 8).abs() < 0.001 &&
            (widget.transform.storage[13] - 5).abs() < 0.001,
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
  });

  testWidgets('icon text-fit applies proportional rounding before icon size', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final image = recorder.endRecording().toImageSync(10, 10);
    addTearDown(image.dispose);
    final icon = SpriteIcon(
      atlas: image,
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      pixelRatio: 1,
      content: const Rect.fromLTRB(1, 2, 9, 6),
      textFitWidth: SpriteTextFit.stretchOnly,
      textFitHeight: SpriteTextFit.proportional,
    );
    final data = _label(
      '',
      16,
      textPlaced: false,
      iconPlaced: true,
      icon: 'fit',
      iconScale: 1.5,
      iconFitWidth: 3,
      iconFitHeight: 3.3,
    );
    final symbol = MapSymbol(
      key: 'proportional-fit',
      data: data,
      textPos: null,
      iconPos: Offset.zero,
      icon: icon,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => buildDefaultSymbolIcon(context, symbol)!,
        ),
      ),
    );

    final widget = tester.widget<SpriteIconWidget>(
      find.byType(SpriteIconWidget),
    );
    expect(widget.fitSize, const Size(7.5, 3.3));
    expect(widget.fitSizeConstrained, isTrue);
  });

  testWidgets('line icon follows the path only with map rotation alignment', (
    tester,
  ) async {
    final loaded = await tester.runAsync(_loadTestSpriteAtlas);
    final fixture = loaded!;
    addTearDown(() {
      fixture.atlas.dispose();

      return fixture.directory.delete(recursive: true);
    });
    const styleRotation = 0.2;
    const pathRotation = math.pi / 4;

    Future<void> pump({required bool rotateWithMap}) {
      final data = _label(
        '',
        16,
        textPlaced: false,
        iconPlaced: true,
        icon: 'pin',
        alongLine: true,
        iconRotationWithMap: rotateWithMap,
        iconRotation: styleRotation,
        iconPath: const [LabelPathPoint(-20, -20), LabelPathPoint(20, 20)],
        iconTransform: LabelAffineTransform(
          xx: math.cos(styleRotation),
          xy: math.sin(styleRotation),
          yx: -math.sin(styleRotation),
          yy: math.cos(styleRotation),
        ),
      );
      final symbol = MapSymbol(
        key: 'line-icon',
        data: data,
        textPos: null,
        iconPos: Offset.zero,
        icon: fixture.atlas['pin'],
        spriteAtlas: fixture.atlas,
        visible: true,
        fadeIn: false,
      );

      return tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => buildDefaultSymbolIcon(context, symbol)!,
          ),
        ),
      );
    }

    bool hasRotation(double angle) => tester
        .widgetList<Transform>(find.byType(Transform))
        .any(
          (widget) =>
              (widget.transform.storage[0] - math.cos(angle)).abs() < 0.001 &&
              (widget.transform.storage[1] - math.sin(angle)).abs() < 0.001,
        );

    await pump(rotateWithMap: false);
    expect(hasRotation(styleRotation), isTrue);
    expect(hasRotation(pathRotation + styleRotation), isFalse);

    await pump(rotateWithMap: true);
    expect(hasRotation(pathRotation + styleRotation), isTrue);
  });

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
        data: _label('old', 12, crossTileId: 42),
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
        data: _label('new', 12, crossTileId: 42),
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
    final data = _label('stable', 16, crossTileId: 11);
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

  testWidgets('default position updates only relayout the overlay', (
    tester,
  ) async {
    final relayout = ValueNotifier<int>(0);
    final data = _label('layout only', 16, crossTileId: 12);
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
    final originalLayout = tester.widget<CustomMultiChildLayout>(
      find.byType(CustomMultiChildLayout),
    );

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
    await tester.pump();

    expect(
      identical(
        tester.widget<CustomMultiChildLayout>(
          find.byType(CustomMultiChildLayout),
        ),
        originalLayout,
      ),
      isTrue,
    );
    expect(tester.getCenter(find.text('layout only')), const Offset(140, 150));
    relayout.dispose();
  });

  testWidgets('moving a symbol reuses its unchanged default text widget', (
    tester,
  ) async {
    final data = _label('cached', 16, crossTileId: 9);
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

    await pump(data, const Offset(120, 130));
    expect(
      identical(tester.widget<Text>(find.text('cached')), originalText),
      isTrue,
    );

    await pump(_label('updated', 16, crossTileId: 9), const Offset(120, 130));
    expect(find.text('cached'), findsNothing);
    expect(find.text('updated'), findsOneWidget);
  });

  testWidgets('a custom builder still observes position-only updates', (
    tester,
  ) async {
    final data = _label('custom', 16, crossTileId: 10);
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

  testWidgets('culled hidden symbols complete removal without a fade widget', (
    tester,
  ) async {
    final fadedKeys = <String>[];
    final hidden = MapSymbol(
      key: 'labels:gone',
      data: _label('gone', 12, crossTileId: 7),
      textPos: const Offset(-1000, -1000),
      iconPos: null,
      icon: null,
      visible: false,
      fadeIn: false,
    );
    final visible = MapSymbol(
      key: 'labels:visible',
      data: _label('visible', 12, crossTileId: 8),
      textPos: const Offset(-1000, -1000),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [hidden, visible],
          screenSize: const Size(200, 200),
          onFadedOut: fadedKeys.add,
        ),
      ),
    );
    await tester.pump();

    expect(fadedKeys, contains('labels:gone'));
    expect(fadedKeys, isNot(contains('labels:visible')));
    expect(find.text('gone'), findsNothing);
  });
}
