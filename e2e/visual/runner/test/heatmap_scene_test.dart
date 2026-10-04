import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:test/test.dart';
import 'package:visual_e2e_runner/visual_e2e_runner.dart';

void main() {
  for (final format in [image.Format.uint8, image.Format.uint16]) {
    test('blank $format captures fail with normalized RGB samples', () {
      final capture = image.Image(width: 1600, height: 1200, format: format);
      final scale = format == image.Format.uint16 ? 257 : 1;
      for (final pixel in capture) {
        pixel
          ..r = 231 * scale
          ..g = 237 * scale
          ..b = 243 * scale;
      }
      final result = analyzeHeatmapScenePng(
        Uint8List.fromList(image.encodePng(capture)),
      );

      expect(result.samples['isolated'], [231.0, 237.0, 243.0]);
      expect(result.failures, contains(startsWith('isolated RGB')));
      expect(result.failures, contains(startsWith('overlap RGB')));
      expect(result.failures, contains(startsWith('secondHeatmap RGB')));
    });
  }

  test('unexpected viewport dimensions cannot pass heatmap checks', () {
    final capture = image.Image(width: 800, height: 600);
    final result = analyzeHeatmapScenePng(
      Uint8List.fromList(image.encodePng(capture)),
    );

    expect(result.samples, isEmpty);
    expect(result.failures, isNotEmpty);
  });
}
