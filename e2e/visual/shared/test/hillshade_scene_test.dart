import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

void main() {
  test('hillshade uses the local DEM with deterministic illumination', () {
    final scene = jsonDecode(
      File('assets/scenes/hillshade.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final source = scene['sources']['terrain'] as Map<String, dynamic>;
    expect(source['type'], 'raster-dem');
    expect(source['tiles'], [
      '__VISUAL_E2E_ASSET_BASE__/dem/mapbox/{z}/{x}/{y}.png',
    ]);
    expect(source['encoding'], 'mapbox');
    expect(source['tileSize'], 256);
    expect(source['minzoom'], 12);
    expect(source['maxzoom'], 12);
    final terrain = (scene['layers'] as List<dynamic>).singleWhere(
      (dynamic layer) => layer['id'] == 'terrain',
    );
    expect(terrain['type'], 'hillshade');
    expect(terrain['source'], 'terrain');
    expect(terrain['paint']['hillshade-illumination-anchor'], 'map');
    expect(terrain['paint']['hillshade-illumination-direction'], 270);
    expect(terrain['paint']['hillshade-method'], 'standard');
    expect(visualE2eDesktopSceneIds, contains('hillshade'));
    expect(visualE2eSceneIdFromRoute('/visual-e2e/hillshade'), 'hillshade');
  });
}
