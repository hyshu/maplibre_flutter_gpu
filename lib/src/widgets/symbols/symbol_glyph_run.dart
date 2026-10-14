part of 'default_symbol_builders.dart';

/// One glyph or inline image painted by a [SymbolGlyphRun].
///
/// [size] is the glyph box in shaped units. [center] is the box center in the
/// run's coordinates. The box rotates by [angle] around that center and then
/// scales by [scaleX] and [scaleY] along the run's axes, which is how pitch
/// compresses rotated glyphs in screen space. This class is internal and is
/// not exported by the package barrel.
@internal
class const SymbolGlyph({
  /// The grapheme, or an empty string for an inline image.
  required final String text,

  /// The fill style of a text glyph, or the tint source of an image.
  required final TextStyle style,
  final SpriteIcon? image,
  final double imageScale = 1,
  required final Size size,
  required final Offset center,
  final double angle = 0,
  final double scaleX = 1,
  final double scaleY = 1,
}) {
  /// The placement as a matrix applied around [center].
  Matrix4 get transform {
    final cosine = math.cos(angle);
    final sine = math.sin(angle);

    return Matrix4.identity()
      ..setEntry(0, 0, cosine * scaleX)
      ..setEntry(1, 0, sine * scaleY)
      ..setEntry(0, 1, -sine * scaleX)
      ..setEntry(1, 1, cosine * scaleY);
  }

  /// Whether [other] paints the same content, ignoring placement.
  bool shapesLike(SymbolGlyph other) =>
      text == other.text &&
      style == other.style &&
      identical(image, other.image) &&
      imageScale == other.imageScale &&
      size == other.size;
}

/// Paints the glyphs of one along-line or vertical label as a single leaf.
///
/// Each glyph is drawn from a shared, laid-out text painter, so a placement
/// change repaints the leaf without rebuilding or re-laying out any widget.
/// Inherited text settings are resolved where the run is mounted, as a
/// [Text] widget would resolve them. Halo values are in shaped units. This
/// widget is internal and is not exported by the package barrel.
@internal
class const SymbolGlyphRun({
  super.key,
  required final List<SymbolGlyph> glyphs,
  required final Size desiredSize,
  required final TextDirection direction,
  required final Color haloColor,
  required final double haloWidth,
  required final double haloBlur,
}) extends LeafRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) => RenderSymbolGlyphRun(
    glyphs: glyphs,
    desiredSize: desiredSize,
    direction: direction,
    haloColor: haloColor,
    haloWidth: haloWidth,
    haloBlur: haloBlur,
    settings: SymbolTextSettings.of(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSymbolGlyphRun renderObject,
  ) => renderObject
    ..settings = SymbolTextSettings.of(context)
    ..direction = direction
    ..haloColor = haloColor
    ..haloWidth = haloWidth
    ..haloBlur = haloBlur
    ..desiredSize = desiredSize
    ..glyphs = glyphs;
}

/// Ambient text settings that a [Text] widget would apply. Internal.
@internal
class const SymbolTextSettings({
  required final TextStyle defaultStyle,
  required final TextScaler scaler,
  required final bool boldText,
  required final TextHeightBehavior? heightBehavior,
  required final Locale? locale,
  required final double devicePixelRatio,
}) {
  factory of(BuildContext context) {
    final defaults = DefaultTextStyle.of(context);

    return .new(
      defaultStyle: defaults.style,
      scaler: MediaQuery.textScalerOf(context),
      boldText: MediaQuery.boldTextOf(context),
      heightBehavior:
          defaults.textHeightBehavior ??
          DefaultTextHeightBehavior.maybeOf(context),
      locale: Localizations.maybeLocaleOf(context),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SymbolTextSettings &&
      defaultStyle == other.defaultStyle &&
      scaler == other.scaler &&
      boldText == other.boldText &&
      heightBehavior == other.heightBehavior &&
      locale == other.locale &&
      devicePixelRatio == other.devicePixelRatio;

  @override
  int get hashCode => Object.hash(
    defaultStyle,
    scaler,
    boldText,
    heightBehavior,
    locale,
    devicePixelRatio,
  );

  /// Resolves [style] the way [Text] resolves its style.
  TextStyle resolve(TextStyle style) {
    final merged = defaultStyle.merge(style);

    return boldText ? merged.merge(const TextStyle(fontWeight: .bold)) : merged;
  }
}

typedef _GlyphPainterKey = (
  InlineSpan,
  TextDirection,
  TextAlign,
  int?,
  TextScaler,
  TextHeightBehavior?,
  Locale?,
);

/// A laid-out painter shared by every leaf that paints the same text.
class _GlyphPainter {
  _GlyphPainter(this.painter);

  final TextPainter painter;

  /// The atlas glyphs rasterized from this painter.
  final atlasKeys = <_GlyphAtlasKey>{};
  var references = 0;
  var evicted = false;

  void release() {
    references--;
    if (references == 0 && evicted) _dispose();
  }

  void _dispose() {
    _GlyphAtlas.forget(this);
    painter.dispose();
  }
}

/// Shares laid-out text painters between glyph runs and text blocks.
///
/// Painters stay alive while any leaf references them. Eviction removes
/// unreferenced painters first and disposes referenced ones once released.
abstract final class _GlyphPainters {
  static var capacity = 8192;
  static final _entries = <_GlyphPainterKey, _GlyphPainter>{};
  static var _listensForSystemFontChanges = false;

  /// Returns the painter of [span] laid out as wide as its longest line, with
  /// lines aligned by [align] inside that width.
  static _GlyphPainter acquire(
    InlineSpan span,
    TextDirection direction,
    SymbolTextSettings settings, {
    TextAlign align = .start,
    int? maxLines = 1,
  }) {
    if (!_listensForSystemFontChanges) {
      PaintingBinding.instance.systemFonts.addListener(_evictAll);
      _listensForSystemFontChanges = true;
    }
    final key = (
      span,
      direction,
      align,
      maxLines,
      settings.scaler,
      settings.heightBehavior,
      settings.locale,
    );
    var entry = _entries[key];
    if (entry == null) {
      if (_entries.length >= capacity) _evictUnreferenced();
      final painter = TextPainter(
        text: span,
        textAlign: align,
        textDirection: direction,
        textScaler: settings.scaler,
        textHeightBehavior: settings.heightBehavior,
        locale: settings.locale,
        maxLines: maxLines,
      )..layout();
      entry = _entries[key] = _GlyphPainter(painter);
    }
    entry.references++;

    return entry;
  }

  static void _evictUnreferenced() {
    final removed = <_GlyphPainterKey>[];
    for (final entry in _entries.entries) {
      if (entry.value.references > 0) continue;
      entry.value._dispose();
      removed.add(entry.key);
      if (removed.length >= math.max(1, capacity ~/ 8)) break;
    }
    if (removed.isEmpty) {
      // Every painter is in use; let the oldest go once it is released.
      final oldest = _entries.entries.first;
      oldest.value.evicted = true;
      _entries.remove(oldest.key);

      return;
    }
    removed.forEach(_entries.remove);
  }

  static void _evictAll() {
    _GlyphAtlas.clear();
    for (final entry in _entries.values) {
      if (entry.references == 0) {
        entry.painter.dispose();
      } else {
        entry.evicted = true;
      }
    }
    _entries.clear();
  }
}

/// Render object of [SymbolGlyphRun].
///
/// Placement-only updates repaint without layout. Size or content changes
/// re-layout and re-resolve painters. This class is internal.
@internal
class RenderSymbolGlyphRun({
  required var List<SymbolGlyph> _glyphs,
  required var Size _desiredSize,
  required var TextDirection _direction,
  required var Color _haloColor,
  required var double _haloWidth,
  required var double _haloBlur,
  required var SymbolTextSettings _settings,
}) extends RenderBox with RelayoutWhenSystemFontsChangeMixin {
  List<_GlyphPainter?>? _fills;
  List<_GlyphPainter?>? _halos;
  // Scratch buffers for one atlas batch, reused across paints.
  Float32List _transforms = Float32List(0);
  Float32List _rects = Float32List(0);

  /// The glyphs in paint order.
  List<SymbolGlyph> get glyphs => _glyphs;

  set glyphs(List<SymbolGlyph> value) {
    if (identical(_glyphs, value)) return;
    final previous = _glyphs;
    _glyphs = value;
    var sameContent = previous.length == value.length;
    for (var index = 0; sameContent && index < value.length; index++) {
      sameContent = previous[index].shapesLike(value[index]);
    }
    if (sameContent) {
      // Glyph boxes are independent of their placement.
      markNeedsPaint();

      return;
    }
    _releasePainters();
    markNeedsLayout();
  }

  set desiredSize(Size value) {
    if (_desiredSize == value) return;
    _desiredSize = value;
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

  set settings(SymbolTextSettings value) {
    if (_settings == value) return;
    _settings = value;
    _releasePainters();
    markNeedsLayout();
  }

  /// The resolved fill painter of each text glyph, or null for images.
  @visibleForTesting
  List<TextPainter?> get debugFillPainters {
    _ensurePainters();

    return [for (final fill in _fills!) fill?.painter];
  }

  void _ensurePainters() {
    if (_fills != null) return;
    final fills = <_GlyphPainter?>[];
    final halos = <_GlyphPainter?>[];
    for (final glyph in _glyphs) {
      if (glyph.image != null) {
        fills.add(null);
        halos.add(null);
        continue;
      }
      final style = _settings.resolve(glyph.style);
      fills.add(
        _GlyphPainters.acquire(
          TextSpan(text: glyph.text, style: style),
          _direction,
          _settings,
        ),
      );
      halos.add(
        _haloWidth <= 0
            ? null
            : _GlyphPainters.acquire(
                TextSpan(
                  text: glyph.text,
                  style: style.copyWith(
                    foreground: _haloPaint(_haloWidth, _haloBlur, _haloColor),
                  ),
                ),
                _direction,
                _settings,
              ),
      );
    }
    _fills = fills;
    _halos = halos;
  }

  void _releasePainters() {
    for (final entry in [...?_fills, ...?_halos]) {
      entry?.release();
    }
    _fills = null;
    _halos = null;
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

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_desiredSize);

  @override
  void performLayout() {
    size = constraints.constrain(_desiredSize);
    _ensurePainters();
    // Reserving atlas space now lets the first paint of the frame draw every
    // newly laid out glyph into its page at once.
    final padding = _atlasPadding;
    for (final fill in _fills!.indexed) {
      final painter = fill.$2;
      if (painter == null) continue;
      _GlyphAtlas.entryFor(
        painter,
        _halos![fill.$1],
        _settings.devicePixelRatio,
        padding,
      );
    }
  }

  @override
  bool hitTestSelf(Offset position) {
    for (final glyph in _glyphs) {
      final inverse = Matrix4.tryInvert(glyph.transform);
      if (inverse == null) continue;
      final local = MatrixUtils.transformPoint(
        inverse,
        position - glyph.center,
      );
      if (local.dx.abs() <= glyph.size.width / 2 &&
          local.dy.abs() <= glyph.size.height / 2) {
        return true;
      }
    }

    return false;
  }

  /// Texels of padding around a rasterized glyph for its halo and ink that
  /// extends past the glyph box.
  double get _atlasPadding {
    final fontSize = _glyphs.isEmpty
        ? 0.0
        : (_settings.resolve(_glyphs.first.style).fontSize ?? 0);

    return ((_haloWidth + _haloBlur * 2 + fontSize * 0.2) *
                _settings.devicePixelRatio)
            .ceilToDouble() +
        1;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _ensurePainters();
    final canvas = context.canvas;
    final padding = _atlasPadding;
    final devicePixelRatio = _settings.devicePixelRatio;
    // Every text glyph of a label shares one scale, so a label draws as one
    // batch per atlas page under that scale with per-glyph rotation.
    _GlyphAtlasPage? batchPage;
    var batchScaleX = 1.0;
    var batchScaleY = 1.0;
    var batched = 0;
    void flushBatch() {
      if (batched == 0) return;
      canvas
        ..save()
        ..translate(offset.dx, offset.dy)
        ..scale(batchScaleX, batchScaleY)
        ..drawRawAtlas(
          batchPage!.image!,
          Float32List.sublistView(_transforms, 0, batched * 4),
          Float32List.sublistView(_rects, 0, batched * 4),
          null,
          null,
          null,
          _atlasPaint,
        )
        ..restore();
      batched = 0;
    }

    for (var index = 0; index < _glyphs.length; index++) {
      final glyph = _glyphs[index];
      final box = glyph.size;
      final image = glyph.image;
      _GlyphAtlasEntry? entry;
      if (image == null) {
        final fill = _fills![index]!;
        entry = _GlyphAtlas.entryFor(
          fill,
          _halos![index],
          devicePixelRatio,
          padding,
        );
        if (entry != null && !_GlyphAtlas.prepare(entry)) entry = null;
      }
      if (entry != null) {
        if (batchPage != entry.page ||
            batchScaleX != glyph.scaleX ||
            batchScaleY != glyph.scaleY) {
          flushBatch();
          batchPage = entry.page;
          batchScaleX = glyph.scaleX;
          batchScaleY = glyph.scaleY;
        }
        _appendAtlasGlyph(batched, glyph, entry, devicePixelRatio);
        batched++;
        SymbolProfileCounters.add(SymbolProfileCounters.atlasGlyphs);
        continue;
      }
      if (image == null) {
        SymbolProfileCounters.add(SymbolProfileCounters.atlasFallbacks);
      }
      flushBatch();
      canvas
        ..save()
        ..translate(offset.dx + glyph.center.dx, offset.dy + glyph.center.dy)
        ..transform(glyph.transform.storage)
        ..translate(-box.width / 2, -box.height / 2);
      if (image != null) {
        paintSpriteIcon(
          canvas,
          box,
          icon: image,
          scale: glyph.imageScale,
          tint: glyph.style.color,
          haloColor: image.sdf ? _haloColor : null,
          haloWidth: image.sdf ? _haloWidth : 0,
          haloBlur: image.sdf ? _haloBlur : 0,
          devicePixelRatio: devicePixelRatio,
        );
      } else {
        _halos![index]?.painter.paint(canvas, Offset.zero);
        _fills![index]!.painter.paint(canvas, Offset.zero);
      }
      canvas.restore();
    }
    flushBatch();
  }

  void _appendAtlasGlyph(
    int slot,
    SymbolGlyph glyph,
    _GlyphAtlasEntry entry,
    double devicePixelRatio,
  ) {
    if (_transforms.length < (slot + 1) * 4) {
      final capacity = math.max(16, _glyphs.length) * 4;
      _transforms = Float32List(capacity);
      _rects = Float32List(capacity);
    }
    // The batch canvas is scaled by the glyph scale, so the glyph center maps
    // back through that scale. A plain translation lands on whole device
    // pixels to stay as crisp as directly painted text.
    var x = glyph.center.dx / glyph.scaleX;
    var y = glyph.center.dy / glyph.scaleY;
    if (glyph.angle == 0 && glyph.scaleX == 1 && glyph.scaleY == 1) {
      x = (x * devicePixelRatio).roundToDouble() / devicePixelRatio;
      y = (y * devicePixelRatio).roundToDouble() / devicePixelRatio;
    }
    final scale = 1 / devicePixelRatio;
    final cosine = math.cos(glyph.angle) * scale;
    final sine = math.sin(glyph.angle) * scale;
    final rect = entry.rect;
    final anchorX = rect.width / 2;
    final anchorY = rect.height / 2;
    final base = slot * 4;
    _transforms[base] = cosine;
    _transforms[base + 1] = sine;
    _transforms[base + 2] = x - cosine * anchorX + sine * anchorY;
    _transforms[base + 3] = y - sine * anchorX - cosine * anchorY;
    _rects[base] = rect.left;
    _rects[base + 1] = rect.top;
    _rects[base + 2] = rect.right;
    _rects[base + 3] = rect.bottom;
  }
}
