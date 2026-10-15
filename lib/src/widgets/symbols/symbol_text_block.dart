part of 'default_symbol_builders.dart';

/// Paints one point label as a single leaf.
///
/// The label is laid out once as a paragraph, with its lines aligned by
/// [align] inside [width], and painted from the shared glyph atlas, so a
/// camera frame that only moves or scales the label neither re-shapes nor
/// re-rasterizes its text. Inherited text settings are resolved where the
/// block is mounted, as a [Text] widget would resolve them. Lengths are in
/// shaped units. This widget is internal and is not exported by the package
/// barrel.
@internal
class const SymbolTextBlock({
  super.key,

  /// The label text. Placeholder spans are not supported.
  required final InlineSpan span,
  required final TextAlign align,

  /// The box width that lines align within. A line wider than the box
  /// overflows it on the sides the alignment leaves open, so centered text
  /// stays centered on the box, and the leaf stays this wide.
  required final double width,

  /// The line limit, or null to keep every line of the text.
  required final int? maxLines,
  required final TextDirection direction,
  required final Color haloColor,
  required final double haloWidth,
  required final double haloBlur,

  /// Ink that may extend past the paragraph box on each side, such as the
  /// overhang of italic glyphs.
  required final double inkMargin,

  /// Whether the leaf paints without scaling or rotation, so its raster can
  /// land on whole device pixels.
  required final bool pixelAligned,
}) extends LeafRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSymbolTextBlock(
        span: span,
        align: align,
        width: width,
        maxLines: maxLines,
        direction: direction,
        haloColor: haloColor,
        haloWidth: haloWidth,
        haloBlur: haloBlur,
        inkMargin: inkMargin,
        pixelAligned: pixelAligned,
        settings: SymbolTextSettings.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSymbolTextBlock renderObject,
  ) => renderObject
    ..settings = SymbolTextSettings.of(context)
    ..direction = direction
    ..haloColor = haloColor
    ..haloWidth = haloWidth
    ..haloBlur = haloBlur
    ..inkMargin = inkMargin
    ..pixelAligned = pixelAligned
    ..align = align
    ..maxLines = maxLines
    ..width = width
    ..span = span;
}

/// Render object of [SymbolTextBlock].
///
/// The paragraph is as wide as its longest line and is offset inside the leaf
/// by the alignment, which places lines where a [Text] widget of the leaf's
/// width would while they fit and keeps the alignment when they overflow.
/// Width changes re-layout without re-shaping. This class is internal.
@internal
class RenderSymbolTextBlock({
  required var InlineSpan _span,
  required var TextAlign _align,
  required var double _width,
  required var int? _maxLines,
  required var TextDirection _direction,
  required var Color _haloColor,
  required var double _haloWidth,
  required var double _haloBlur,
  required var double _inkMargin,
  required var bool _pixelAligned,
  required var SymbolTextSettings _settings,
}) extends RenderBox with RelayoutWhenSystemFontsChangeMixin {
  _GlyphPainter? _fill;
  _GlyphPainter? _halo;

  set span(InlineSpan value) {
    if (_span == value) return;
    _span = value;
    _releasePainters();
    markNeedsLayout();
  }

  set align(TextAlign value) {
    if (_align == value) return;
    _align = value;
    _releasePainters();
    markNeedsLayout();
  }

  set width(double value) {
    if (_width == value) return;
    _width = value;
    markNeedsLayout();
  }

  set maxLines(int? value) {
    if (_maxLines == value) return;
    _maxLines = value;
    _releasePainters();
    markNeedsLayout();
  }

  set direction(TextDirection value) {
    if (_direction == value) return;
    _direction = value;
    _releasePainters();
    markNeedsLayout();
  }

  set haloColor(Color value) {
    if (_haloColor == value) return;
    _haloColor = value;
    _releasePainters();
    markNeedsPaint();
  }

  set haloWidth(double value) {
    if (_haloWidth == value) return;
    _haloWidth = value;
    _releasePainters();
    markNeedsPaint();
  }

  set haloBlur(double value) {
    if (_haloBlur == value) return;
    _haloBlur = value;
    _releasePainters();
    markNeedsPaint();
  }

  set inkMargin(double value) {
    if (_inkMargin == value) return;
    _inkMargin = value;
    markNeedsPaint();
  }

  set pixelAligned(bool value) {
    if (_pixelAligned == value) return;
    _pixelAligned = value;
    markNeedsPaint();
  }

  set settings(SymbolTextSettings value) {
    if (_settings == value) return;
    _settings = value;
    _releasePainters();
    markNeedsLayout();
  }

  /// The resolved fill painter.
  @visibleForTesting
  TextPainter get debugFillPainter {
    _ensurePainters();

    return _fill!.painter;
  }

  /// The resolved halo painter, or null without a halo.
  @visibleForTesting
  TextPainter? get debugHaloPainter {
    _ensurePainters();

    return _halo?.painter;
  }

  void _ensurePainters() {
    if (_fill != null) return;
    final span = _resolvedSpan();
    _fill = _GlyphPainters.acquire(
      span,
      _direction,
      _settings,
      align: _align,
      maxLines: _maxLines,
    );
    _halo = _haloWidth <= 0
        ? null
        : _GlyphPainters.acquire(
            _spanWithForeground(
              span,
              _haloPaint(_haloWidth, _haloBlur, _haloColor),
            ),
            _direction,
            _settings,
            align: _align,
            maxLines: _maxLines,
          );
  }

  /// The span with the inherited text settings merged into its root style.
  InlineSpan _resolvedSpan() {
    final span = _span;
    if (span is! TextSpan) return span;

    return TextSpan(
      text: span.text,
      style: _settings.resolve(span.style ?? const TextStyle()),
      children: span.children,
    );
  }

  void _releasePainters() {
    _fill?.release();
    _halo?.release();
    _fill = null;
    _halo = null;
  }

  @override
  void systemFontsDidChange() {
    _releasePainters();
    super.systemFontsDidChange();
  }

  @override
  void detach() {
    _releasePainters();
    super.detach();
  }

  @override
  void dispose() {
    _releasePainters();
    super.dispose();
  }

  @override
  bool get sizedByParent => false;

  Size _blockSize(BoxConstraints constraints) {
    _ensurePainters();

    return constraints.constrain(Size(_width, _fill!.painter.height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _blockSize(constraints);

  @override
  void performLayout() {
    size = _blockSize(constraints);
    // Reserving atlas space now lets the first paint of the frame draw every
    // newly laid out label into its page at once.
    _GlyphAtlas.entryFor(
      _fill!,
      _halo,
      _settings.devicePixelRatio,
      _atlasPadding,
    );
  }

  @override
  bool hitTestSelf(Offset position) => true;

  /// The paragraph origin inside the leaf.
  Offset get _paragraphOrigin => Offset(
    (_width - _fill!.painter.width) * _alignmentFactor(_align, _direction),
    0,
  );

  /// Texels of padding around the rasterized paragraph for its halo and ink
  /// that extends past the paragraph box.
  double get _atlasPadding =>
      ((_haloWidth + _haloBlur * 2 + _inkMargin) * _settings.devicePixelRatio)
          .ceilToDouble() +
      1;

  @override
  void paint(PaintingContext context, Offset offset) {
    _ensurePainters();
    final fill = _fill!;
    final canvas = context.canvas;
    final devicePixelRatio = _settings.devicePixelRatio;
    var origin = offset + _paragraphOrigin;
    if (_pixelAligned) {
      origin = Offset(
        (origin.dx * devicePixelRatio).roundToDouble() / devicePixelRatio,
        (origin.dy * devicePixelRatio).roundToDouble() / devicePixelRatio,
      );
    }
    final entry = _GlyphAtlas.entryFor(
      fill,
      _halo,
      devicePixelRatio,
      _atlasPadding,
    );
    if (entry != null && _GlyphAtlas.prepare(entry)) {
      final rect = entry.rect;
      final inset = entry.padding / devicePixelRatio;
      canvas.drawImageRect(
        entry.page.image!,
        rect,
        Rect.fromLTWH(
          origin.dx - inset,
          origin.dy - inset,
          rect.width / devicePixelRatio,
          rect.height / devicePixelRatio,
        ),
        _pixelAligned ? _nearestAtlasPaint : _atlasPaint,
      );
      SymbolProfileCounters.add(SymbolProfileCounters.atlasGlyphs);

      return;
    }
    SymbolProfileCounters.add(SymbolProfileCounters.atlasFallbacks);
    _halo?.painter.paint(canvas, origin);
    fill.painter.paint(canvas, origin);
  }
}

/// The share of spare box width placed before a line.
double _alignmentFactor(TextAlign align, TextDirection direction) =>
    switch (align) {
      .left || .justify => 0,
      .right => 1,
      .center => 0.5,
      .start => direction == .ltr ? 0 : 1,
      .end => direction == .ltr ? 1 : 0,
    };

/// Copies [span] with [paint] as the foreground of every text style, as a
/// halo needs. Placeholder spans are returned unchanged.
InlineSpan _spanWithForeground(InlineSpan span, Paint paint) {
  if (span is! TextSpan) return span;
  final style = span.style;
  final children = span.children;

  return TextSpan(
    text: span.text,
    style: style == null
        ? TextStyle(foreground: paint)
        : style.copyWith(foreground: paint),
    children: children == null
        ? null
        : [for (final child in children) _spanWithForeground(child, paint)],
  );
}
