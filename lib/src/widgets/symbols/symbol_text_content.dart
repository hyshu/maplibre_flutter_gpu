part of 'default_symbol_builders.dart';

final _haloPaintCache = _BoundedCache<(double, double, Color), Paint>(512);

// Cached widgets resolve inherited text settings separately where mounted.
// Entries hold no build contexts, elements, or sprite images.
final _glyphTextCache =
    _BoundedCache<
      (String, TextStyle, TextDirection, double, double, Color),
      Widget
    >(4096);
final _pointTextCache =
    _BoundedCache<(String, TextStyle, TextDirection, TextAlign, int?), Text>(
      2048,
    );

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

Widget _glyphText(
  String text,
  TextStyle style,
  DefaultTextScale scale,
  LabelData data,
) {
  final glyphStyle = style.copyWith(height: 1);
  final key = (
    text,
    glyphStyle,
    data.textDirection,
    scale.haloWidth,
    scale.haloBlur,
    data.haloColor,
  );
  final cached = _glyphTextCache[key];
  if (cached != null) return cached;
  final fill = Text(text, style: glyphStyle, textDirection: data.textDirection);
  final visual = scale.haloWidth <= 0
      ? fill
      : Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Text(
              text,
              style: _haloStyle(glyphStyle, scale, data.haloColor),
              textDirection: data.textDirection,
            ),
            fill,
          ],
        );

  return _glyphTextCache.put(key, visual);
}

Text _pointText(
  String text, {
  required TextStyle style,
  required TextDirection direction,
  required TextAlign align,
  required int? maxLines,
}) {
  final key = (text, style, direction, align, maxLines);
  final cached = _pointTextCache[key];
  if (cached != null) return cached;
  final widget = Text(
    text,
    style: style,
    textAlign: align,
    textDirection: direction,
    softWrap: false,
    maxLines: maxLines,
    overflow: TextOverflow.visible,
  );

  return _pointTextCache.put(key, widget);
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
