part of '../visual_e2e_shared.dart';

/// Replaces Liberty's hosted Noto Sans faces with fonts built into the target
/// OS. Both visual E2E apps receive this same transformed style, so MapLibre's
/// native placement and Flutter's text overlay use matching font metrics.
String configureFlutterMarkersSystemFonts(
  String styleJson, {
  required TargetPlatform platform,
}) {
  final style = jsonDecode(styleJson) as Map<String, dynamic>;
  final fontConfig = switch (platform) {
    .iOS => _iosSystemFonts,
    .android => _androidSystemFonts,
    _ => throw UnsupportedError(
      'flutter-markers visual E2E supports iOS and Android only',
    ),
  };

  style['font-faces'] = fontConfig.faces;
  final layers = style['layers'];
  if (layers is List) {
    for (final value in layers) {
      if (value is! Map<String, dynamic> || value['type'] != 'symbol') {
        continue;
      }
      final layout = value['layout'];
      if (layout is! Map<String, dynamic>) continue;
      final textFont = layout['text-font'];
      if (textFont is! List || textFont.isEmpty) continue;
      final sourceFace = textFont.first;
      if (sourceFace is! String) continue;
      layout['text-font'] = [_systemFaceName(sourceFace, fontConfig.names)];
    }
  }
  return jsonEncode(style);
}

String _systemFaceName(String source, _SystemFontNames names) {
  final lower = source.toLowerCase();
  if (lower.contains('italic') || lower.contains('oblique')) {
    return names.italic;
  }
  if (lower.contains('bold') ||
      lower.contains('black') ||
      lower.contains('heavy')) {
    return names.bold;
  }
  return names.regular;
}

typedef _SystemFontNames = ({String regular, String bold, String italic});

const _latinRange = <String>['U+0000-2FFF'];
const _cjkRange = <String>['U+3000-10FFFF'];

const _iosSystemFonts = (
  names: (regular: 'Arial', bold: 'Arial Bold', italic: 'Arial Italic'),
  faces: <String, List<Map<String, Object>>>{
    'Arial': [
      {
        'url': 'file:///System/Library/Fonts/Supplemental/Arial.ttf',
        'unicode-range': _latinRange,
      },
      {
        'url': 'file:///System/Library/Fonts/Supplemental/Arial%20Unicode.ttf',
        'unicode-range': _cjkRange,
      },
    ],
    'Arial Bold': [
      {
        'url': 'file:///System/Library/Fonts/Supplemental/Arial%20Bold.ttf',
        'unicode-range': _latinRange,
      },
      {
        'url': 'file:///System/Library/Fonts/Supplemental/Arial%20Unicode.ttf',
        'unicode-range': _cjkRange,
      },
    ],
    'Arial Italic': [
      {
        'url': 'file:///System/Library/Fonts/Supplemental/Arial%20Italic.ttf',
        'unicode-range': _latinRange,
      },
      {
        'url': 'file:///System/Library/Fonts/Supplemental/Arial%20Unicode.ttf',
        'unicode-range': _cjkRange,
      },
    ],
  },
);

const _androidSystemFonts = (
  names: (
    regular: 'source-sans-pro Regular',
    bold: 'source-sans-pro Bold',
    italic: 'source-sans-pro Italic',
  ),
  faces: <String, List<Map<String, Object>>>{
    'source-sans-pro Regular': [
      {
        'url': 'file:///system/fonts/SourceSansPro-Regular.ttf',
        'unicode-range': _latinRange,
      },
      {
        'url': 'file:///system/fonts/NotoSansCJK-Regular.ttc',
        'unicode-range': _cjkRange,
      },
    ],
    'source-sans-pro Bold': [
      {
        'url': 'file:///system/fonts/SourceSansPro-Bold.ttf',
        'unicode-range': _latinRange,
      },
      {
        'url': 'file:///system/fonts/NotoSansCJK-Regular.ttc',
        'unicode-range': _cjkRange,
      },
    ],
    'source-sans-pro Italic': [
      {
        'url': 'file:///system/fonts/SourceSansPro-Italic.ttf',
        'unicode-range': _latinRange,
      },
      {
        'url': 'file:///system/fonts/NotoSansCJK-Regular.ttc',
        'unicode-range': _cjkRange,
      },
    ],
  },
);
