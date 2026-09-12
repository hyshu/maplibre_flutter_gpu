import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/sprites/sprite_atlas.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbol_overlay.dart';

import 'support/symbol_fixtures.dart';

void main() {
  test('SDF sprite opacity is applied once through its tint', () {
    final tinted = spritePaintColors(0.5, const Color(0x80FF0000));
    final plain = spritePaintColors(0.5, null);

    expect(tinted.imageColor.a, 1);
    expect(tinted.filterColor?.a, closeTo(0.25, 0.001));
    expect(plain.imageColor.a, closeTo(0.5, 0.001));
    expect(plain.filterColor, isNull);
  });

  testWidgets('zero sprite opacity skips SDF fill and halo painting', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final image = recorder.endRecording().toImageSync(1, 1);
    addTearDown(image.dispose);
    const iconKey = ValueKey('transparent-sdf-icon');

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SpriteIconWidget(
            key: iconKey,
            icon: SpriteIcon(
              atlas: image,
              x: 0,
              y: 0,
              width: 1,
              height: 1,
              pixelRatio: 1,
              sdf: true,
            ),
            opacity: 0,
            tint: const Color(0xFFFF0000),
            haloColor: const Color(0xFF00FF00),
            haloWidth: 4,
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(iconKey),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    expect(tester.getSize(find.byKey(iconKey)), const Size(1, 1));
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

  testWidgets('default SDF icon applies fit, halo, affine, and translation', (
    tester,
  ) async {
    final loaded = await tester.runAsync(() => loadTestSpriteAtlas(sdf: true));
    final fixture = loaded!;
    addTearDown(() {
      fixture.atlas.dispose();

      return fixture.directory.delete(recursive: true);
    });
    const rotation = 0.25;
    final data = symbolLabel(
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
    final data = symbolLabel(
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
    final loaded = await tester.runAsync(loadTestSpriteAtlas);
    final fixture = loaded!;
    addTearDown(() {
      fixture.atlas.dispose();

      return fixture.directory.delete(recursive: true);
    });
    const styleRotation = 0.2;
    const pathRotation = math.pi / 4;

    Future<void> pump({required bool rotateWithMap}) {
      final data = symbolLabel(
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
}
