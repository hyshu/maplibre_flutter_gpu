part of 'sprite_atlas.dart';

@visibleForTesting
/// Returns the image and filter colors used to paint a sprite.
({Color imageColor, Color? filterColor}) spritePaintColors(
  double opacity,
  Color? tint,
) {
  final clampedOpacity = opacity.clamp(0.0, 1.0);
  if (tint != null) {
    return (
      imageColor: const Color(0xFFFFFFFF),
      filterColor: tint.withValues(alpha: tint.a * clampedOpacity),
    );
  }
  return (
    imageColor: Color.fromRGBO(255, 255, 255, clampedOpacity),
    filterColor: null,
  );
}

/// Paints [icon] into a [size] box at the canvas origin.
///
/// This is the painting of [SpriteIconWidget] without a widget, for callers
/// that draw sprites inside their own render object. The tint and halo apply
/// only when [SpriteIcon.sdf] is true. This function is internal and is not
/// exported by the package barrel.
@internal
void paintSpriteIcon(
  Canvas canvas,
  Size size, {
  required SpriteIcon icon,
  required double devicePixelRatio,
  double opacity = 1,
  Color? tint,
  double scale = 1,
  Color? haloColor,
  double haloWidth = 0,
  double haloBlur = 0,
}) => _SpritePainter(
  icon,
  opacity,
  icon.sdf ? tint : null,
  scale,
  icon.sdf ? haloColor : null,
  haloWidth,
  haloBlur,
  devicePixelRatio,
  false,
).paint(canvas, size);

/// Draws an icon cropped from a sprite sheet.
///
/// A tint is applied only when [SpriteIcon.sdf] is true.
class const SpriteIconWidget({
  super.key,

  /// Icon to draw.
  required final SpriteIcon icon,

  /// Display scale applied to [SpriteIcon.displaySize].
  final double scale = 1.0,

  /// Opacity applied while drawing the icon.
  ///
  /// Values at or below zero retain the icon's layout size without creating a
  /// painter.
  final double opacity = 1.0,

  /// Color applied to signed distance field icons.
  final Color? tint,

  /// Target display size used by icon-text-fit.
  ///
  /// For sprites with [SpriteIcon.content], this size describes that content
  /// rectangle and fixed borders paint outside it. A null value preserves the
  /// sprite's intrinsic aspect ratio and [scale].
  final Size? fitSize,

  /// Whether [fitSize] already includes sprite proportional constraints.
  final bool fitSizeConstrained = false,

  /// Halo color applied to signed distance field icons.
  final Color? haloColor,

  /// Halo width in logical pixels.
  final double haloWidth = 0,

  /// Halo blur radius in logical pixels.
  final double haloBlur = 0,
}) extends StatelessWidget {
  @override
  Widget build(context) {
    final naturalSize = icon.displaySize * scale;
    final requestedSize = fitSize;
    final usesTextFit =
        requestedSize != null &&
        requestedSize.width.isFinite &&
        requestedSize.height.isFinite &&
        requestedSize.width > 0 &&
        requestedSize.height > 0;
    var size = usesTextFit
        ? fitSizeConstrained
              ? requestedSize
              : icon.fittedContentSize(requestedSize)
        : naturalSize;
    if (usesTextFit) {
      final minimum = icon.minimumFittedContentSize;
      size = Size(
        math.max(size.width, minimum.width),
        math.max(size.height, minimum.height),
      );
    }
    if (opacity <= 0) return SizedBox.fromSize(size: size);

    return CustomPaint(
      size: size,
      painter: _SpritePainter(
        icon,
        opacity,
        icon.sdf ? tint : null,
        scale,
        icon.sdf ? haloColor : null,
        haloWidth,
        haloBlur,
        MediaQuery.devicePixelRatioOf(context),
        usesTextFit,
      ),
    );
  }
}

class _SpritePainter(
  final SpriteIcon icon,
  final double opacity,
  final Color? tint,
  final double scale,
  final Color? haloColor,
  final double haloWidth,
  final double haloBlur,
  final double devicePixelRatio,
  final bool usesTextFit,
) extends CustomPainter {
  Size? _cachedSegmentSize;
  List<({Rect source, Rect destination})>? _cachedSegments;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final segments = _segmentsFor(size);
    if (icon.sdf) {
      _paintSdf(canvas, segments, tint ?? const Color(0xFF000000));

      return;
    }
    final colors = spritePaintColors(opacity, tint);
    final paint = Paint()
      ..filterQuality = .medium
      ..color = colors.imageColor;
    if (colors.filterColor != null) {
      paint.colorFilter = .mode(colors.filterColor!, .srcIn);
    }
    _drawSprite(canvas, segments, paint);
  }

  void _paintSdf(
    Canvas canvas,
    List<({Rect source, Rect destination})> segments,
    Color fillColor,
  ) {
    final effectiveScale = scale.isFinite && scale > 0 ? scale : 1.0;
    final dpr = devicePixelRatio.isFinite && devicePixelRatio > 0
        ? devicePixelRatio
        : 1.0;
    final fillGamma = 0.105 / (effectiveScale * dpr);
    final haloGamma =
        (haloBlur.clamp(0.0, double.infinity) * 1.19 / 8 + 0.105) /
        (effectiveScale * dpr);
    final clampedOpacity = opacity.clamp(0.0, 1.0);
    final fillOpacity = clampedOpacity * fillColor.a;
    final halo = haloColor;
    final haloOpacity = halo == null ? 0.0 : clampedOpacity * halo.a;
    if (halo != null && haloOpacity > 0 && haloWidth > 0) {
      final haloEdge =
          (6 - haloWidth.clamp(0.0, double.infinity) / effectiveScale) / 8;
      if (haloOpacity >= 1 && fillOpacity >= 1) {
        // An opaque fill covers the halo interior, so the halo composites
        // directly like MapLibre's two SDF passes. Translucent fills or halos
        // need the layer below so the halo never shows through the fill.
        _drawSprite(canvas, segments, _sdfPaint(halo, haloEdge, haloGamma));
      } else {
        canvas.saveLayer(
          null,
          Paint()
            ..color = const Color(0xFFFFFFFF).withValues(alpha: haloOpacity),
        );
        _drawSprite(canvas, segments, _sdfPaint(halo, haloEdge, haloGamma));
        _drawSprite(
          canvas,
          segments,
          _sdfPaint(
            const Color(0xFFFFFFFF),
            0.75,
            haloGamma,
            blendMode: .dstOut,
          ),
        );
        canvas.restore();
      }
    }
    if (fillOpacity <= 0) return;
    if (fillOpacity < 1) {
      canvas.saveLayer(
        null,
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: fillOpacity),
      );
    }
    _drawSprite(canvas, segments, _sdfPaint(fillColor, 0.75, fillGamma));
    if (fillOpacity < 1) canvas.restore();
  }

  // SDF paints repeat across icons and frames. Cached paints are never
  // mutated after insertion.
  static final _sdfPaints = <(Color, double, double, BlendMode), Paint>{};
  static const _maxSdfPaints = 256;

  static Paint _sdfPaint(
    Color color,
    double edge,
    double gamma, {
    BlendMode blendMode = .srcOver,
  }) {
    final key = (color, edge, gamma, blendMode);
    final cached = _sdfPaints[key];
    if (cached != null) return cached;
    final safeGamma = gamma.clamp(1 / 255, 1.0);
    final slope = 1 / (safeGamma * 2);
    final intercept = -(edge - safeGamma) * slope * 255;
    if (_sdfPaints.length >= _maxSdfPaints) {
      _sdfPaints.remove(_sdfPaints.keys.first);
    }

    return _sdfPaints[key] = Paint()
      ..filterQuality = .medium
      ..blendMode = blendMode
      ..colorFilter = .matrix([
        0,
        0,
        0,
        0,
        color.r * 255,
        0,
        0,
        0,
        0,
        color.g * 255,
        0,
        0,
        0,
        0,
        color.b * 255,
        0,
        0,
        0,
        slope,
        intercept,
      ]);
  }

  List<({Rect source, Rect destination})> _segmentsFor(Size size) {
    final cached = _cachedSegments;
    if (_cachedSegmentSize == size && cached != null) return cached;
    final content = usesTextFit ? icon.content : null;
    final xSegments = spriteAxisSegments(
      sourceExtent: icon.width,
      stretches: usesTextFit ? icon.stretchX : const [],
      destExtent: size.width,
      pixelRatio: icon.pixelRatio,
      contentStart: content?.left,
      contentEnd: content?.right,
    );
    final ySegments = spriteAxisSegments(
      sourceExtent: icon.height,
      stretches: usesTextFit ? icon.stretchY : const [],
      destExtent: size.height,
      pixelRatio: icon.pixelRatio,
      contentStart: content?.top,
      contentEnd: content?.bottom,
    );
    final segments = [
      for (final x in xSegments)
        for (final y in ySegments)
          (
            source: Rect.fromLTRB(
              icon.x + x.sourceStart,
              icon.y + y.sourceStart,
              icon.x + x.sourceEnd,
              icon.y + y.sourceEnd,
            ),
            destination: Rect.fromLTRB(
              x.destStart,
              y.destStart,
              x.destEnd,
              y.destEnd,
            ),
          ),
    ];
    _cachedSegmentSize = size;
    _cachedSegments = segments;

    return segments;
  }

  void _drawSprite(
    Canvas canvas,
    List<({Rect source, Rect destination})> segments,
    Paint paint,
  ) {
    for (final segment in segments) {
      canvas.drawImageRect(
        icon.atlas,
        segment.source,
        segment.destination,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpritePainter old) =>
      old.icon != icon ||
      old.opacity != opacity ||
      old.tint != tint ||
      old.scale != scale ||
      old.haloColor != haloColor ||
      old.haloWidth != haloWidth ||
      old.haloBlur != haloBlur ||
      old.devicePixelRatio != devicePixelRatio ||
      old.usesTextFit != usesTextFit;
}
