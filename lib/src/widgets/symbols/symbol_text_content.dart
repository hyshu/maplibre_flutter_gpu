part of 'default_symbol_builders.dart';

final _haloPaintCache = _BoundedCache<(double, double, Color), Paint>(512);

typedef _TextBlockKey = (
  InlineSpan,
  TextAlign,
  double,
  int?,
  TextDirection,
  Color,
  double,
  double,
  double,
  bool,
);

// Cached widgets resolve inherited text settings separately where mounted.
// Entries hold no build contexts, elements, or sprite images.
final _textBlockCache = _BoundedCache<_TextBlockKey, SymbolTextBlock>(8192);

/// Bounded cache that evicts its oldest entry one at a time.
///
/// Lookups are plain map reads. Eviction never clears the cache wholesale, so
/// a full cache keeps serving the entries that symbols still use.
final class _BoundedCache<K, V> {
  _BoundedCache(this.capacity);

  final int capacity;
  final _entries = <K, V>{};

  V? operator [](K key) => _entries[key];

  /// Stores [value] under [key], evicting the oldest entry when full.
  V put(K key, V value) {
    if (_entries.length >= capacity) _entries.remove(_entries.keys.first);
    _entries[key] = value;

    return value;
  }

  void clear() => _entries.clear();
}

// Identical widgets let unchanged labels skip element updates.
SymbolTextBlock _textBlock({
  required InlineSpan span,
  required TextAlign align,
  required double width,
  required int? maxLines,
  required TextDirection direction,
  required Color haloColor,
  required double haloWidth,
  required double haloBlur,
  required double inkMargin,
  required bool pixelAligned,
}) {
  final key = (
    span,
    align,
    width,
    maxLines,
    direction,
    haloColor,
    haloWidth,
    haloBlur,
    inkMargin,
    pixelAligned,
  );
  final cached = _textBlockCache[key];
  if (cached != null) return cached;
  final widget = SymbolTextBlock(
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
  );

  return _textBlockCache.put(key, widget);
}

// Stable Paint identity keeps unchanged foreground styles out of text layout.
// Cached paints must not be mutated after insertion.
Paint _haloPaint(double haloWidth, double haloBlur, Color haloColor) {
  final key = (haloWidth, haloBlur, haloColor);
  final cached = _haloPaintCache[key];
  if (cached != null) return cached;
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = haloWidth * 2
    ..strokeJoin = StrokeJoin.round
    ..maskFilter = haloBlur > 0
        ? MaskFilter.blur(BlurStyle.normal, haloBlur)
        : null
    ..color = haloColor;

  return _haloPaintCache.put(key, paint);
}
