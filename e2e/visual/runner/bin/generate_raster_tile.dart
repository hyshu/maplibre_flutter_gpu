// Generates the raster tile the `raster-pattern` visual E2E scene samples.
//
// The tile is committed as an asset, but it is generated rather than drawn by
// hand so the pattern that makes sampling errors visible is described in code:
//
//   * a thick border, so tile seams and clipping are visible;
//   * a corner block only in the top-left, so a flipped or rotated UV is
//     obvious rather than looking like a slightly different texture;
//   * a diagonal, so a transposed axis shows up as a mirrored line.
//
// Regenerate with:
//   dart run bin/generate_raster_tile.dart --output ../shared/assets/resources/raster-tile.png
import 'dart:io';

import 'package:args/args.dart';
import 'package:image/image.dart' as image;

const _size = 256;

void main(List<String> arguments) {
  final parser = ArgParser()..addOption('output', mandatory: true);
  final options = parser.parse(arguments);

  final tile = image.Image(width: _size, height: _size, numChannels: 4);
  image.fill(tile, color: image.ColorRgba8(0xc9, 0xdd, 0xe8, 0xff));

  // Diagonal first, so the border and corner block draw over it.
  image.drawLine(
    tile,
    x1: 0,
    y1: 0,
    x2: _size - 1,
    y2: _size - 1,
    color: image.ColorRgba8(0x4e, 0x8d, 0x7c, 0xff),
    thickness: 6,
  );

  image.fillRect(
    tile,
    x1: 16,
    y1: 16,
    x2: 88,
    y2: 88,
    color: image.ColorRgba8(0xd8, 0x4a, 0x5b, 0xff),
  );

  const border = 8;
  image.drawRect(
    tile,
    x1: border ~/ 2,
    y1: border ~/ 2,
    x2: _size - 1 - border ~/ 2,
    y2: _size - 1 - border ~/ 2,
    color: image.ColorRgba8(0x15, 0x3c, 0x4d, 0xff),
    thickness: border,
  );

  final output = File(options.option('output')!);
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(image.encodePng(tile));
  stdout.writeln('Wrote ${output.path} (${_size}x$_size)');
}
