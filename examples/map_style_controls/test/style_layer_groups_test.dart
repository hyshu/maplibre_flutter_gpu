import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_map_style_controls_example/style_layer_groups.dart';

void main() {
  final style = jsonEncode({
    'version': 8,
    'layers': [
      {
        'id': 'building-3d',
        'type': 'fill-extrusion',
        'source-layer': 'building',
      },
      {'id': 'road-primary', 'type': 'line', 'source-layer': 'transportation'},
      {'id': 'water', 'type': 'fill', 'source-layer': 'water'},
      {
        'id': 'city-label',
        'type': 'symbol',
        'source-layer': 'place',
        'layout': {
          'text-field': ['get', 'name'],
          'icon-image': 'dot',
        },
      },
      {
        'id': 'poi-cafe',
        'type': 'symbol',
        'source-layer': 'poi',
        'layout': {
          'text-field': ['get', 'name'],
          'icon-image': 'cafe',
        },
      },
      {
        'id': 'road-one-way-arrow',
        'type': 'symbol',
        'source-layer': 'transportation',
        'layout': {'icon-image': 'arrow'},
      },
    ],
  });

  test('maps technical style layers to user-facing groups', () {
    final catalog = StyleLayerCatalog.fromStyle(style);

    expect(catalog[StyleLayerGroup.buildings3d], ['building-3d']);
    expect(catalog[StyleLayerGroup.roads], ['road-primary']);
    expect(catalog[StyleLayerGroup.water], ['water']);
    expect(catalog[StyleLayerGroup.labels], ['city-label']);
    expect(catalog[StyleLayerGroup.symbols], [
      'poi-cafe',
      'road-one-way-arrow',
    ]);
  });

  test('missing layer collections produce empty groups', () {
    final catalog = StyleLayerCatalog.fromStyle(
      jsonEncode({'version': 8, 'layers': <Object>[]}),
    );

    for (final group in StyleLayerGroup.values) {
      expect(catalog[group], isEmpty);
    }
  });
}
