import 'dart:ui' show Color, TextDirection;

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart'
    as legacy_ffi;

void main() {
  LabelData createLabel({
    double textR = 0,
    double textG = 0,
    double textB = 0,
    double textA = 1,
    double haloR = 0,
    double haloG = 0,
    double haloB = 0,
    double haloA = 0,
  }) => .new(
    lat: 35,
    lon: 139,
    fontSize: 16,
    textR: textR,
    textG: textG,
    textB: textB,
    textA: textA,
    haloR: haloR,
    haloG: haloG,
    haloB: haloB,
    haloA: haloA,
    haloWidth: 2,
    text: 'Tokyo',
    layer: 'place-label',
  );

  test('constructor defaults and legacy FFI export remain stable', () {
    final label = createLabel();
    final legacy_ffi.LabelData legacyView = label;

    expect(legacyView, same(label));
    expect(label.crossTileId, 0);
    expect(label.iconLat, 0);
    expect(label.iconLon, 0);
    expect(label.textW, 0);
    expect(label.textH, 0);
    expect(label.iconW, 0);
    expect(label.iconH, 0);
    expect(label.iconScale, 1);
    expect(label.iconOpacity, 1);
    expect(label.iconR, 0);
    expect(label.iconG, 0);
    expect(label.iconB, 0);
    expect(label.iconA, 1);
    expect(label.textOffsetX, 0);
    expect(label.textOffsetY, 0);
    expect(label.textOpacity, 1);
    expect(label.haloBlur, 0);
    expect(label.letterSpacing, 0);
    expect(label.lineHeight, 1.2);
    expect(label.maxWidth, 10);
    expect(label.textFont, isEmpty);
    expect(label.iconOffsetX, 0);
    expect(label.iconOffsetY, 0);
    expect(label.renderGroup, 0);
    expect(label.renderOrder, 0);
    expect(label.textPlaced, isTrue);
    expect(label.iconPlaced, isFalse);
    expect(label.alongLine, isFalse);
    expect(label.angle, 0);
    expect(label.icon, isEmpty);
    expect(label.visualText, label.text);
    expect(label.textDirection, TextDirection.ltr);
  });

  test('supporting label value types are public', () {
    const section = LabelTextSection(start: 0, end: 4);
    const path = LabelPathPoint(1, 2);
    const transform = LabelAffineTransform(xx: 2);

    expect(section.fontScale, 1);
    expect(path.x, 1);
    expect(transform.xx, 2);
    expect(LabelTextJustify.values, hasLength(4));
    expect(SpriteTextFit.values, hasLength(3));
  });

  test('colors convert premultiplied channels to straight alpha', () {
    final label = createLabel(
      textR: 0.25,
      textG: 0.125,
      textA: 0.5,
      haloR: 1,
      haloG: 1,
      haloB: 1,
      haloA: 0,
    );

    expect(label.textColor, const Color.fromARGB(128, 128, 64, 0));
    expect(label.haloColor, const Color(0x00000000));
    expect(label.iconColor, const Color.fromARGB(255, 0, 0, 0));
  });
}
