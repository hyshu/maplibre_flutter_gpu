import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/sprites/sprite_atlas.dart';

LabelData _label(
  String text,
  double fontSize, {
  int crossTileId = 0,
  String textFont = '',
  double letterSpacing = 0,
  double lineHeight = 1.2,
  double maxWidth = 10,
}) => LabelData(
  crossTileId: crossTileId,
  lat: 0,
  lon: 0,
  fontSize: fontSize,
  textR: 0,
  textG: 0,
  textB: 0,
  textA: 1,
  haloR: 0,
  haloG: 0,
  haloB: 0,
  haloA: 0,
  haloWidth: 0,
  textFont: textFont,
  letterSpacing: letterSpacing,
  lineHeight: lineHeight,
  maxWidth: maxWidth,
  textPlaced: true,
  text: text,
  layer: 'labels',
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

  testWidgets('position-only changes relayout without rebuilding symbols', (
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

    expect(builds, 1);
    expect(tester.getCenter(find.text('stable')), const Offset(140, 150));
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
