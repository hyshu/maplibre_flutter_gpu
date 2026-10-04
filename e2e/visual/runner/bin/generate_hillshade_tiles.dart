// Generates deterministic Mapbox and Terrarium DEMs for the hillshade scene.
import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:image/image.dart' as image;

/// Elevation in meters for a plateau with east, west, and south slopes.
double hillshadeFixtureElevation(int x, int y) =>
    1000 + 20 * math.min(96, math.min(x, 255 - x)) + 14 * math.max(0, y - 160);

/// Encodes the same terrain in either supported raster DEM format.
image.Image createHillshadeDem({required bool terrarium}) {
  final tile = image.Image(width: 256, height: 256, numChannels: 4);
  for (final pixel in tile) {
    final elevation = hillshadeFixtureElevation(pixel.x, pixel.y);
    final encoded = terrarium
        ? ((elevation + 32768) * 256).round()
        : ((elevation + 10000) * 10).round();
    pixel
      ..r = (encoded >> 16) & 0xff
      ..g = (encoded >> 8) & 0xff
      ..b = encoded & 0xff
      ..a = 255;
  }
  return tile;
}

void main(List<String> arguments) {
  final parser = ArgParser()..addOption('output-directory', mandatory: true);
  final options = parser.parse(arguments);
  final directory = Directory(options.option('output-directory')!);
  directory.createSync(recursive: true);
  for (final terrarium in [false, true]) {
    final name = terrarium ? 'hillshade-terrarium.png' : 'hillshade-mapbox.png';
    final output = File('${directory.path}/$name');
    output.writeAsBytesSync(
      image.encodePng(createHillshadeDem(terrarium: terrarium)),
    );
    stdout.writeln('Wrote ${output.path} (256x256)');
  }
}
