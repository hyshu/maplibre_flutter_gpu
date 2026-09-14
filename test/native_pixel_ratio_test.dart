import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

void main() {
  test('native frontend and map options receive the same pixel ratio', () {
    final source = SourceFiles.nativeBridge;

    final frontendStart = source.indexOf(
      'g_frontend = std::make_unique<BridgeFrontend>',
    );
    expect(frontendStart, greaterThanOrEqualTo(0));
    final frontendEnd = source.indexOf(
      'mln::ResourceOptions resourceOptions;',
      frontendStart,
    );
    expect(frontendEnd, greaterThan(frontendStart));
    expect(
      source.substring(frontendStart, frontendEnd),
      contains('pixel_ratio'),
    );

    final mapOptionsStart = source.indexOf('mln::MapOptions mapOptions;');
    expect(mapOptionsStart, greaterThanOrEqualTo(0));
    final mapOptionsEnd = source.indexOf(
      'g_map = std::make_unique<mln::Map>',
      mapOptionsStart,
    );
    expect(mapOptionsEnd, greaterThan(mapOptionsStart));
    expect(
      source.substring(mapOptionsStart, mapOptionsEnd),
      contains('mapOptions.withPixelRatio(pixel_ratio);'),
    );
  });
}
