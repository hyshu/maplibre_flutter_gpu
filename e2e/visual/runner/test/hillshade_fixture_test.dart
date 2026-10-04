import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:test/test.dart';

import '../bin/generate_hillshade_tiles.dart';

void main() {
  test('Mapbox and Terrarium assets encode identical analytic terrain', () {
    for (final terrarium in [false, true]) {
      final name = terrarium ? 'terrarium' : 'mapbox';
      final tile = image.decodePng(
        File('../shared/assets/resources/hillshade-$name.png')
            .readAsBytesSync(),
      )!;
      expect(tile.width, 256);
      expect(tile.height, 256);
      for (final pixel in tile) {
        final elevation = terrarium
            ? pixel.r * 256 + pixel.g + pixel.b / 256 - 32768
            : (pixel.r * 65536 + pixel.g * 256 + pixel.b) / 10 - 10000;
        expect(elevation, hillshadeFixtureElevation(pixel.x, pixel.y));
        expect(pixel.a, 255);
      }
    }
  });

  test('DEM sample regions have known flat and directional slopes', () {
    double eastGradient(int x, int y) =>
        (hillshadeFixtureElevation(x + 1, y) -
            hillshadeFixtureElevation(x - 1, y)) /
        2;
    double southGradient(int x, int y) =>
        (hillshadeFixtureElevation(x, y + 1) -
            hillshadeFixtureElevation(x, y - 1)) /
        2;
    expect(eastGradient(64, 96), 20);
    expect(eastGradient(192, 96), -20);
    expect(eastGradient(128, 96), 0);
    expect(southGradient(128, 96), 0);
    expect(southGradient(128, 192), 14);
  });
}
