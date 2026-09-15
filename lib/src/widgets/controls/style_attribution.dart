/// Parses attribution labels and links resolved from style sources.
///
/// Duplicate entries are omitted. Plain text is retained when an attribution
/// value contains no links.
List<({String label, String? url})> parseStyleAttributions(
  Iterable<String> values,
) {
  final result = <({String label, String? url})>[];
  final seen = <(String, String?)>{};
  for (final value in values) {
    for (final entry in _parseAttribution(value)) {
      if (seen.add((entry.label, entry.url))) result.add(entry);
    }
  }

  return result;
}

List<({String label, String? url})> _parseAttribution(String value) {
  final anchorPattern = RegExp(
    r'<a\b([^>]*)>(.*?)</a\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  final result = <({String label, String? url})>[];
  for (final match in anchorPattern.allMatches(value)) {
    final label = _plainAttributionText(match.group(2)!);
    if (label.isEmpty) continue;
    final href = _hrefFromAttributes(match.group(1)!);
    result.add((label: label, url: href));
  }
  if (result.isEmpty) {
    final label = _plainAttributionText(value);
    if (label.isNotEmpty) result.add((label: label, url: null));
  }

  return result;
}

String? _hrefFromAttributes(String attributes) {
  final match = RegExp(
    r'''\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
    caseSensitive: false,
  ).firstMatch(attributes);
  final value = match?.group(1) ?? match?.group(2) ?? match?.group(3);
  final decoded = value == null ? '' : _decodeHtmlEntities(value).trim();

  return decoded.isEmpty ? null : decoded;
}

String _plainAttributionText(String value) =>
    _decodeHtmlEntities(value.replaceAll(RegExp(r'<[^>]*>'), ' '))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

String _decodeHtmlEntities(String value) {
  const named = {
    'amp': '&',
    'apos': "'",
    'copy': '©',
    'gt': '>',
    'lt': '<',
    'nbsp': ' ',
    'quot': '"',
    'reg': '®',
    'trade': '™',
  };

  return value.replaceAllMapped(
    RegExp(r'&(#(?:x[0-9a-f]+|\d+)|[a-z]+);', caseSensitive: false),
    (match) {
      final entity = match.group(1)!;
      if (!entity.startsWith('#')) {
        return named[entity.toLowerCase()] ?? match[0]!;
      }
      final hexadecimal = entity.length > 2 && entity[1].toLowerCase() == 'x';
      final codePoint = int.tryParse(
        entity.substring(hexadecimal ? 2 : 1),
        radix: hexadecimal ? 16 : 10,
      );

      return codePoint == null ? match[0]! : String.fromCharCode(codePoint);
    },
  );
}
