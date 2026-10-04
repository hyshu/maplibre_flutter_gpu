import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_map_layers_example/heatmap_style.dart';

void main() {
  test(
    'inserts density and points below labels and preserves basemap sources',
    () {
      final basemap = <String, dynamic>{
        'version': 8,
        'glyphs': 'https://example.com/{fontstack}/{range}.pbf',
        'sources': {
          'basemap': {
            'type': 'vector',
            'url': 'https://example.com/tiles.json',
          },
        },
        'layers': [
          {'id': 'land', 'type': 'background'},
          {'id': 'labels', 'type': 'symbol'},
        ],
      };
      final original = jsonEncode(basemap);
      final points = {'type': 'FeatureCollection', 'features': <Object>[]};
      final result = buildHeatmapStyle(basemap, points);
      final layers = result['layers'] as List;

      expect(layers.map((layer) => layer['id']), [
        'land',
        heatmapLayerId,
        pointLayerId,
        'labels',
      ]);
      expect(result['sources']['basemap'], basemap['sources']!['basemap']);
      expect(result['sources'][earthquakeSourceId]['data'], same(points));
      expect(result['glyphs'], basemap['glyphs']);
      expect(layers[2]['layout']['visibility'], 'none');
      expect(jsonEncode(basemap), original);
    },
  );

  test('supports basemaps without labels', () {
    final result = buildHeatmapStyle(
      {'version': 8, 'sources': <String, dynamic>{}, 'layers': <Object>[]},
      {'type': 'FeatureCollection', 'features': <Object>[]},
    );

    expect((result['layers'] as List).map((layer) => layer['id']), [
      heatmapLayerId,
      pointLayerId,
    ]);
  });
}
