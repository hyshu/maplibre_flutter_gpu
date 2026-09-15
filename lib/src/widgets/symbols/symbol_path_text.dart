part of 'default_symbol_builders.dart';

Widget _buildPathText(LabelData data, List<_SymbolTextPart> parts) {
  final glyphs = <_PathGlyph>[];
  final direction = data.textDirection;
  for (final part in parts) {
    if (part.imageSection) {
      final image = part.image;
      if (image == null) continue;
      final size = image.displaySize * part.imageScale;
      glyphs.add(
        _PathGlyph(
          advance: size.width,
          size: size,
          child: SpriteIconWidget(
            icon: image,
            scale: part.imageScale,
            tint: part.style.color,
            haloColor: image.sdf ? data.haloColor : null,
            haloWidth: image.sdf ? data.haloWidth : 0,
            haloBlur: image.sdf ? data.haloBlur : 0,
          ),
        ),
      );
      continue;
    }
    for (final grapheme in part.text.characters) {
      if (grapheme == '\n' || grapheme == '\r') continue;
      final glyphStyle = part.style.copyWith(height: 1);
      final metrics = _pathGlyphMetrics(grapheme, glyphStyle, direction);
      glyphs.add(
        _PathGlyph(
          advance: metrics.advance,
          size: metrics.size,
          child: _glyphText(grapheme, glyphStyle, data),
        ),
      );
    }
  }
  final path = [for (final point in data.textPath) Offset(point.x, point.y)];
  final lineScale = _lineSymbolScale(data.textTransform);
  final pathAngle =
      _pathAngle(data.textPath, data.angle, keepUpright: data.textKeepUpright) +
      data.textRotation;
  final advanceScale = _lineAdvanceScale(lineScale, pathAngle);
  final placements = layoutSymbolGlyphsAlongPath(path, [
    for (final glyph in glyphs) glyph.advance * advanceScale,
  ], keepUpright: data.textKeepUpright);
  if (placements.length != glyphs.length) {
    final fallbackStyle = parts.isEmpty
        ? TextStyle(fontSize: data.fontSize, color: data.textColor)
        : parts.first.style;
    final fallback = _buildPointText(data, parts, fallbackStyle);

    return _applyLineSymbolTransform(
      fallback,
      data.textTransform,
      _pathAngle(data.textPath, data.angle, keepUpright: data.textKeepUpright) +
          data.textRotation,
    );
  }

  final visualScaleX = lineScale.x.isFinite ? math.max(lineScale.x, 0) : 1.0;
  final visualScaleY = lineScale.y.isFinite ? math.max(lineScale.y, 0) : 1.0;
  final maxGlyphWidth =
      glyphs.fold<double>(
        data.fontSize,
        (value, glyph) => math.max(value, glyph.size.width),
      ) *
      visualScaleX;
  final maxGlyphHeight =
      glyphs.fold<double>(
        data.fontSize,
        (value, glyph) => math.max(value, glyph.size.height),
      ) *
      visualScaleY;
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
  final placementsForLayout = <_PathGlyphPlacement>[];
  final children = <Widget>[];
  for (var i = 0; i < glyphs.length; i++) {
    final glyph = glyphs[i];
    final placement = placements[i];
    placementsForLayout.add(
      _PathGlyphPlacement(
        size: glyph.size,
        offset: Offset(
          halfWidth + placement.position.dx - glyph.size.width / 2,
          halfHeight + placement.position.dy - glyph.size.height / 2,
        ),
      ),
    );
    children.add(
      Transform(
        alignment: Alignment.center,
        transform: _pathGlyphTransform(
          data.textTransform,
          placement.angle + data.textRotation,
        ),
        child: glyph.child,
      ),
    );
  }

  return _PathGlyphLayout(
    desiredSize: Size(math.max(1, halfWidth * 2), math.max(1, halfHeight * 2)),
    placements: placementsForLayout,
    children: children,
  );
}

Matrix4 _pathGlyphTransform(LabelAffineTransform transform, double angle) {
  final scale = _lineSymbolScale(transform);
  final hasFiniteScale = scale.x.isFinite && scale.y.isFinite;
  final scaleX = hasFiniteScale ? scale.x : 1.0;
  final scaleY = hasFiniteScale ? scale.y : 1.0;
  final safeAngle = angle.isFinite ? angle : 0.0;
  final cosine = math.cos(safeAngle);
  final sine = math.sin(safeAngle);

  return Matrix4.identity()
    ..setEntry(0, 0, cosine * scaleX)
    ..setEntry(1, 0, sine * scaleY)
    ..setEntry(0, 1, -sine * scaleX)
    ..setEntry(1, 1, cosine * scaleY);
}

class const _PathGlyphLayout({
  required final Size desiredSize,
  required final List<_PathGlyphPlacement> placements,
  required super.children,
}) extends MultiChildRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPathGlyphLayout(desiredSize: desiredSize, placements: placements);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderPathGlyphLayout renderObject,
  ) {
    renderObject
      ..desiredSize = desiredSize
      ..placements = placements;
  }
}

class const _PathGlyphPlacement({
  required final Size size,
  required final Offset offset,
});

class _PathGlyphParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPathGlyphLayout({
  required var Size _desiredSize,
  required var List<_PathGlyphPlacement> _placements,
}) extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PathGlyphParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PathGlyphParentData> {
  set desiredSize(Size value) {
    if (_desiredSize == value) return;
    _desiredSize = value;
    markNeedsLayout();
  }

  set placements(List<_PathGlyphPlacement> value) {
    _placements = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PathGlyphParentData) {
      child.parentData = _PathGlyphParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_desiredSize);

  @override
  void performLayout() {
    size = constraints.constrain(_desiredSize);
    var child = firstChild;
    var index = 0;
    while (child != null) {
      assert(index < _placements.length);
      final placement = _placements[index];
      child.layout(BoxConstraints.tight(placement.size));
      final parentData = child.parentData! as _PathGlyphParentData;
      parentData.offset = placement.offset;
      child = parentData.nextSibling;
      index++;
    }
    assert(index == _placements.length);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final parentData = child.parentData! as _PathGlyphParentData;
    transform.multiply(
      Matrix4.translationValues(parentData.offset.dx, parentData.offset.dy, 0),
    );
  }
}

class const _PathGlyph({
  required final double advance,
  required final Size size,
  required final Widget child,
});

typedef _GlyphMetrics = ({double advance, Size size});

const _maxPathGlyphMetrics = 4096;
final _pathGlyphMetricsCache =
    <(String, TextStyle, TextDirection), _GlyphMetrics>{};
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
  final key = (text, style, direction);
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
  if (_pathGlyphMetricsCache.length >= _maxPathGlyphMetrics) {
    _pathGlyphMetricsCache.clear();
  }
  _pathGlyphMetricsCache[key] = metrics;

  return metrics;
}
