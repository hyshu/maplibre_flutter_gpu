// Pixel comparison and anti-alias detection are adapted from pixelmatch-cpp.
// Copyright (c) 2015, Mapbox. Distributed under the ISC license.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

class PixelMask {
  const PixelMask({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.label,
  });

  final int left;
  final int top;
  final int width;
  final int height;
  final String label;

  bool contains(int x, int y) {
    return x >= left && y >= top && x < left + width && y < top + height;
  }

  Map<String, Object> toJson() => <String, Object>{
    'left': left,
    'top': top,
    'width': width,
    'height': height,
    'label': label,
  };
}

class PixelMatchOptions {
  const PixelMatchOptions({
    this.colorThreshold = 0.05,
    this.includeAntiAlias = false,
    this.masks = const <PixelMask>[],
  }) : assert(colorThreshold >= 0 && colorThreshold <= 1);

  final double colorThreshold;
  final bool includeAntiAlias;
  final List<PixelMask> masks;
}

class PixelMatchResult {
  const PixelMatchResult({
    required this.width,
    required this.height,
    required this.comparedPixelCount,
    required this.maskedPixelCount,
    required this.exactMismatchPixelCount,
    required this.thresholdMismatchPixelCount,
    required this.antiAliasedPixelCount,
    required this.mismatchPixelCount,
    required this.meanAbsoluteChannelDelta,
    required this.p95MaxChannelDelta,
    required this.diffPng,
    required this.options,
  });

  final int width;
  final int height;
  final int comparedPixelCount;
  final int maskedPixelCount;
  final int exactMismatchPixelCount;
  final int thresholdMismatchPixelCount;
  final int antiAliasedPixelCount;
  final int mismatchPixelCount;
  final double meanAbsoluteChannelDelta;
  final int p95MaxChannelDelta;
  final Uint8List diffPng;
  final PixelMatchOptions options;

  int get totalPixelCount => width * height;

  double get similarity {
    if (comparedPixelCount == 0) return 1;

    return 1 - mismatchPixelCount / comparedPixelCount;
  }

  double get strictSimilarity {
    if (comparedPixelCount == 0) return 1;

    return 1 - thresholdMismatchPixelCount / comparedPixelCount;
  }

  double get exactSimilarity {
    if (comparedPixelCount == 0) return 1;

    return 1 - exactMismatchPixelCount / comparedPixelCount;
  }

  Map<String, Object> toJson() => <String, Object>{
    'width': width,
    'height': height,
    'totalPixelCount': totalPixelCount,
    'comparedPixelCount': comparedPixelCount,
    'maskedPixelCount': maskedPixelCount,
    'exactMismatchPixelCount': exactMismatchPixelCount,
    'thresholdMismatchPixelCount': thresholdMismatchPixelCount,
    'antiAliasedPixelCount': antiAliasedPixelCount,
    'mismatchPixelCount': mismatchPixelCount,
    'similarity': similarity,
    'antiAliasAdjustedSimilarity': similarity,
    'strictSimilarity': strictSimilarity,
    'exactSimilarity': exactSimilarity,
    'meanAbsoluteChannelDelta': meanAbsoluteChannelDelta,
    'p95MaxChannelDelta': p95MaxChannelDelta,
    'colorThreshold': options.colorThreshold,
    'includeAntiAlias': options.includeAntiAlias,
    'masks': options.masks.map((mask) => mask.toJson()).toList(),
  };
}

/// Structural metrics used to reject missing or uniform desktop captures.
final class PngSmokeMetrics {
  /// Creates metrics for one decoded PNG.
  const PngSmokeMetrics({
    required this.width,
    required this.height,
    required this.contentPixels,
    required this.totalPixels,
    required this.maximumChannelRange,
  });

  /// PNG width in pixels.
  final int width;

  /// PNG height in pixels.
  final int height;

  /// Pixels distinct from the expected scene background.
  final int contentPixels;

  /// Total decoded pixels.
  final int totalPixels;

  /// Largest observed range among the red, green, and blue channels.
  final int maximumChannelRange;

  /// Fraction of pixels distinct from the expected scene background.
  double get contentRatio => contentPixels / totalPixels;

  /// Whether the capture has the required size, content, and color range.
  bool passes({
    required int expectedWidth,
    required int expectedHeight,
    required double minimumContentRatio,
    required int minimumChannelRange,
  }) =>
      width == expectedWidth &&
      height == expectedHeight &&
      contentRatio >= minimumContentRatio &&
      maximumChannelRange >= minimumChannelRange;
}

/// Measures PNG dimensions, rendered content, and RGB channel range.
PngSmokeMetrics analyzePngSmoke({
  required Uint8List png,
  required int backgroundRed,
  required int backgroundGreen,
  required int backgroundBlue,
  int channelThreshold = 8,
}) {
  final decoded = image.decodePng(png);
  if (decoded == null) {
    throw const FormatException('image is not a valid PNG');
  }
  final bytes = decoded
      .convert(format: image.Format.uint8, numChannels: 4)
      .getBytes(order: image.ChannelOrder.rgba);
  var contentPixels = 0;
  var minimumRed = 255;
  var minimumGreen = 255;
  var minimumBlue = 255;
  var maximumRed = 0;
  var maximumGreen = 0;
  var maximumBlue = 0;
  for (var position = 0; position < bytes.length; position += 4) {
    final rgb = _compositedRgb(bytes, position);
    minimumRed = math.min(minimumRed, rgb.$1);
    minimumGreen = math.min(minimumGreen, rgb.$2);
    minimumBlue = math.min(minimumBlue, rgb.$3);
    maximumRed = math.max(maximumRed, rgb.$1);
    maximumGreen = math.max(maximumGreen, rgb.$2);
    maximumBlue = math.max(maximumBlue, rgb.$3);
    final maxDelta = math.max(
      (rgb.$1 - backgroundRed).abs(),
      math.max(
        (rgb.$2 - backgroundGreen).abs(),
        (rgb.$3 - backgroundBlue).abs(),
      ),
    );
    if (maxDelta > channelThreshold) contentPixels++;
  }
  final maximumChannelRange = math.max(
    maximumRed - minimumRed,
    math.max(maximumGreen - minimumGreen, maximumBlue - minimumBlue),
  );

  return PngSmokeMetrics(
    width: decoded.width,
    height: decoded.height,
    contentPixels: contentPixels,
    totalPixels: decoded.width * decoded.height,
    maximumChannelRange: maximumChannelRange,
  );
}

double pngContentRatio({
  required Uint8List png,
  required int backgroundRed,
  required int backgroundGreen,
  required int backgroundBlue,
  int channelThreshold = 8,
}) {
  return analyzePngSmoke(
    png: png,
    backgroundRed: backgroundRed,
    backgroundGreen: backgroundGreen,
    backgroundBlue: backgroundBlue,
    channelThreshold: channelThreshold,
  ).contentRatio;
}

PixelMatchResult comparePngBytes({
  required Uint8List referencePng,
  required Uint8List actualPng,
  PixelMatchOptions options = const PixelMatchOptions(),
}) {
  final referenceImage = image.decodePng(referencePng);
  final actualImage = image.decodePng(actualPng);
  if (referenceImage == null) {
    throw const FormatException('reference image is not a valid PNG');
  }
  if (actualImage == null) {
    throw const FormatException('actual image is not a valid PNG');
  }
  if (referenceImage.width != actualImage.width ||
      referenceImage.height != actualImage.height) {
    throw ArgumentError(
      'image dimensions differ: '
      'reference=${referenceImage.width}x${referenceImage.height}, '
      'actual=${actualImage.width}x${actualImage.height}',
    );
  }

  final width = referenceImage.width;
  final height = referenceImage.height;
  final reference = referenceImage
      .convert(format: image.Format.uint8, numChannels: 4)
      .getBytes(order: image.ChannelOrder.rgba);
  final actual = actualImage
      .convert(format: image.Format.uint8, numChannels: 4)
      .getBytes(order: image.ChannelOrder.rgba);
  final diff = Uint8List(width * height * 4);
  final maxDelta = 35215 * options.colorThreshold * options.colorThreshold;
  final deltaHistogram = List<int>.filled(256, 0);

  var compared = 0;
  var masked = 0;
  var exactMismatch = 0;
  var thresholdMismatch = 0;
  var antiAliased = 0;
  var mismatch = 0;
  var absoluteChannelDelta = 0.0;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final position = (y * width + x) * 4;
      if (_isMasked(options.masks, x, y)) {
        masked++;
        final stripe = ((x + y) ~/ 8).isEven;
        _drawPixel(
          diff,
          position,
          stripe ? 75 : 100,
          stripe ? 91 : 116,
          stripe ? 115 : 140,
        );
        continue;
      }

      compared++;
      final referenceRgb = _compositedRgb(reference, position);
      final actualRgb = _compositedRgb(actual, position);
      final redDelta = (referenceRgb.$1 - actualRgb.$1).abs();
      final greenDelta = (referenceRgb.$2 - actualRgb.$2).abs();
      final blueDelta = (referenceRgb.$3 - actualRgb.$3).abs();
      final maxChannelDelta = math.max(
        redDelta,
        math.max(greenDelta, blueDelta),
      );
      deltaHistogram[maxChannelDelta]++;
      absoluteChannelDelta += (redDelta + greenDelta + blueDelta) / 3;
      if (maxChannelDelta != 0) exactMismatch++;

      final delta = _colorDelta(reference, actual, position, position);
      if (delta > maxDelta) {
        thresholdMismatch++;
        final isAntiAliased =
            !options.includeAntiAlias &&
            (_antialiased(reference, x, y, width, height, actual) ||
                _antialiased(actual, x, y, width, height, reference)) &&
            _hasLocalContrast(reference, x, y, width, height, maxDelta) &&
            _hasLocalContrast(actual, x, y, width, height, maxDelta);
        if (isAntiAliased) {
          antiAliased++;
          _drawPixel(diff, position, 37, 99, 235);
        } else {
          mismatch++;
          _drawPixel(diff, position, 230, 45, 62);
        }
      } else {
        final gray = _blend(_grayPixel(reference, position), 0.1);
        _drawPixel(diff, position, gray, gray, gray);
      }
    }
  }

  final diffImage = image.Image.fromBytes(
    width: width,
    height: height,
    bytes: diff.buffer,
    order: image.ChannelOrder.rgba,
  );
  final p95 = _percentile(deltaHistogram, compared, 0.95);

  return PixelMatchResult(
    width: width,
    height: height,
    comparedPixelCount: compared,
    maskedPixelCount: masked,
    exactMismatchPixelCount: exactMismatch,
    thresholdMismatchPixelCount: thresholdMismatch,
    antiAliasedPixelCount: antiAliased,
    mismatchPixelCount: mismatch,
    meanAbsoluteChannelDelta: compared == 0
        ? 0
        : absoluteChannelDelta / compared,
    p95MaxChannelDelta: p95,
    diffPng: Uint8List.fromList(image.encodePng(diffImage)),
    options: options,
  );
}

Uint8List normalizeReferencePngSize({
  required Uint8List referencePng,
  required Uint8List actualPng,
}) {
  final reference = image.decodePng(referencePng);
  final actual = image.decodePng(actualPng);
  if (reference == null) {
    throw const FormatException('reference image is not a valid PNG');
  }
  if (actual == null) {
    throw const FormatException('actual image is not a valid PNG');
  }
  if (reference.width == actual.width && reference.height == actual.height) {
    return referencePng;
  }

  final widthScale = reference.width / actual.width;
  final heightScale = reference.height / actual.height;
  if (widthScale != heightScale ||
      widthScale < 1 ||
      widthScale != widthScale.roundToDouble()) {
    throw ArgumentError(
      'image dimensions differ by a non-uniform display scale: '
      'reference=${reference.width}x${reference.height}, '
      'actual=${actual.width}x${actual.height}',
    );
  }
  return Uint8List.fromList(
    image.encodePng(
      image.copyResize(
        reference,
        width: actual.width,
        height: actual.height,
        interpolation: image.Interpolation.average,
      ),
    ),
  );
}

bool _hasLocalContrast(
  Uint8List bytes,
  int centerX,
  int centerY,
  int width,
  int height,
  double minimumDelta,
) {
  final centerPosition = (centerY * width + centerX) * 4;
  final startX = math.max(0, centerX - 1);
  final startY = math.max(0, centerY - 1);
  final endX = math.min(width - 1, centerX + 1);
  final endY = math.min(height - 1, centerY + 1);

  for (var y = startY; y <= endY; y++) {
    for (var x = startX; x <= endX; x++) {
      if (x == centerX && y == centerY) continue;
      if (_colorDelta(bytes, bytes, centerPosition, (y * width + x) * 4) >
          minimumDelta) {
        return true;
      }
    }
  }
  return false;
}

bool _isMasked(List<PixelMask> masks, int x, int y) {
  for (final mask in masks) {
    if (mask.contains(x, y)) return true;
  }
  return false;
}

int _percentile(List<int> histogram, int count, double percentile) {
  if (count == 0) return 0;
  final target = (count * percentile).ceil();
  var seen = 0;
  for (var value = 0; value < histogram.length; value++) {
    seen += histogram[value];
    if (seen >= target) return value;
  }
  return histogram.length - 1;
}

(int, int, int) _compositedRgb(Uint8List bytes, int position) {
  final alpha = bytes[position + 3] / 255;

  return (
    _blend(bytes[position], alpha),
    _blend(bytes[position + 1], alpha),
    _blend(bytes[position + 2], alpha),
  );
}

int _blend(num color, double alpha) {
  final value = (255 + (color - 255) * alpha).toInt();

  return math.max(0, math.min(255, value));
}

double _rgbToY(num red, num green, num blue) {
  return red * 0.29889531 + green * 0.58662247 + blue * 0.11448223;
}

double _rgbToI(num red, num green, num blue) {
  return red * 0.59597799 - green * 0.27417610 - blue * 0.32180189;
}

double _rgbToQ(num red, num green, num blue) {
  return red * 0.21147017 - green * 0.52261711 + blue * 0.31114694;
}

double _colorDelta(
  Uint8List first,
  Uint8List second,
  int firstPosition,
  int secondPosition,
) {
  final firstRgb = _compositedRgb(first, firstPosition);
  final secondRgb = _compositedRgb(second, secondPosition);
  final y =
      _rgbToY(firstRgb.$1, firstRgb.$2, firstRgb.$3) -
      _rgbToY(secondRgb.$1, secondRgb.$2, secondRgb.$3);
  final i =
      _rgbToI(firstRgb.$1, firstRgb.$2, firstRgb.$3) -
      _rgbToI(secondRgb.$1, secondRgb.$2, secondRgb.$3);
  final q =
      _rgbToQ(firstRgb.$1, firstRgb.$2, firstRgb.$3) -
      _rgbToQ(secondRgb.$1, secondRgb.$2, secondRgb.$3);

  return 0.5053 * y * y + 0.299 * i * i + 0.1957 * q * q;
}

double _brightnessDelta(Uint8List image, int first, int second) {
  final firstRgb = _compositedRgb(image, first);
  final secondRgb = _compositedRgb(image, second);

  return _rgbToY(firstRgb.$1, firstRgb.$2, firstRgb.$3) -
      _rgbToY(secondRgb.$1, secondRgb.$2, secondRgb.$3);
}

int _grayPixel(Uint8List bytes, int position) {
  final rgb = _compositedRgb(bytes, position);
  final value = _rgbToY(rgb.$1, rgb.$2, rgb.$3).toInt();

  return math.max(0, math.min(255, value));
}

void _drawPixel(Uint8List output, int position, int red, int green, int blue) {
  output[position] = red;
  output[position + 1] = green;
  output[position + 2] = blue;
  output[position + 3] = 255;
}

bool _antialiased(
  Uint8List imageBytes,
  int centerX,
  int centerY,
  int width,
  int height, [
  Uint8List? otherImage,
]) {
  final startX = centerX > 0 ? centerX - 1 : 0;
  final startY = centerY > 0 ? centerY - 1 : 0;
  final endX = math.min(centerX + 1, width - 1);
  final endY = math.min(centerY + 1, height - 1);
  final centerPosition = (centerY * width + centerX) * 4;
  var zeroes = 0;
  var positives = 0;
  var negatives = 0;
  var minimum = 0.0;
  var maximum = 0.0;
  var minimumX = 0;
  var minimumY = 0;
  var maximumX = 0;
  var maximumY = 0;

  for (var x = startX; x <= endX; x++) {
    for (var y = startY; y <= endY; y++) {
      if (x == centerX && y == centerY) continue;
      final delta = _brightnessDelta(
        imageBytes,
        centerPosition,
        (y * width + x) * 4,
      );
      if (delta == 0) {
        zeroes++;
      } else if (delta < 0) {
        negatives++;
      } else {
        positives++;
      }
      if (zeroes > 2) return false;
      if (otherImage == null) continue;

      if (delta < minimum) {
        minimum = delta;
        minimumX = x;
        minimumY = y;
      }
      if (delta > maximum) {
        maximum = delta;
        maximumX = x;
        maximumY = y;
      }
    }
  }

  if (otherImage == null) return true;
  if (negatives == 0 || positives == 0) return false;

  return (!_antialiased(imageBytes, minimumX, minimumY, width, height) &&
          !_antialiased(otherImage, minimumX, minimumY, width, height)) ||
      (!_antialiased(imageBytes, maximumX, maximumY, width, height) &&
          !_antialiased(otherImage, maximumX, maximumY, width, height));
}
