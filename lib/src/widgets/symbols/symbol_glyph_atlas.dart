part of 'default_symbol_builders.dart';

/// Where one rasterized glyph lives in the atlas.
class _GlyphAtlasEntry({
  required final _GlyphAtlasPage page,

  /// Texel rectangle of the glyph image, padding included.
  required final Rect rect,

  /// Padding on each side in texels, so the glyph box center is the rectangle
  /// center.
  required final double padding,
}) {
  /// Whether the page image contains this glyph yet.
  var drawn = false;
}

/// Test and diagnostic access to the glyph atlas. Internal.
@internal
abstract final class SymbolGlyphAtlas {
  /// Whether glyphs are drawn from the atlas.
  static bool get enabled => _GlyphAtlas._enabled;

  /// Turns the atlas off, dropping its pages, or back on.
  static set enabled(bool value) {
    _GlyphAtlas._enabled = value;
    if (!value) _GlyphAtlas.clear();
  }

  /// Pages kept before the least recently used one is dropped.
  static int get pageBudget => _GlyphAtlas.pageBudget;
  static set pageBudget(int value) => _GlyphAtlas.pageBudget = value;

  /// Number of live pages.
  static int get pageCount => _GlyphAtlas._pages.length;

  /// Number of rasterized glyphs.
  static int get entryCount => _GlyphAtlas._entries.length;

  /// Drops every page.
  static void clear() => _GlyphAtlas.clear();

  /// Laid-out glyph painters kept before unreferenced ones are disposed.
  static int get painterCapacity => _GlyphPainters.capacity;
  static set painterCapacity(int value) => _GlyphPainters.capacity = value;
}

typedef _GlyphAtlasKey = (
  _GlyphPainter fill,
  _GlyphPainter? halo,
  double devicePixelRatio,
  double padding,
);

class _PendingGlyph {
  _PendingGlyph(this.key, this.entry);

  final _GlyphAtlasKey key;
  final _GlyphAtlasEntry entry;
}

/// One shelf-packed page of rasterized glyphs.
class _GlyphAtlasPage {
  _GlyphAtlasPage(this.size);

  final int size;
  ui.Image? image;
  final pending = <_PendingGlyph>[];
  final _shelves = <({double top, double height, double next})>[];
  var _nextTop = 0.0;
  var lastUsedFrame = -1;

  /// Reserves a texel rectangle, or returns null when the page is full.
  Rect? allocate(double width, double height) {
    final rowHeight = (height / 8).ceil() * 8.0;
    for (var index = 0; index < _shelves.length; index++) {
      final shelf = _shelves[index];
      if (shelf.height < rowHeight ||
          shelf.height > rowHeight * 1.5 ||
          shelf.next + width > size) {
        continue;
      }
      _shelves[index] = (
        top: shelf.top,
        height: shelf.height,
        next: shelf.next + width,
      );

      return Rect.fromLTWH(shelf.next, shelf.top, width, height);
    }
    if (_nextTop + rowHeight > size || width > size) return null;
    final shelf = (top: _nextTop, height: rowHeight, next: width);
    _shelves.add(shelf);
    _nextTop += rowHeight;

    return Rect.fromLTWH(0, shelf.top, width, height);
  }

  /// Draws the pending glyphs over the current image into a new image.
  void flush() {
    if (pending.isEmpty) return;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final previous = image;
    if (previous != null) canvas.drawImage(previous, Offset.zero, Paint());
    for (final glyph in pending) {
      final (fill, halo, devicePixelRatio, padding) = glyph.key;
      final rect = glyph.entry.rect;
      canvas
        ..save()
        ..translate(rect.left + padding, rect.top + padding)
        ..scale(devicePixelRatio);
      halo?.painter.paint(canvas, Offset.zero);
      fill.painter.paint(canvas, Offset.zero);
      canvas.restore();
    }
    final picture = recorder.endRecording();
    try {
      image = picture.toImageSync(size, size);
    } finally {
      picture.dispose();
    }
    for (final glyph in pending) {
      glyph.entry.drawn = true;
    }
    pending.clear();
    previous?.dispose();
  }

  void dispose() {
    image?.dispose();
    image = null;
    pending.clear();
  }
}

/// Samples atlas texels bilinearly, for scaled or rotated glyphs.
final _atlasPaint = Paint()..filterQuality = FilterQuality.low;

/// Copies atlas texels one to one, for glyphs that land on device pixels.
final _nearestAtlasPaint = Paint()..filterQuality = FilterQuality.none;

/// Process-wide store of rasterized label glyphs.
///
/// Glyphs are rasterized once at the device pixel ratio into shelf-packed
/// pages, so a label paints as one textured batch per page instead of a text
/// draw per glyph. Pages are rebuilt when glyphs are added, at most a few
/// times per frame; glyphs that cannot be placed yet paint from their text
/// painter until the next frame. The store disables itself when the engine
/// cannot rasterize a page.
abstract final class _GlyphAtlas {
  static const pageSize = 1024;

  /// Pages kept before the least recently used one is dropped.
  static var pageBudget = 12;

  /// Page flushes allowed per frame.
  static const _flushesPerFrame = 2;

  static final _entries = <_GlyphAtlasKey, _GlyphAtlasEntry>{};
  static final _pages = <_GlyphAtlasPage>[];
  static var _enabled = true;
  static var _frame = 0;
  static var _flushesThisFrame = 0;
  static var _frameCallbackScheduled = false;

  /// Drops every page, for tests and for a changed system font set.
  static void clear() {
    for (final page in _pages) {
      page.dispose();
    }
    for (final key in _entries.keys) {
      key.$1.atlasKeys.clear();
      key.$2?.atlasKeys.clear();
    }
    _pages.clear();
    _entries.clear();
  }

  /// Forgets the glyphs rasterized from a painter that is being disposed.
  static void forget(_GlyphPainter painter) {
    for (final key in painter.atlasKeys.toList()) {
      _removeEntry(key);
    }
  }

  /// Drops one glyph, including one placed on a page but not drawn into it
  /// yet.
  static void _removeEntry(_GlyphAtlasKey key) {
    final entry = _entries.remove(key);
    key.$1.atlasKeys.remove(key);
    key.$2?.atlasKeys.remove(key);
    if (entry != null && !entry.drawn) {
      entry.page.pending.removeWhere((glyph) => identical(glyph.entry, entry));
    }
  }

  /// Returns the entry for a glyph, rasterizing it when needed, or null when
  /// the glyph must be painted directly this frame.
  static _GlyphAtlasEntry? entryFor(
    _GlyphPainter fill,
    _GlyphPainter? halo,
    double devicePixelRatio,
    double padding,
  ) {
    if (!_enabled) return null;
    final key = (fill, halo, devicePixelRatio, padding);
    final existing = _entries[key];
    if (existing != null) {
      existing.page.lastUsedFrame = _frame;

      return existing;
    }
    _beginFrameIfNeeded();
    final size = fill.painter.size;
    final width = (size.width * devicePixelRatio + padding * 2).ceilToDouble();
    final height = (size.height * devicePixelRatio + padding * 2)
        .ceilToDouble();
    if (width > pageSize || height > pageSize) return null;
    var page = _pages.isEmpty ? null : _pages.last;
    var rect = page?.allocate(width, height);
    if (rect == null) {
      page = _openPage();
      if (page == null) return null;
      rect = page.allocate(width, height)!;
    }
    final entry = _entries[key] = _GlyphAtlasEntry(
      page: page!,
      rect: rect,
      padding: padding,
    );
    page.pending.add(_PendingGlyph(key, entry));
    page.lastUsedFrame = _frame;
    fill.atlasKeys.add(key);
    halo?.atlasKeys.add(key);

    return entry;
  }

  /// Draws a page's pending glyphs. Returns false when the atlas was disabled.
  static bool _flushPage(_GlyphAtlasPage page) {
    try {
      page.flush();
    } on Object catch (error, stackTrace) {
      // The engine could not rasterize a page; fall back to text painting.
      _enabled = false;
      clear();
      SymbolProfileCounters.add(SymbolProfileCounters.atlasDisabled);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'maplibre_flutter_gpu',
          context: ErrorDescription('while rasterizing a symbol glyph page'),
        ),
      );

      return false;
    }
    _flushesThisFrame++;
    SymbolProfileCounters.add(SymbolProfileCounters.atlasFlushes);

    return true;
  }

  /// Draws the page holding [entry] if the glyph is not in it yet.
  ///
  /// Returns false when the glyph must be painted directly this frame because
  /// the page cannot be rebuilt again until the next frame.
  static bool prepare(_GlyphAtlasEntry entry) {
    if (entry.drawn) return true;
    if (_flushesThisFrame >= _flushesPerFrame) return false;

    return _flushPage(entry.page) && entry.drawn;
  }

  static _GlyphAtlasPage? _openPage() {
    if (_pages.length >= pageBudget) {
      // Drop the page least recently drawn, unless everything was drawn this
      // frame, in which case the new glyphs paint directly until a page frees.
      _GlyphAtlasPage? victim;
      for (final page in _pages) {
        if (page.lastUsedFrame >= _frame) continue;
        if (victim == null || page.lastUsedFrame < victim.lastUsedFrame) {
          victim = page;
        }
      }
      if (victim == null) return null;
      for (final key in [
        for (final entry in _entries.entries)
          if (entry.value.page == victim) entry.key,
      ]) {
        _removeEntry(key);
      }
      _pages.remove(victim);
      victim.dispose();
    }
    final page = _GlyphAtlasPage(pageSize);
    _pages.add(page);

    return page;
  }

  static void _beginFrameIfNeeded() {
    if (_frameCallbackScheduled) return;
    _frameCallbackScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _frameCallbackScheduled = false;
      _frame++;
      _flushesThisFrame = 0;
      // Pages that still hold undrawn glyphs are completed next frame.
      for (final page in _pages) {
        if (page.pending.isNotEmpty) {
          _beginFrameIfNeeded();
          break;
        }
      }
    });
  }
}
