part of 'default_symbol_builders.dart';

/// A glyph shaped for placement, in shaped units.
class const _ShapedGlyph({
  required final String text,
  required final TextStyle style,
  final SpriteIcon? image,
  final double imageScale = 1,
  required final double advance,
  required final Size size,
});

/// Shapes the graphemes and inline images of [parts] for glyph placement.
List<_ShapedGlyph> _shapeGlyphs(
  List<_SymbolTextPart> parts,
  TextDirection direction,
  DefaultTextScale scale,
) {
  final glyphs = <_ShapedGlyph>[];
  for (final part in parts) {
    if (part.imageSection) {
      final image = part.image;
      if (image == null) continue;
      final imageScale = part.imageScale / scale.ratio;
      final size = image.displaySize * imageScale;
      glyphs.add(
        _ShapedGlyph(
          text: '',
          style: part.style,
          image: image,
          imageScale: imageScale,
          advance: size.width,
          size: size,
        ),
      );
      continue;
    }
    for (final grapheme in part.text.characters) {
      if (grapheme == '\n' || grapheme == '\r') continue;
      final glyphStyle = part.style.copyWith(height: 1);
      final metrics = _pathGlyphMetrics(grapheme, glyphStyle, direction);
      glyphs.add(
        _ShapedGlyph(
          text: grapheme,
          style: glyphStyle,
          advance: metrics.advance,
          size: metrics.size,
        ),
      );
    }
  }

  return glyphs;
}

// Glyph sizes and advances are in shaped units; the scale ratio converts them
// to screen space for placement, and each glyph's transform applies it.
Widget _buildPathText(
  LabelData data,
  List<_SymbolTextPart> parts,
  DefaultTextScale scale,
) {
  final glyphs = _shapeGlyphs(parts, data.textDirection, scale);
  final path = [for (final point in data.textPath) Offset(point.x, point.y)];
  final lineScale = _lineSymbolScale(data.textTransform);
  final pathAngle =
      _pathAngle(data.textPath, data.angle, keepUpright: data.textKeepUpright) +
      data.textRotation;
  final advanceScale = _lineAdvanceScale(lineScale, pathAngle) * scale.ratio;
  final placements = layoutSymbolGlyphsAlongPath(path, [
    for (final glyph in glyphs) glyph.advance * advanceScale,
  ], keepUpright: data.textKeepUpright);
  if (placements.length != glyphs.length) {
    final fallbackStyle = parts.isEmpty
        ? TextStyle(fontSize: scale.fontSize, color: data.textColor)
        : parts.first.style;
    final fallback = _buildPointText(data, parts, fallbackStyle, scale);

    return _applyLineSymbolTransform(
      fallback,
      data.textTransform,
      _pathAngle(data.textPath, data.angle, keepUpright: data.textKeepUpright) +
          data.textRotation,
      scale.ratio,
    );
  }

  final visualScaleX = lineScale.x.isFinite ? math.max(lineScale.x, 0) : 1.0;
  final visualScaleY = lineScale.y.isFinite ? math.max(lineScale.y, 0) : 1.0;
  final maxGlyphWidth =
      glyphs.fold<double>(
        scale.fontSize,
        (value, glyph) => math.max(value, glyph.size.width),
      ) *
      visualScaleX *
      scale.ratio;
  final maxGlyphHeight =
      glyphs.fold<double>(
        scale.fontSize,
        (value, glyph) => math.max(value, glyph.size.height),
      ) *
      visualScaleY *
      scale.ratio;
  final halfWidth =
      path.fold<double>(0, (value, point) => math.max(value, point.dx.abs())) +
      maxGlyphWidth / 2 +
      data.haloWidth +
      data.haloBlur;
  final halfHeight =
      path.fold<double>(0, (value, point) => math.max(value, point.dy.abs())) +
      maxGlyphHeight / 2 +
      data.haloWidth +
      data.haloBlur;
  final placed = <SymbolGlyph>[];
  for (var i = 0; i < glyphs.length; i++) {
    final glyph = glyphs[i];
    final placement = placements[i];
    placed.add(
      SymbolGlyph(
        text: glyph.text,
        style: glyph.style,
        image: glyph.image,
        imageScale: glyph.imageScale,
        size: glyph.size,
        center: Offset(
          halfWidth + placement.position.dx,
          halfHeight + placement.position.dy,
        ),
        transform: _pathGlyphTransform(
          data.textTransform,
          placement.angle + data.textRotation,
          scale.ratio,
        ),
      ),
    );
  }

  return SymbolGlyphRun(
    glyphs: placed,
    desiredSize: Size(math.max(1, halfWidth * 2), math.max(1, halfHeight * 2)),
    direction: data.textDirection,
    haloColor: data.haloColor,
    haloWidth: scale.haloWidth,
    haloBlur: scale.haloBlur,
  );
}

Matrix4 _pathGlyphTransform(
  LabelAffineTransform transform,
  double angle,
  double ratio,
) {
  final scale = _lineSymbolScale(transform);
  final hasFiniteScale = scale.x.isFinite && scale.y.isFinite;
  final scaleX = (hasFiniteScale ? scale.x : 1.0) * ratio;
  final scaleY = (hasFiniteScale ? scale.y : 1.0) * ratio;
  final safeAngle = angle.isFinite ? angle : 0.0;
  final cosine = math.cos(safeAngle);
  final sine = math.sin(safeAngle);

  return Matrix4.identity()
    ..setEntry(0, 0, cosine * scaleX)
    ..setEntry(1, 0, sine * scaleY)
    ..setEntry(0, 1, -sine * scaleX)
    ..setEntry(1, 1, cosine * scaleY);
}

typedef _GlyphMetrics = ({double advance, Size size});

// Metrics depend on the font and spacing only, so colors and halo paints share
// one entry. Fallback families are joined because record equality compares
// lists by identity.
typedef _GlyphMetricsKey = (
  String,
  TextDirection,
  double?,
  String?,
  String?,
  FontWeight?,
  FontStyle?,
  double?,
  double?,
);

final _pathGlyphMetricsCache = _BoundedCache<_GlyphMetricsKey, _GlyphMetrics>(
  4096,
);
var _listensForSystemFontChanges = false;

_GlyphMetrics _pathGlyphMetrics(
  String text,
  TextStyle style,
  TextDirection direction,
) {
  if (!_listensForSystemFontChanges) {
    PaintingBinding.instance.systemFonts.addListener(
      _pathGlyphMetricsCache.clear,
    );
    _listensForSystemFontChanges = true;
  }
  final key = (
    text,
    direction,
    style.fontSize,
    style.fontFamily,
    style.fontFamilyFallback?.join('\u0000'),
    style.fontWeight,
    style.fontStyle,
    style.letterSpacing,
    style.wordSpacing,
  );
  final cached = _pathGlyphMetricsCache[key];
  if (cached != null) return cached;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    maxLines: 1,
  );
  late final _GlyphMetrics metrics;
  try {
    painter.layout();
    metrics = (advance: painter.width, size: painter.size);
  } finally {
    painter.dispose();
  }
  return _pathGlyphMetricsCache.put(key, metrics);
}
