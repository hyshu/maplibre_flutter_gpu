import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native frontend and map options receive the same pixel ratio', () {
    final source = File('native/src/maplibre_bridge.cpp').readAsStringSync();

    final frontendStart = source.indexOf(
      'g_frontend = std::make_unique<BridgeFrontend>',
    );
    expect(frontendStart, greaterThanOrEqualTo(0));
    final frontendEnd = source.indexOf(
      'mbgl::ResourceOptions resourceOptions;',
      frontendStart,
    );
    expect(frontendEnd, greaterThan(frontendStart));
    expect(
      source.substring(frontendStart, frontendEnd),
      contains('pixel_ratio'),
    );

    final mapOptionsStart = source.indexOf('mbgl::MapOptions mapOptions;');
    expect(mapOptionsStart, greaterThanOrEqualTo(0));
    final mapOptionsEnd = source.indexOf(
      'g_map = std::make_unique<mbgl::Map>',
      mapOptionsStart,
    );
    expect(mapOptionsEnd, greaterThan(mapOptionsStart));
    expect(
      source.substring(mapOptionsStart, mapOptionsEnd),
      contains('mapOptions.withPixelRatio(pixel_ratio);'),
    );
  });
}
