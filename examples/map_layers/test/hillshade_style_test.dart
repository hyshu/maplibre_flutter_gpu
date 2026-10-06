import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_map_layers_example/hillshade_style.dart';

void main() {
  test('adds a raster-dem source and flat shading below labels', () {
    final basemap = <String, dynamic>{
      'version': 8,
      'glyphs': 'https://example.com/{fontstack}/{range}.pbf',
      'sources': {
        'basemap': {'type': 'vector', 'url': 'https://example.com/tiles.json'},
      },
      'layers': [
        {'id': 'land', 'type': 'background'},
        {'id': 'labels', 'type': 'symbol'},
      ],
    };
    final original = jsonEncode(basemap);
    final result = buildHillshadeStyle(basemap, visible: false);
    final layers = result['layers'] as List;

    expect(layers.map((layer) => layer['id']), [
      'land',
      hillshadeLayerId,
      'labels',
    ]);
    expect(layers[1]['type'], 'hillshade');
    expect(layers[1]['layout'], {'visibility': 'none'});
    expect(layers[1]['paint'], {
      ...const HillshadeSettings().properties.toJson()..remove('visibility'),
    });
    expect(result['sources'][elevationSourceId], {
      'type': 'raster-dem',
      'url': elevationDataUrl,
      'tileSize': 256,
      'encoding': 'mapbox',
      'attribution':
          '<a href="https://earth.jaxa.jp/en/data/policy/">AW3D30 (JAXA)</a>',
    });
    expect(result['sources']['basemap'], basemap['sources']!['basemap']);
    expect(result['glyphs'], basemap['glyphs']);
    expect(result, isNot(contains('terrain')));
    expect(jsonEncode(basemap), original);
  });

  test('supports a style without labels', () {
    final result = buildHillshadeStyle({
      'version': 8,
      'sources': <String, dynamic>{},
      'layers': <Object>[],
    });

    expect((result['layers'] as List).single['layout'], {
      'visibility': 'visible',
    });
  });

  test(
    'multidirectional settings wrap three lights and retain zero strength',
    () {
      final settings = const HillshadeSettings().copyWith(
        exaggeration: 0,
        direction: 359,
        altitude: 60,
        method: 'multidirectional',
        anchoredToMap: false,
        visible: false,
      );
      final properties = settings.properties;

      expect(properties.hillshadeIlluminationDirection, [359, 119, 239]);
      expect(properties.hillshadeIlluminationAltitude, 60);
      expect(properties.hillshadeIlluminationAnchor, 'viewport');
      expect(properties.hillshadeExaggeration, 0);
      expect(properties.visibility, 'none');
      expect(
        settings
            .copyWith(method: 'basic')
            .properties
            .hillshadeIlluminationDirection,
        359,
      );
    },
  );
}
