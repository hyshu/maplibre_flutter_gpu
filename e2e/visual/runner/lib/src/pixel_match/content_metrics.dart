part of '../pixel_match.dart';

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
      .convert(format: .uint8, numChannels: 4)
      .getBytes(order: .rgba);
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

  return .new(
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
}) => analyzePngSmoke(
  png: png,
  backgroundRed: backgroundRed,
  backgroundGreen: backgroundGreen,
  backgroundBlue: backgroundBlue,
  channelThreshold: channelThreshold,
).contentRatio;

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
      .convert(format: .uint8, numChannels: 4)
      .getBytes(order: .rgba);
  final actual = actualImage
      .convert(format: .uint8, numChannels: 4)
      .getBytes(order: .rgba);
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

  return .new(
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
      .convert(format: .uint8, numChannels: 4)
      .getBytes(order: .rgba);
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

  return .new(
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

    return .new(
      orientationRadians:
          0.5 * math.atan2(2 * covarianceXY, covarianceXX - covarianceYY),
      elongation: largestEigenvalue / math.max(smallestEigenvalue, 1e-9),
    );
  }
}

final class _PrincipalAxis {
  const new({required this.orientationRadians, required this.elongation});

  final double orientationRadians;
  final double elongation;
}
