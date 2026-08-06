import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

void main() {
  test('fill extrusion properties match maplibre_gl JSON', () {
    const properties = FillExtrusionLayerProperties(
      fillExtrusionColor: ['get', 'color'],
      fillExtrusionHeight: ['get', 'height'],
      fillExtrusionBase: 2,
      fillExtrusionOpacity: 0.8,
      fillExtrusionVerticalGradient: true,
      visibility: 'visible',
    );

    expect(properties.toJson(), {
      'fill-extrusion-opacity': 0.8,
      'fill-extrusion-color': ['get', 'color'],
      'fill-extrusion-height': ['get', 'height'],
      'fill-extrusion-base': 2,
      'fill-extrusion-vertical-gradient': true,
      'visibility': 'visible',
    });
  });

  test('skipNulls false supports property reset semantics', () {
    const properties = FillExtrusionLayerProperties(
      fillExtrusionColor: '#00bcd4',
    );
    final json = properties.toJson(skipNulls: false);

    expect(json['fill-extrusion-color'], '#00bcd4');
    expect(json, containsPair('fill-extrusion-height', null));
    expect(json, containsPair('visibility', null));
  });

  test('fromJson and copyWith match maplibre_gl behavior', () {
    final original = FillExtrusionLayerProperties.fromJson({
      'fill-extrusion-height': 40,
      'fill-extrusion-opacity': 0.5,
    });
    final changed = original.copyWith(
      const FillExtrusionLayerProperties(fillExtrusionHeight: 80),
    );

    expect(changed.fillExtrusionHeight, 80);
    expect(changed.fillExtrusionOpacity, 0.5);
  });
}
