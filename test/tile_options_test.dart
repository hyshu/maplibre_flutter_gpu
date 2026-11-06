import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

void main() {
  test('defaults match MapLibre and never reduce detail when upright', () {
    const options = TileLodOptions.defaults;
    expect(options.minRadius, 3);
    expect(options.scale, 1);
    expect(options.pitchThreshold, 60);
    expect(options.zoomShift, 0);
    expect(options.mode, TileLodMode.standard);
  });

  test('options compare by value', () {
    const a = TileLodOptions(pitchThreshold: 20, mode: TileLodMode.distance);
    const b = TileLodOptions(pitchThreshold: 20, mode: TileLodMode.distance);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const TileLodOptions(pitchThreshold: 20)));
    expect(a, isNot(TileLodOptions.defaults));
  });

  test('invalid ranges are rejected', () {
    expect(() => TileLodOptions(minRadius: -1), throwsAssertionError);
    expect(() => TileLodOptions(scale: 0), throwsAssertionError);
    expect(() => TileLodOptions(pitchThreshold: 181), throwsAssertionError);
  });
}
