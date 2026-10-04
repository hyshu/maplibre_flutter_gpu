import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

/// Checks density accumulation, paint expressions, and composition in the
/// fixed 800 by 600 heatmap scene captured at a pixel ratio of two.
({Map<String, List<double>> samples, List<String> failures})
analyzeHeatmapScenePng(Uint8List png) {
  final decoded = image.decodePng(png);
  if (decoded == null) throw const FormatException('Invalid heatmap PNG');
  if (decoded.width != 1600 || decoded.height != 1200) {
    return (
      samples: {},
      failures: ['Heatmap capture must be 1600 by 1200 pixels.'],
    );
  }
  final samples = <String, List<double>>{
    'isolated': _sample(decoded, longitude: -10, latitude: 7),
    'overlap': _sample(decoded, longitude: 0, latitude: 7),
    'weighted': _sample(decoded, longitude: 10, latitude: 7),
    'falloff': _sample(decoded, longitude: -10, latitude: 7, offsetX: 35),
    'smallRadius': _sample(decoded, longitude: -10, latitude: -6, offsetX: 30),
    'largeRadius': _sample(decoded, longitude: 0, latitude: -6, offsetX: 30),
    'secondHeatmap': _sample(decoded, longitude: 10, latitude: -6, offsetX: 25),
    'underlay': _sample(decoded, longitude: 10, latitude: -6, offsetX: 65),
    'foreground': _sample(decoded, longitude: 10, latitude: -6),
  };
  final failures = <String>[];
  void expectColor(String name, List<double> expected, double tolerance) {
    final actual = samples[name]!;
    if (List.generate(
      3,
      (index) => index,
    ).any((index) => (actual[index] - expected[index]).abs() > tolerance)) {
      failures.add(
        '$name RGB ${actual.map((channel) => channel.toStringAsFixed(1)).join(', ')} '
        'does not match ${expected.join(', ')} within $tolerance.',
      );
    }
  }

  // At a point center, Gaussian density is weight times intensity divided
  // by sqrt(2 pi). These colors include the fixture's ramp and 0.75 opacity.
  expectColor('isolated', [58, 177, 252], 30);
  expectColor('overlap', [249, 118, 61], 30);
  expectColor('weighted', [158, 251, 152], 30);
  expectColor('falloff', [120, 123, 249], 35);
  expectColor('smallRadius', [222, 228, 243], 25);
  expectColor('largeRadius', [58, 89, 252], 35);
  expectColor('secondHeatmap', [255, 128, 255], 25);
  expectColor('underlay', [255, 255, 255], 15);
  expectColor('foreground', [23, 74, 46], 10);

  return (samples: samples, failures: failures);
}

List<double> _sample(
  image.Image captured, {
  required double longitude,
  required double latitude,
  double offsetX = 0,
}) {
  const worldSize = 512.0 * 16;
  const pixelRatio = 2.0;
  final x =
      (captured.width / 2 +
              (longitude / 360 * worldSize + offsetX) * pixelRatio)
          .round();
  final y =
      (captured.height / 2 -
              math.log(math.tan(math.pi / 4 + latitude * math.pi / 360)) *
                  worldSize /
                  (2 * math.pi) *
                  pixelRatio)
          .round();
  final total = [0.0, 0.0, 0.0];
  for (var dy = -2; dy <= 2; dy++) {
    for (var dx = -2; dx <= 2; dx++) {
      final pixel = captured.getPixel(x + dx, y + dy);
      total[0] += pixel.rNormalized * 255;
      total[1] += pixel.gNormalized * 255;
      total[2] += pixel.bNormalized * 255;
    }
  }

  return [for (final channel in total) channel / 25];
}
