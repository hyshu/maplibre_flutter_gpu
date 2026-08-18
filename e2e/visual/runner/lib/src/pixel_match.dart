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

class PixelColor {
  const PixelColor(this.red, this.green, this.blue)
    : assert(red >= 0 && red <= 255),
      assert(green >= 0 && green <= 255),
      assert(blue >= 0 && blue <= 255);

  final int red;
  final int green;
  final int blue;

  Map<String, int> toJson() => <String, int>{
    'red': red,
    'green': green,
    'blue': blue,
  };
}

/// A display-size-independent region used for focused pixel metrics.
class NormalizedPixelRegion {
  /// Creates a region using fractions of the image width and height.
  const NormalizedPixelRegion({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.label,
  }) : assert(left >= 0 && left < right),
       assert(top >= 0 && top < bottom),
       assert(right <= 1),
       assert(bottom <= 1);

  /// Left edge as a fraction of image width.
  final double left;

  /// Top edge as a fraction of image height.
  final double top;

  /// Exclusive right edge as a fraction of image width.
  final double right;

  /// Exclusive bottom edge as a fraction of image height.
  final double bottom;

  /// Human-readable purpose of this region.
  final String label;

  /// Whether a pixel lies inside this region for the given image size.
  bool contains(int x, int y, int width, int height) {
    return x >= (left * width).floor() &&
        x < (right * width).ceil() &&
        y >= (top * height).floor() &&
        y < (bottom * height).ceil();
  }

  /// Serializes this region for the visual report.
  Map<String, Object> toJson() => <String, Object>{
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'label': label,
  };
}

class PixelMatchOptions {
  const PixelMatchOptions({
    this.colorThreshold = 0.05,
    this.includeAntiAlias = false,
    this.masks = const <PixelMask>[],
    this.foregroundBackground,
    this.foregroundChannelThreshold = 8,
    this.foregroundRegion,
  }) : assert(colorThreshold >= 0 && colorThreshold <= 1),
       assert(
         foregroundChannelThreshold >= 0 && foregroundChannelThreshold <= 255,
       );

  final double colorThreshold;
  final bool includeAntiAlias;
  final List<PixelMask> masks;
  final PixelColor? foregroundBackground;
  final int foregroundChannelThreshold;
  final NormalizedPixelRegion? foregroundRegion;
}

class ForegroundMatchResult {
  const ForegroundMatchResult({
    required this.background,
    required this.channelThreshold,
    required this.referencePixelCount,
    required this.actualPixelCount,
    required this.intersectionPixelCount,
    required this.unionPixelCount,
    required this.mismatchPixelCount,
    this.region,
  });

  final PixelColor background;
  final int channelThreshold;
  final int referencePixelCount;
  final int actualPixelCount;
  final int intersectionPixelCount;
  final int unionPixelCount;
  final int mismatchPixelCount;
  final NormalizedPixelRegion? region;

  double get similarity {
    if (unionPixelCount == 0) return 1;

    return 1 - mismatchPixelCount / unionPixelCount;
  }

  double get intersectionOverUnion {
    if (unionPixelCount == 0) return 1;

    return intersectionPixelCount / unionPixelCount;
  }

  Map<String, Object> toJson() => <String, Object>{
    'background': background.toJson(),
    'channelThreshold': channelThreshold,
    'referencePixelCount': referencePixelCount,
    'actualPixelCount': actualPixelCount,
    'intersectionPixelCount': intersectionPixelCount,
    'unionPixelCount': unionPixelCount,
    'mismatchPixelCount': mismatchPixelCount,
    'similarity': similarity,
    'intersectionOverUnion': intersectionOverUnion,
    if (region != null) 'region': region!.toJson(),
  };
}

/// Compares the dominant axis of a color-isolated shape in two PNGs.
///
/// The orientation is independent of the shape's position. This makes the
/// metric suitable for fixtures whose placement can differ between renderer
/// generations while their rotation must remain equivalent.
final class ColorOrientationMatchResult {
  /// Creates the result of a color-isolated orientation comparison.
  const ColorOrientationMatchResult({
    required this.targetColor,
    required this.channelThreshold,
    required this.region,
    required this.minimumPixelCount,
    required this.minimumElongation,
    required this.referencePixelCount,
    required this.actualPixelCount,
    required this.referenceOrientationRadians,
    required this.actualOrientationRadians,
    required this.referenceElongation,
    required this.actualElongation,
  });

  /// Color used to isolate the compared shape.
  final PixelColor targetColor;

  /// Maximum per-channel distance from [targetColor].
  final int channelThreshold;

  /// Region in which matching pixels were measured.
  final NormalizedPixelRegion region;

  /// Minimum number of matching pixels required in each image.
  final int minimumPixelCount;

  /// Minimum principal-axis ratio required for a stable orientation.
  final double minimumElongation;

  /// Number of matching pixels in the reference image.
  final int referencePixelCount;

  /// Number of matching pixels in the actual image.
  final int actualPixelCount;

  /// Undirected principal-axis orientation in the reference image.
  final double? referenceOrientationRadians;

  /// Undirected principal-axis orientation in the actual image.
  final double? actualOrientationRadians;

  /// Principal-axis ratio in the reference image.
  final double? referenceElongation;

  /// Principal-axis ratio in the actual image.
  final double? actualElongation;

  /// Smallest difference between the two undirected axes.
  double? get orientationDifferenceRadians {
    final reference = referenceOrientationRadians;
    final actual = actualOrientationRadians;
    if (reference == null || actual == null) return null;

    final rawDifference = (reference - actual).abs();

    return math.min(rawDifference, math.pi - rawDifference);
  }

  /// Similarity derived from the axis difference, where 90 degrees is zero.
  double get similarity {
    if (referencePixelCount < minimumPixelCount ||
        actualPixelCount < minimumPixelCount ||
        (referenceElongation ?? 0) < minimumElongation ||
        (actualElongation ?? 0) < minimumElongation) {
      return 0;
    }
    final difference = orientationDifferenceRadians;
    if (difference == null) return 0;

    return (1 - difference / (math.pi / 2)).clamp(0, 1).toDouble();
  }

  /// Serializes the orientation metric for the visual report.
  Map<String, Object> toJson() => <String, Object>{
    'targetColor': targetColor.toJson(),
    'channelThreshold': channelThreshold,
    'region': region.toJson(),
    'minimumPixelCount': minimumPixelCount,
    'minimumElongation': minimumElongation,
    'referencePixelCount': referencePixelCount,
    'actualPixelCount': actualPixelCount,
    if (referenceOrientationRadians != null)
      'referenceOrientationDegrees':
          referenceOrientationRadians! * 180 / math.pi,
    if (actualOrientationRadians != null)
      'actualOrientationDegrees': actualOrientationRadians! * 180 / math.pi,
    if (orientationDifferenceRadians != null)
      'orientationDifferenceDegrees':
          orientationDifferenceRadians! * 180 / math.pi,
    'referenceElongation': ?referenceElongation,
    'actualElongation': ?actualElongation,
    'similarity': similarity,
  };
}

/// Color-isolated content measured inside one image region.
final class ColorPresenceResult {
  /// Creates a color-presence measurement.
  const ColorPresenceResult({
    required this.targetColor,
    required this.channelThreshold,
    required this.region,
    required this.pixelCount,
  });

  /// Color used to isolate the measured content.
  final PixelColor targetColor;

  /// Maximum per-channel distance from [targetColor].
  final int channelThreshold;

  /// Region in which matching pixels were measured.
  final NormalizedPixelRegion region;

  /// Number of pixels matching [targetColor].
  final int pixelCount;

  /// Serializes the color-presence measurement.
  Map<String, Object> toJson() => <String, Object>{
    'targetColor': targetColor.toJson(),
    'channelThreshold': channelThreshold,
    'region': region.toJson(),
    'pixelCount': pixelCount,
  };
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
    this.foreground,
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
  final ForegroundMatchResult? foreground;

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
    if (foreground != null) 'foreground': foreground!.toJson(),
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
  var referenceForeground = 0;
  var actualForeground = 0;
  var foregroundIntersection = 0;
  var foregroundUnion = 0;
  var foregroundMismatch = 0;

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
      var isMismatch = false;
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
          isMismatch = true;
          _drawPixel(diff, position, 230, 45, 62);
        }
      } else {
        final gray = _blend(_grayPixel(reference, position), 0.1);
        _drawPixel(diff, position, gray, gray, gray);
      }

      final foregroundBackground = options.foregroundBackground;
      final foregroundRegion = options.foregroundRegion;
      if (foregroundBackground != null &&
          (foregroundRegion == null ||
              foregroundRegion.contains(x, y, width, height))) {
        final referenceIsForeground = _isForeground(
          referenceRgb,
          foregroundBackground,
          options.foregroundChannelThreshold,
        );
        final actualIsForeground = _isForeground(
          actualRgb,
          foregroundBackground,
          options.foregroundChannelThreshold,
        );
        if (referenceIsForeground) referenceForeground++;
        if (actualIsForeground) actualForeground++;
        if (referenceIsForeground && actualIsForeground) {
          foregroundIntersection++;
        }
        if (referenceIsForeground || actualIsForeground) {
          foregroundUnion++;
          if (isMismatch) foregroundMismatch++;
        }
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
    foreground: options.foregroundBackground == null
        ? null
        : ForegroundMatchResult(
            background: options.foregroundBackground!,
            channelThreshold: options.foregroundChannelThreshold,
            referencePixelCount: referenceForeground,
            actualPixelCount: actualForeground,
            intersectionPixelCount: foregroundIntersection,
            unionPixelCount: foregroundUnion,
            mismatchPixelCount: foregroundMismatch,
            region: options.foregroundRegion,
          ),
  );
}

/// Compares color-isolated shape orientations without comparing placement.
ColorOrientationMatchResult compareColorOrientationPngBytes({
  required Uint8List referencePng,
  required Uint8List actualPng,
  required PixelColor targetColor,
  required NormalizedPixelRegion region,
  int channelThreshold = 16,
  int minimumPixelCount = 20,
  double minimumElongation = 1.5,
}) {
  if (channelThreshold < 0 || channelThreshold > 255) {
    throw ArgumentError.value(
      channelThreshold,
      'channelThreshold',
      'must be between 0 and 255',
    );
  }
  if (minimumPixelCount < 2) {
    throw ArgumentError.value(
      minimumPixelCount,
      'minimumPixelCount',
      'must be at least 2',
    );
  }
  if (minimumElongation <= 1) {
    throw ArgumentError.value(
      minimumElongation,
      'minimumElongation',
      'must be greater than 1',
    );
  }

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
  final referenceMoments = _ColorMoments();
  final actualMoments = _ColorMoments();

  for (
    var y = (region.top * height).floor();
    y < (region.bottom * height).ceil();
    y++
  ) {
    for (
      var x = (region.left * width).floor();
      x < (region.right * width).ceil();
      x++
    ) {
      final position = (y * width + x) * 4;
      if (_matchesColor(
        _compositedRgb(reference, position),
        targetColor,
        channelThreshold,
      )) {
        referenceMoments.add(x, y);
      }
      if (_matchesColor(
        _compositedRgb(actual, position),
        targetColor,
        channelThreshold,
      )) {
        actualMoments.add(x, y);
      }
    }
  }

  final referenceAxis = referenceMoments.principalAxis;
  final actualAxis = actualMoments.principalAxis;

  return ColorOrientationMatchResult(
    targetColor: targetColor,
    channelThreshold: channelThreshold,
    region: region,
    minimumPixelCount: minimumPixelCount,
    minimumElongation: minimumElongation,
    referencePixelCount: referenceMoments.count,
    actualPixelCount: actualMoments.count,
    referenceOrientationRadians: referenceAxis?.orientationRadians,
    actualOrientationRadians: actualAxis?.orientationRadians,
    referenceElongation: referenceAxis?.elongation,
    actualElongation: actualAxis?.elongation,
  );
}

/// Counts pixels near [targetColor] inside [region].
ColorPresenceResult analyzeColorPresencePngBytes({
  required Uint8List png,
  required PixelColor targetColor,
  required NormalizedPixelRegion region,
  int channelThreshold = 16,
}) {
  if (channelThreshold < 0 || channelThreshold > 255) {
    throw ArgumentError.value(
      channelThreshold,
      'channelThreshold',
      'must be between 0 and 255',
    );
  }
  final decoded = image.decodePng(png);
  if (decoded == null) throw const FormatException('image is not a valid PNG');
  final width = decoded.width;
  final height = decoded.height;
  final bytes = decoded
      .convert(format: image.Format.uint8, numChannels: 4)
      .getBytes(order: image.ChannelOrder.rgba);
  var pixelCount = 0;
  for (
    var y = (region.top * height).floor();
    y < (region.bottom * height).ceil();
    y++
  ) {
    for (
      var x = (region.left * width).floor();
      x < (region.right * width).ceil();
      x++
    ) {
      final position = (y * width + x) * 4;
      if (_matchesColor(
        _compositedRgb(bytes, position),
        targetColor,
        channelThreshold,
      )) {
        pixelCount++;
      }
    }
  }

  return ColorPresenceResult(
    targetColor: targetColor,
    channelThreshold: channelThreshold,
    region: region,
    pixelCount: pixelCount,
  );
}

final class _ColorMoments {
  var count = 0;
  var _sumX = 0.0;
  var _sumY = 0.0;
  var _sumXX = 0.0;
  var _sumYY = 0.0;
  var _sumXY = 0.0;

  void add(int x, int y) {
    count++;
    _sumX += x;
    _sumY += y;
    _sumXX += x * x;
    _sumYY += y * y;
    _sumXY += x * y;
  }

  _PrincipalAxis? get principalAxis {
    if (count < 2) return null;

    final meanX = _sumX / count;
    final meanY = _sumY / count;
    final covarianceXX = _sumXX / count - meanX * meanX;
    final covarianceYY = _sumYY / count - meanY * meanY;
    final covarianceXY = _sumXY / count - meanX * meanY;
    final discriminant = math.sqrt(
      math.pow(covarianceXX - covarianceYY, 2) +
          4 * covarianceXY * covarianceXY,
    );
    final largestEigenvalue = (covarianceXX + covarianceYY + discriminant) / 2;
    final smallestEigenvalue = (covarianceXX + covarianceYY - discriminant) / 2;
    if (largestEigenvalue <= 0) return null;

    return _PrincipalAxis(
      orientationRadians:
          0.5 * math.atan2(2 * covarianceXY, covarianceXX - covarianceYY),
      elongation: largestEigenvalue / math.max(smallestEigenvalue, 1e-9),
    );
  }
}

final class _PrincipalAxis {
  const _PrincipalAxis({
    required this.orientationRadians,
    required this.elongation,
  });

  final double orientationRadians;
  final double elongation;
}

bool _matchesColor(
  (int, int, int) color,
  PixelColor target,
  int channelThreshold,
) {
  return math.max(
        (color.$1 - target.red).abs(),
        math.max(
          (color.$2 - target.green).abs(),
          (color.$3 - target.blue).abs(),
        ),
      ) <=
      channelThreshold;
}

bool _isForeground(
  (int, int, int) color,
  PixelColor background,
  int channelThreshold,
) {
  return math.max(
        (color.$1 - background.red).abs(),
        math.max(
          (color.$2 - background.green).abs(),
          (color.$3 - background.blue).abs(),
        ),
      ) >
      channelThreshold;
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
