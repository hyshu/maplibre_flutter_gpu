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
