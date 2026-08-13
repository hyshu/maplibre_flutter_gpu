import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

const _style = '''
{
  "version": 8,
  "glyphs": "https://example.test/{fontstack}/{range}.pbf",
  "sources": {},
  "layers": [
    {
      "id": "regular",
      "type": "symbol",
      "layout": {"text-field": "Regular", "text-font": ["Noto Sans Regular"]}
    },
    {
      "id": "bold",
      "type": "symbol",
      "layout": {"text-field": "Bold", "text-font": ["Noto Sans Bold"]}
    },
    {
      "id": "italic",
      "type": "symbol",
      "layout": {"text-field": "Italic", "text-font": ["Noto Sans Italic"]}
    },
    {
      "id": "icon-only",
      "type": "symbol",
      "layout": {"icon-image": "airport"}
    },
    {
      "id": "background",
      "type": "background"
    }
  ]
}
''';

void main() {
  test('configures iOS built-in Arial font files', () {
    final style = _configure(TargetPlatform.iOS);

    expect(_textFont(style, 'regular'), 'Arial');
    expect(_textFont(style, 'bold'), 'Arial Bold');
    expect(_textFont(style, 'italic'), 'Arial Italic');
    expect(_layout(style, 'icon-only'), isNot(contains('text-font')));
    expect(style['glyphs'], 'https://example.test/{fontstack}/{range}.pbf');

    final faces = style['font-faces'] as Map<String, dynamic>;
    expect(
      faces.keys,
      containsAll(<String>['Arial', 'Arial Bold', 'Arial Italic']),
    );
    _expectFace(
      faces,
      'Arial',
      latinUrl: 'file:///System/Library/Fonts/Supplemental/Arial.ttf',
      cjkUrl: 'file:///System/Library/Fonts/Supplemental/Arial%20Unicode.ttf',
    );
  });

  test('configures Android built-in Source Sans Pro and CJK font files', () {
    final style = _configure(TargetPlatform.android);

    expect(_textFont(style, 'regular'), 'source-sans-pro Regular');
    expect(_textFont(style, 'bold'), 'source-sans-pro Bold');
    expect(_textFont(style, 'italic'), 'source-sans-pro Italic');

    final faces = style['font-faces'] as Map<String, dynamic>;
    expect(
      faces.keys,
      containsAll(<String>[
        'source-sans-pro Regular',
        'source-sans-pro Bold',
        'source-sans-pro Italic',
      ]),
    );
    _expectFace(
      faces,
      'source-sans-pro Regular',
      latinUrl: 'file:///system/fonts/SourceSansPro-Regular.ttf',
      cjkUrl: 'file:///system/fonts/NotoSansCJK-Regular.ttc',
    );
  });

  test('rejects unsupported visual E2E platforms', () {
    expect(
      () => configureFlutterMarkersSystemFonts(
        _style,
        platform: TargetPlatform.macOS,
      ),
      throwsUnsupportedError,
    );
  });
}

Map<String, dynamic> _configure(TargetPlatform platform) {
  return jsonDecode(
    configureFlutterMarkersSystemFonts(_style, platform: platform),
  ) as Map<String, dynamic>;
}

Map<String, dynamic> _layout(Map<String, dynamic> style, String id) {
  final layers = style['layers'] as List<dynamic>;
  final layer = layers.cast<Map<String, dynamic>>().singleWhere(
    (Map<String, dynamic> value) => value['id'] == id,
  );

  return layer['layout'] as Map<String, dynamic>;
}

String _textFont(Map<String, dynamic> style, String id) {
  return (_layout(style, id)['text-font'] as List<dynamic>).single as String;
}

void _expectFace(
  Map<String, dynamic> faces,
  String name, {
  required String latinUrl,
  required String cjkUrl,
}) {
  final files = faces[name] as List<dynamic>;
  expect(files, hasLength(2));
  expect(files[0], <String, Object>{
    'url': latinUrl,
    'unicode-range': <String>['U+0000-2FFF'],
  });
  expect(files[1], <String, Object>{
    'url': cjkUrl,
    'unicode-range': <String>['U+3000-10FFFF'],
  });
}
