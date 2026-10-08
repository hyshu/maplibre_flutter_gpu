part of 'default_symbol_builders.dart';

final _haloPaintCache = <(double, double, Color), Paint>{};

// Cached widgets resolve inherited text settings separately where mounted.
// Entries hold no build contexts, elements, or sprite images.
final _glyphTextCache =
    <(String, TextStyle, TextDirection, double, double, Color), Widget>{};
final _pointTextCache =
    <(String, TextStyle, TextDirection, TextAlign, int?), Text>{};

Widget _glyphText(String text, TextStyle style, LabelData data) {
  final glyphStyle = style.copyWith(height: 1);
  final key = (
    text,
    glyphStyle,
    data.textDirection,
    data.haloWidth,
    data.haloBlur,
    data.haloColor,
  );
  final cached = _glyphTextCache[key];
  if (cached != null) return cached;
  final fill = Text(text, style: glyphStyle, textDirection: data.textDirection);
  final visual = data.haloWidth <= 0
      ? fill
      : Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Text(
              text,
              style: _haloStyle(glyphStyle, data),
              textDirection: data.textDirection,
            ),
            fill,
          ],
        );

  return _cacheSymbolContent(_glyphTextCache, key, visual, 4096);
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

  return _cacheSymbolContent(_pointTextCache, key, widget, 2048);
}

// Stable Paint identity keeps unchanged foreground styles out of text layout.
// Cached paints must not be mutated after insertion.
Paint _haloPaint(LabelData data) {
  final key = (data.haloWidth, data.haloBlur, data.haloColor);
  final cached = _haloPaintCache[key];
  if (cached != null) return cached;
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = data.haloWidth * 2
    ..strokeJoin = StrokeJoin.round
    ..maskFilter = data.haloBlur > 0
        ? MaskFilter.blur(BlurStyle.normal, data.haloBlur)
        : null
    ..color = data.haloColor;

  return _cacheSymbolContent(_haloPaintCache, key, paint, 512);
}

V _cacheSymbolContent<K, V>(Map<K, V> cache, K key, V value, int capacity) {
  if (cache.length >= capacity) cache.remove(cache.keys.first);
  cache[key] = value;

  return value;
}
