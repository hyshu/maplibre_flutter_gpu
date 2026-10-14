import 'dart:math' as math;

const _earthCircumferenceMeters = 2 * math.pi * 6378137.0;
const _tileExtent = 8192;

/// Ground meters per tile unit at the center latitude of tile row [y] at
/// zoom [z].
double fillExtrusionMetersPerUnit(int z, int y) {
  final tiles = math.pow(2, z).toDouble();
  final mercatorY = math.pi * (1 - 2 * (y + 0.5) / tiles);
  final latitude = math.atan((math.exp(mercatorY) - math.exp(-mercatorY)) / 2);

  return _earthCircumferenceMeters * math.cos(latitude) / (tiles * _tileExtent);
}
