import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:test/test.dart';
import 'package:visual_e2e_runner/visual_e2e_runner.dart';

void main() {
  test('identical PNGs have perfect similarity', () {
    final png = _solidPng(10, 10, red: 30, green: 60, blue: 90);
    final result = comparePngBytes(referencePng: png, actualPng: png);

    expect(result.similarity, 1);
    expect(result.strictSimilarity, 1);
    expect(result.exactSimilarity, 1);
    expect(result.mismatchPixelCount, 0);
    expect(result.comparedPixelCount, 100);
  });

  test('substantial difference lowers global similarity', () {
    final reference = _solidImage(10, 10, red: 0, green: 0, blue: 0);
    final actual = image.Image.from(reference);
    actual.setPixelRgba(5, 5, 255, 255, 255, 255);

    final result = comparePngBytes(
      referencePng: Uint8List.fromList(image.encodePng(reference)),
      actualPng: Uint8List.fromList(image.encodePng(actual)),
      options: const PixelMatchOptions(includeAntiAlias: true),
    );

    expect(result.mismatchPixelCount, 1);
    expect(result.similarity, closeTo(0.99, 0.000001));
    expect(result.p95MaxChannelDelta, 0);
  });

  test('foreground similarity is not diluted by blank background', () {
    final reference = _solidImage(100, 100, red: 231, green: 237, blue: 243);
    final actual = image.Image.from(reference);
    for (var y = 45; y < 55; y++) {
      for (var x = 45; x < 55; x++) {
        reference.setPixelRgba(x, y, 20, 40, 60, 255);
        actual.setPixelRgba(x, y, 220, 40, 60, 255);
      }
    }

    final result = comparePngBytes(
      referencePng: Uint8List.fromList(image.encodePng(reference)),
      actualPng: Uint8List.fromList(image.encodePng(actual)),
      options: const PixelMatchOptions(
        includeAntiAlias: true,
        foregroundBackground: PixelColor(231, 237, 243),
      ),
    );

    expect(result.similarity, 0.99);
    expect(result.foreground!.unionPixelCount, 100);
    expect(result.foreground!.similarity, 0);
    expect(result.foreground!.intersectionOverUnion, 1);
  });

  test('foreground union catches content missing from either image', () {
    final reference = _solidImage(10, 10, red: 231, green: 237, blue: 243);
    final actual = image.Image.from(reference);
    for (var y = 2; y < 4; y++) {
      for (var x = 2; x < 4; x++) {
        reference.setPixelRgba(x, y, 20, 40, 60, 255);
      }
    }
    for (var y = 6; y < 8; y++) {
      for (var x = 6; x < 8; x++) {
        actual.setPixelRgba(x, y, 20, 40, 60, 255);
      }
    }

    final result = comparePngBytes(
      referencePng: Uint8List.fromList(image.encodePng(reference)),
      actualPng: Uint8List.fromList(image.encodePng(actual)),
      options: const PixelMatchOptions(
        includeAntiAlias: true,
        foregroundBackground: PixelColor(231, 237, 243),
      ),
    );

    expect(result.foreground!.referencePixelCount, 4);
    expect(result.foreground!.actualPixelCount, 4);
    expect(result.foreground!.intersectionPixelCount, 0);
    expect(result.foreground!.unionPixelCount, 8);
    expect(result.foreground!.similarity, 0);
    expect(result.foreground!.intersectionOverUnion, 0);
  });

  test('tight foreground gate catches reversed symbol z order', () {
    final reference = _solidImage(300, 300, red: 231, green: 237, blue: 243);
    final actual = image.Image.from(reference);
    _fillRect(
      reference,
      left: 100,
      top: 100,
      size: 60,
      red: 249,
      green: 115,
      blue: 22,
    );
    _fillRect(
      reference,
      left: 110,
      top: 110,
      size: 60,
      red: 22,
      green: 163,
      blue: 74,
    );
    _fillRect(
      actual,
      left: 110,
      top: 110,
      size: 60,
      red: 22,
      green: 163,
      blue: 74,
    );
    _fillRect(
      actual,
      left: 100,
      top: 100,
      size: 60,
      red: 249,
      green: 115,
      blue: 22,
    );
    final referencePng = Uint8List.fromList(image.encodePng(reference));
    final actualPng = Uint8List.fromList(image.encodePng(actual));
    final result = comparePngBytes(
      referencePng: referencePng,
      actualPng: actualPng,
      options: const PixelMatchOptions(
        includeAntiAlias: true,
        foregroundBackground: PixelColor(231, 237, 243),
        foregroundRegion: NormalizedPixelRegion(
          left: 0.36,
          top: 0.36,
          right: 0.54,
          bottom: 0.54,
          label: 'tight overlap center',
        ),
      ),
    );

    expect(
      pngContentRatio(
        png: referencePng,
        backgroundRed: 231,
        backgroundGreen: 237,
        backgroundBlue: 243,
      ),
      greaterThan(0.01),
    );
    expect(
      pngContentRatio(
        png: actualPng,
        backgroundRed: 231,
        backgroundGreen: 237,
        backgroundBlue: 243,
      ),
      greaterThan(0.01),
    );
    expect(result.similarity, greaterThan(0.95));
    expect(result.foreground!.intersectionOverUnion, 1);
    expect(result.foreground!.similarity, lessThan(0.20));
    expect(result.foreground!.region!.label, 'tight overlap center');
  });

  test('focused gate catches a missing small fixture', () {
    final reference = _solidImage(400, 400, red: 231, green: 237, blue: 243);
    final actual = image.Image.from(reference);
    _fillRect(
      reference,
      left: 40,
      top: 40,
      size: 160,
      red: 15,
      green: 118,
      blue: 110,
    );
    _fillRect(
      actual,
      left: 40,
      top: 40,
      size: 160,
      red: 15,
      green: 118,
      blue: 110,
    );
    _fillRect(
      reference,
      left: 310,
      top: 310,
      size: 32,
      red: 245,
      green: 158,
      blue: 11,
    );
    final referencePng = Uint8List.fromList(image.encodePng(reference));
    final actualPng = Uint8List.fromList(image.encodePng(actual));
    final global = comparePngBytes(
      referencePng: referencePng,
      actualPng: actualPng,
      options: const PixelMatchOptions(
        includeAntiAlias: true,
        foregroundBackground: PixelColor(231, 237, 243),
      ),
    );
    final focused = comparePngBytes(
      referencePng: referencePng,
      actualPng: actualPng,
      options: const PixelMatchOptions(
        includeAntiAlias: true,
        foregroundBackground: PixelColor(231, 237, 243),
        foregroundRegion: NormalizedPixelRegion(
          left: 0.75,
          top: 0.75,
          right: 0.90,
          bottom: 0.90,
          label: 'small fixture',
        ),
      ),
    );

    expect(global.similarity, greaterThan(0.99));
    expect(global.foreground!.similarity, greaterThan(0.95));
    expect(focused.foreground!.similarity, 0);
  });

  test('color presence counts only the target color inside the region', () {
    final target = _solidImage(100, 100, red: 231, green: 237, blue: 243);
    _fillRect(
      target,
      left: 20,
      top: 20,
      size: 10,
      red: 250,
      green: 204,
      blue: 21,
    );
    _fillRect(
      target,
      left: 70,
      top: 70,
      size: 20,
      red: 250,
      green: 204,
      blue: 21,
    );

    final result = analyzeColorPresencePngBytes(
      png: Uint8List.fromList(image.encodePng(target)),
      targetColor: const PixelColor(250, 204, 21),
      region: const NormalizedPixelRegion(
        left: 0.1,
        top: 0.1,
        right: 0.4,
        bottom: 0.4,
        label: 'target fixture',
      ),
    );

    expect(result.pixelCount, 100);
    expect(result.region.label, 'target fixture');
  });

  test('color orientation ignores translation and catches reversed text', () {
    final reference = _solidImage(400, 400, red: 231, green: 237, blue: 243);
    final translated = image.Image.from(reference);
    final reversed = image.Image.from(reference);
    final glyphColor = image.ColorRgb8(2, 132, 199);
    image.drawLine(
      reference,
      x1: 280,
      y1: 280,
      x2: 292,
      y2: 350,
      color: glyphColor,
      thickness: 10,
    );
    image.drawLine(
      reference,
      x1: 292,
      y1: 350,
      x2: 350,
      y2: 335,
      color: glyphColor,
      thickness: 10,
    );
    image.drawLine(
      translated,
      x1: 310,
      y1: 270,
      x2: 322,
      y2: 340,
      color: glyphColor,
      thickness: 10,
    );
    image.drawLine(
      translated,
      x1: 322,
      y1: 340,
      x2: 380,
      y2: 325,
      color: glyphColor,
      thickness: 10,
    );
    image.drawLine(
      reversed,
      x1: 310,
      y1: 270,
      x2: 350,
      y2: 330,
      color: glyphColor,
      thickness: 10,
    );
    image.drawLine(
      reversed,
      x1: 350,
      y1: 330,
      x2: 382,
      y2: 280,
      color: glyphColor,
      thickness: 10,
    );
    const region = NormalizedPixelRegion(
      left: 0.55,
      top: 0.60,
      right: 0.99,
      bottom: 0.95,
      label: 'single-glyph map-aligned line text',
    );
    final referencePng = Uint8List.fromList(image.encodePng(reference));
    final translatedResult = compareColorOrientationPngBytes(
      referencePng: referencePng,
      actualPng: Uint8List.fromList(image.encodePng(translated)),
      targetColor: const PixelColor(2, 132, 199),
      region: region,
    );
    final reversedResult = compareColorOrientationPngBytes(
      referencePng: referencePng,
      actualPng: Uint8List.fromList(image.encodePng(reversed)),
      targetColor: const PixelColor(2, 132, 199),
      region: region,
    );
    final missingResult = compareColorOrientationPngBytes(
      referencePng: referencePng,
      actualPng: _solidPng(400, 400, red: 231, green: 237, blue: 243),
      targetColor: const PixelColor(2, 132, 199),
      region: region,
    );

    expect(translatedResult.similarity, closeTo(1, 0.000001));
    expect(translatedResult.orientationDifferenceRadians, closeTo(0, 1e-9));
    expect(reversedResult.similarity, lessThan(0.85));
    expect(reversedResult.orientationDifferenceRadians, greaterThan(0.25));
    expect(reversedResult.toJson()['region'], region.toJson());
    expect(missingResult.actualPixelCount, 0);
    expect(missingResult.similarity, 0);
  });

  test('an actual-only antialiased seam remains a mismatch', () {
    final reference = _solidImage(9, 9, red: 255, green: 255, blue: 255);
    final actual = image.Image.from(reference);
    for (var y = 0; y < actual.height; y++) {
      actual.setPixelRgba(2, y, 200, 200, 200, 255);
      actual.setPixelRgba(3, y, 80, 80, 80, 255);
      actual.setPixelRgba(4, y, 200, 200, 200, 255);
    }

    final result = comparePngBytes(
      referencePng: Uint8List.fromList(image.encodePng(reference)),
      actualPng: Uint8List.fromList(image.encodePng(actual)),
    );

    expect(result.antiAliasedPixelCount, 0);
    expect(result.mismatchPixelCount, 27);
    expect(result.strictSimilarity, result.similarity);
  });

  test('different antialiasing on a shared edge is excluded', () {
    final reference = image.Image(width: 9, height: 9);
    final actual = image.Image(width: 9, height: 9);
    for (var y = 0; y < 9; y++) {
      for (var x = 0; x < 9; x++) {
        final referenceShade = x < 4 ? 0 : (x == 4 ? 120 : 255);
        final actualShade = x < 4 ? 0 : (x == 4 ? 170 : 255);
        reference.setPixelRgba(
          x,
          y,
          referenceShade,
          referenceShade,
          referenceShade,
          255,
        );
        actual.setPixelRgba(x, y, actualShade, actualShade, actualShade, 255);
      }
    }

    final result = comparePngBytes(
      referencePng: Uint8List.fromList(image.encodePng(reference)),
      actualPng: Uint8List.fromList(image.encodePng(actual)),
    );

    expect(result.antiAliasedPixelCount, 9);
    expect(result.mismatchPixelCount, 0);
    expect(result.strictSimilarity, closeTo(8 / 9, 0.000001));
    expect(result.similarity, 1);
  });

  test('mask excludes pixels from comparison', () {
    final reference = _solidImage(4, 4, red: 0, green: 0, blue: 0);
    final actual = image.Image.from(reference);
    actual.setPixelRgba(3, 3, 255, 255, 255, 255);

    final result = comparePngBytes(
      referencePng: Uint8List.fromList(image.encodePng(reference)),
      actualPng: Uint8List.fromList(image.encodePng(actual)),
      options: const PixelMatchOptions(
        includeAntiAlias: true,
        masks: <PixelMask>[
          PixelMask(left: 3, top: 3, width: 1, height: 1, label: 'test'),
        ],
      ),
    );

    expect(result.maskedPixelCount, 1);
    expect(result.comparedPixelCount, 15);
    expect(result.similarity, 1);
  });

  test('dimension mismatch throws', () {
    expect(
      () => comparePngBytes(
        referencePng: _solidPng(2, 2, red: 0, green: 0, blue: 0),
        actualPng: _solidPng(3, 2, red: 0, green: 0, blue: 0),
      ),
      throwsArgumentError,
    );
  });

  test('normalizes a uniformly scaled reference to the actual size', () {
    final normalized = normalizeReferencePngSize(
      referencePng: _solidPng(4, 4, red: 20, green: 40, blue: 60),
      actualPng: _solidPng(2, 2, red: 20, green: 40, blue: 60),
    );

    final result = comparePngBytes(
      referencePng: normalized,
      actualPng: _solidPng(2, 2, red: 20, green: 40, blue: 60),
    );
    expect(result.similarity, 1);
  });

  test('rejects a non-uniform reference scale', () {
    expect(
      () => normalizeReferencePngSize(
        referencePng: _solidPng(4, 4, red: 0, green: 0, blue: 0),
        actualPng: _solidPng(2, 4, red: 0, green: 0, blue: 0),
      ),
      throwsArgumentError,
    );
  });

  test('content ratio counts pixels distinct from the scene background', () {
    final screenshot = _solidImage(2, 2, red: 231, green: 237, blue: 243)
      ..setPixelRgba(1, 1, 100, 120, 140, 255);

    final ratio = pngContentRatio(
      png: Uint8List.fromList(image.encodePng(screenshot)),
      backgroundRed: 231,
      backgroundGreen: 237,
      backgroundBlue: 243,
    );

    expect(ratio, 0.25);
  });

  test('desktop smoke metrics reject a uniform transparent capture', () {
    final transparent = image.Image(width: 4, height: 3);
    final metrics = analyzePngSmoke(
      png: Uint8List.fromList(image.encodePng(transparent)),
      backgroundRed: 231,
      backgroundGreen: 237,
      backgroundBlue: 243,
    );

    expect(metrics.maximumChannelRange, 0);
    expect(
      metrics.passes(
        expectedWidth: 4,
        expectedHeight: 3,
        minimumContentRatio: 0.01,
        minimumChannelRange: 16,
      ),
      isFalse,
    );
  });

  test('desktop smoke metrics require fixed dimensions and color range', () {
    final screenshot = _solidImage(4, 3, red: 231, green: 237, blue: 243)
      ..setPixelRgba(1, 1, 80, 120, 160, 255);
    final metrics = analyzePngSmoke(
      png: Uint8List.fromList(image.encodePng(screenshot)),
      backgroundRed: 231,
      backgroundGreen: 237,
      backgroundBlue: 243,
    );

    expect(metrics.contentRatio, closeTo(1 / 12, 1e-9));
    expect(metrics.maximumChannelRange, greaterThanOrEqualTo(16));
    expect(
      metrics.passes(
        expectedWidth: 4,
        expectedHeight: 3,
        minimumContentRatio: 0.01,
        minimumChannelRange: 16,
      ),
      isTrue,
    );
    expect(
      metrics.passes(
        expectedWidth: 8,
        expectedHeight: 6,
        minimumContentRatio: 0.01,
        minimumChannelRange: 16,
      ),
      isFalse,
    );
  });
}

Uint8List _solidPng(
  int width,
  int height, {
  required int red,
  required int green,
  required int blue,
}) {
  return Uint8List.fromList(
    image.encodePng(
      _solidImage(width, height, red: red, green: green, blue: blue),
    ),
  );
}

image.Image _solidImage(
  int width,
  int height, {
  required int red,
  required int green,
  required int blue,
}) {
  final result = image.Image(width: width, height: height);
  for (final pixel in result) {
    pixel.setRgba(red, green, blue, 255);
  }
  return result;
}

void _fillRect(
  image.Image target, {
  required int left,
  required int top,
  required int size,
  required int red,
  required int green,
  required int blue,
}) {
  for (var y = top; y < top + size; y++) {
    for (var x = left; x < left + size; x++) {
      target.setPixelRgba(x, y, red, green, blue, 255);
    }
  }
}
