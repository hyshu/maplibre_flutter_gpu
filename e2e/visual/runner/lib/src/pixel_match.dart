// Pixel comparison and anti-alias detection are adapted from pixelmatch-cpp.
// Copyright (c) 2015, Mapbox. Distributed under the ISC license.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

part 'pixel_match/comparison_types.dart';
part 'pixel_match/content_metrics.dart';
part 'pixel_match/image_pixels.dart';

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
      .convert(format: .uint8, numChannels: 4)
      .getBytes(order: .rgba);
  final actual = actualImage
      .convert(format: .uint8, numChannels: 4)
      .getBytes(order: .rgba);
  final diff = Uint8List(width * height * 4);
  final maxDelta = 35215 * options.colorThreshold * options.colorThreshold;
  final deltaHistogram = List.filled(256, 0);

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
    order: .rgba,
  );
  final p95 = _percentile(deltaHistogram, compared, 0.95);

  return .new(
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
        : .new(
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
