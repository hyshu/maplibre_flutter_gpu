part of 'sprite_atlas.dart';

/// Aspect-ratio constraint applied to an icon-text-fit content rectangle.
enum SpriteTextFit {
  /// The content may grow or shrink independently on this axis.
  stretchOrShrink,

  /// The content may grow but preserves its minimum fixed-pixel extent.
  stretchOnly,

  /// The other axis determines this axis from the content aspect ratio.
  proportional,
}

/// One icon in the sprite sheet.
class const SpriteIcon({
  /// Image containing this icon.
  required final ui.Image atlas,

  /// Horizontal offset of the icon in atlas pixels.
  required final double x,

  /// Vertical offset of the icon in atlas pixels.
  required final double y,

  /// Width of the icon in atlas pixels.
  required final double width,

  /// Height of the icon in atlas pixels.
  required final double height,

  /// Ratio between atlas pixels and logical pixels.
  required final double pixelRatio,

  /// Whether the icon contains signed distance field data.
  final bool sdf = false,

  /// Horizontal source ranges that may stretch for icon-text-fit.
  ///
  /// Values use pixels relative to this icon's source rectangle.
  final List<(double, double)> stretchX = const [],

  /// Vertical source ranges that may stretch for icon-text-fit.
  ///
  /// Values use pixels relative to this icon's source rectangle.
  final List<(double, double)> stretchY = const [],

  /// Source rectangle that icon-text-fit maps to the shaped text bounds.
  final Rect? content,

  /// Horizontal constraint applied before mapping [content].
  final SpriteTextFit? textFitWidth,

  /// Vertical constraint applied before mapping [content].
  final SpriteTextFit? textFitHeight,
}) {
  /// Logical display size after applying [pixelRatio].
  Size get displaySize => .new(width / pixelRatio, height / pixelRatio);

  /// Applies sprite-level proportional constraints to fitted content bounds.
  Size fittedContentSize(Size requested) {
    final contentRect = content;
    final widthFit = textFitWidth;
    final heightFit = textFitHeight;
    var result = requested;
    if (contentRect != null && widthFit != null && heightFit != null) {
      final contentAspectRatio = contentRect.width / contentRect.height;
      final requestedAspectRatio = requested.width / requested.height;
      if (heightFit == .proportional &&
          ((widthFit == .stretchOnly &&
                  requestedAspectRatio < contentAspectRatio) ||
              widthFit == .proportional)) {
        result = .new(
          (requested.height * contentAspectRatio).ceilToDouble(),
          requested.height,
        );
      } else if (widthFit == .proportional &&
          heightFit == .stretchOnly &&
          requestedAspectRatio > contentAspectRatio) {
        result = .new(
          requested.width,
          (requested.width / contentAspectRatio).ceilToDouble(),
        );
      }
    }
    return result;
  }

  /// Smallest fitted extent that preserves every fixed source pixel.
  Size get minimumFittedContentSize {
    final fittedContent = content ?? Rect.fromLTWH(0, 0, width, height);
    final safePixelRatio = pixelRatio.isFinite && pixelRatio > 0
        ? pixelRatio
        : 1.0;

    return .new(
      _fixedContentExtent(fittedContent.left, fittedContent.right, stretchX) /
          safePixelRatio,
      _fixedContentExtent(fittedContent.top, fittedContent.bottom, stretchY) /
          safePixelRatio,
    );
  }

  static double _fixedContentExtent(
    double start,
    double end,
    List<(double, double)> stretches,
  ) {
    if (stretches.isEmpty) return 0;
    var stretchExtent = 0.0;
    for (final stretch in stretches) {
      final overlapStart = math.max(start, stretch.$1);
      final overlapEnd = math.min(end, stretch.$2);
      if (overlapEnd > overlapStart) stretchExtent += overlapEnd - overlapStart;
    }

    return math.max(0, end - start - stretchExtent);
  }
}
