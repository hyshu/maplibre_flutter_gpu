part of 'default_symbol_builders.dart';

/// One glyph or inline image painted by a [SymbolGlyphRun].
///
/// [size] is the glyph box in shaped units. [center] is the box center in the
/// run's coordinates, and [transform] rotates and scales the box around that
/// center. This class is internal and is not exported by the package barrel.
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
  required final Matrix4 transform,
}) {
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
      devicePixelRatio == other.devicePixelRatio;

  @override
  int get hashCode => Object.hash(
    defaultStyle,
    scaler,
    boldText,
    heightBehavior,
    devicePixelRatio,
  );

  /// Resolves [style] the way [Text] resolves its style.
  TextStyle resolve(TextStyle style) {
    final merged = defaultStyle.merge(style);

    return boldText ? merged.merge(const TextStyle(fontWeight: .bold)) : merged;
  }
}

typedef _GlyphPainterKey = (
  String,
  TextStyle,
  TextDirection,
  TextScaler,
  TextHeightBehavior?,
);

/// A laid-out painter shared by every run that paints the same glyph.
class _GlyphPainter {
  _GlyphPainter(this.painter);

  final TextPainter painter;
  var references = 0;
  var evicted = false;

  void release() {
    references--;
    if (references == 0 && evicted) painter.dispose();
  }
}

/// Shares laid-out text painters between glyph runs.
///
/// Painters stay alive while any run references them. Eviction removes
/// unreferenced painters first and disposes referenced ones once released.
abstract final class _GlyphPainters {
  static const _capacity = 8192;
  static final _entries = <_GlyphPainterKey, _GlyphPainter>{};
  static var _listensForSystemFontChanges = false;

  static _GlyphPainter acquire(
    String text,
    TextStyle style,
    TextDirection direction,
    SymbolTextSettings settings,
  ) {
    if (!_listensForSystemFontChanges) {
      PaintingBinding.instance.systemFonts.addListener(_evictAll);
      _listensForSystemFontChanges = true;
    }
    final key = (
      text,
      style,
      direction,
      settings.scaler,
      settings.heightBehavior,
    );
    var entry = _entries[key];
    if (entry == null) {
      if (_entries.length >= _capacity) _evictUnreferenced();
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: settings.scaler,
        textHeightBehavior: settings.heightBehavior,
        maxLines: 1,
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
      entry.value.painter.dispose();
      removed.add(entry.key);
      if (removed.length >= _capacity ~/ 8) break;
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
        _GlyphPainters.acquire(glyph.text, style, _direction, _settings),
      );
      halos.add(
        _haloWidth <= 0
            ? null
            : _GlyphPainters.acquire(
                glyph.text,
                style.copyWith(
                  foreground: _haloPaint(_haloWidth, _haloBlur, _haloColor),
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

  @override
  void paint(PaintingContext context, Offset offset) {
    _ensurePainters();
    final canvas = context.canvas;
    for (var index = 0; index < _glyphs.length; index++) {
      final glyph = _glyphs[index];
      final box = glyph.size;
      canvas
        ..save()
        ..translate(offset.dx + glyph.center.dx, offset.dy + glyph.center.dy)
        ..transform(glyph.transform.storage)
        ..translate(-box.width / 2, -box.height / 2);
      final image = glyph.image;
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
          devicePixelRatio: _settings.devicePixelRatio,
        );
      } else {
        _halos![index]?.painter.paint(canvas, Offset.zero);
        _fills![index]!.painter.paint(canvas, Offset.zero);
      }
      canvas.restore();
    }
  }
}
