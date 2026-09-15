part of 'default_symbol_builders.dart';

typedef _MapLibreFont = ({String? family, FontWeight weight, FontStyle style});

const _maxMapLibreFontCacheEntries = 256;
final _mapLibreFontCache = <String, _MapLibreFont>{};

/// Resolves a Flutter font description from a MapLibre font stack.
({String? family, List<String>? fallback, FontWeight? weight, FontStyle? style})
_mapLibreFonts(Iterable<String> fontNames) {
  final fonts = [
    for (final name in fontNames)
      if (name.isNotEmpty) name,
  ];
  if (fonts.isEmpty) {
    return (family: null, fallback: null, weight: null, style: null);
  }
  final primary = _mapLibreFont(fonts.first);
  final fallback = <String>[];
  for (final name in fonts.skip(1)) {
    final family = _mapLibreFont(name).family;
    if (family != null &&
        family != primary.family &&
        !fallback.contains(family)) {
      fallback.add(family);
    }
  }

  return (
    family: primary.family,
    fallback: fallback.isEmpty ? null : List.unmodifiable(fallback),
    weight: primary.weight,
    style: primary.style,
  );
}

_MapLibreFont _mapLibreFont(String fontName) {
  final cached = _mapLibreFontCache[fontName];
  if (cached != null) return cached;
  final lower = fontName.toLowerCase();
  final weight = lower.contains('black') || lower.contains('heavy')
      ? FontWeight.w900
      : lower.contains('extra bold') || lower.contains('extrabold')
      ? FontWeight.w800
      : lower.contains('semi bold') ||
            lower.contains('semibold') ||
            lower.contains('demi bold') ||
            lower.contains('demibold')
      ? FontWeight.w600
      : lower.contains('bold')
      ? FontWeight.w700
      : lower.contains('medium')
      ? FontWeight.w500
      : lower.contains('light')
      ? FontWeight.w300
      : lower.contains('thin')
      ? FontWeight.w100
      : FontWeight.w400;
  final style = lower.contains('italic') || lower.contains('oblique')
      ? FontStyle.italic
      : FontStyle.normal;
  final family = fontName
      .replaceFirst(
        RegExp(
          r'(?:\s+(?:extra\s*bold|semi\s*bold|demi\s*bold|'
          r'black|heavy|bold|medium|regular|italic|oblique|light|thin))+$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  final result = (
    family: family.isEmpty ? null : family,
    weight: weight,
    style: style,
  );
  if (_mapLibreFontCache.length >= _maxMapLibreFontCacheEntries) {
    _mapLibreFontCache.clear();
  }
  _mapLibreFontCache[fontName] = result;

  return result;
}
