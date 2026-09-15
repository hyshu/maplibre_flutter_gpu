// Pixel comparison and anti-alias detection are adapted from pixelmatch-cpp.
// Copyright (c) 2015, Mapbox. Distributed under the ISC license.

part of '../pixel_match.dart';

bool _matchesColor(
  (int, int, int) color,
  PixelColor target,
  int channelThreshold,
) =>
    math.max(
      (color.$1 - target.red).abs(),
      math.max((color.$2 - target.green).abs(), (color.$3 - target.blue).abs()),
    ) <=
    channelThreshold;

bool _isForeground(
  (int, int, int) color,
  PixelColor background,
  int channelThreshold,
) => !_matchesColor(color, background, channelThreshold);

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
        interpolation: .average,
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

int _blend(num color, double alpha) =>
    math.max(0, math.min(255, (255 + (color - 255) * alpha).toInt()));

double _rgbToY(num red, num green, num blue) =>
    red * 0.29889531 + green * 0.58662247 + blue * 0.11448223;

double _rgbToI(num red, num green, num blue) =>
    red * 0.59597799 - green * 0.27417610 - blue * 0.32180189;

double _rgbToQ(num red, num green, num blue) =>
    red * 0.21147017 - green * 0.52261711 + blue * 0.31114694;

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
