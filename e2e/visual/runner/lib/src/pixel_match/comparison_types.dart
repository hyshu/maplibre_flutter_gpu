part of '../pixel_match.dart';

class PixelMask {
  const new({
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

  bool contains(int x, int y) =>
      x >= left && y >= top && x < left + width && y < top + height;

  Map<String, Object> toJson() => {
    'left': left,
    'top': top,
    'width': width,
    'height': height,
    'label': label,
  };
}

class PixelColor {
  const new(this.red, this.green, this.blue)
    : assert(red >= 0 && red <= 255),
      assert(green >= 0 && green <= 255),
      assert(blue >= 0 && blue <= 255);

  final int red;
  final int green;
  final int blue;

  Map<String, int> toJson() => {'red': red, 'green': green, 'blue': blue};
}

/// A display-size-independent region used for focused pixel metrics.
class NormalizedPixelRegion {
  /// Creates a region using fractions of the image width and height.
  const new({
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
  bool contains(int x, int y, int width, int height) =>
      x >= (left * width).floor() &&
      x < (right * width).ceil() &&
      y >= (top * height).floor() &&
      y < (bottom * height).ceil();

  /// Serializes this region for the visual report.
  Map<String, Object> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'label': label,
  };
}

class PixelMatchOptions {
  const new({
    this.colorThreshold = 0.05,
    this.includeAntiAlias = false,
    this.masks = const [],
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
  const new({
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

  double get similarity =>
      unionPixelCount == 0 ? 1 : 1 - mismatchPixelCount / unionPixelCount;

  double get intersectionOverUnion =>
      unionPixelCount == 0 ? 1 : intersectionPixelCount / unionPixelCount;

  Map<String, Object> toJson() => {
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
  const new({
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
  Map<String, Object> toJson() => {
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
  const new({
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
  Map<String, Object> toJson() => {
    'targetColor': targetColor.toJson(),
    'channelThreshold': channelThreshold,
    'region': region.toJson(),
    'pixelCount': pixelCount,
  };
}

class PixelMatchResult {
  const new({
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

  double get similarity =>
      comparedPixelCount == 0 ? 1 : 1 - mismatchPixelCount / comparedPixelCount;

  double get strictSimilarity => comparedPixelCount == 0
      ? 1
      : 1 - thresholdMismatchPixelCount / comparedPixelCount;

  double get exactSimilarity => comparedPixelCount == 0
      ? 1
      : 1 - exactMismatchPixelCount / comparedPixelCount;

  Map<String, Object> toJson() => {
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
  const new({
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
