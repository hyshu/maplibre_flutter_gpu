import 'dart:math' as math;

import '../../geo/camera.dart';
import 'control_options.dart';

/// Computes the great-circle distance between `a` and `b` in meters.
double distanceMeters(LatLng a, LatLng b) {
  const earthRadiusMeters = 6371008.8;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final deltaLat = lat2 - lat1;
  var deltaLon = (b.longitude - a.longitude) * math.pi / 180;
  if (deltaLon > math.pi) deltaLon -= math.pi * 2;
  if (deltaLon < -math.pi) deltaLon += math.pi * 2;
  final sinLat = math.sin(deltaLat / 2);
  final sinLon = math.sin(deltaLon / 2);
  final haversine =
      sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLon * sinLon;

  return earthRadiusMeters * 2 * math.asin(math.sqrt(haversine.clamp(0, 1)));
}

/// Selects a readable scale distance that fits within `maxWidth`.
///
/// The returned width is in logical pixels. An empty value is returned when
/// `metersAcrossMaxWidth` or `maxWidth` is not finite and positive.
ScaleBarValue scaleBarValue(
  double metersAcrossMaxWidth,
  ScaleControlUnit unit, {
  double maxWidth = 80,
}) {
  if (!metersAcrossMaxWidth.isFinite ||
      metersAcrossMaxWidth <= 0 ||
      !maxWidth.isFinite ||
      maxWidth <= 0) {
    return const ScaleBarValue(label: '', width: 0);
  }

  late final double unitsAcrossMaxWidth;
  late final String suffix;
  switch (unit) {
    case .metric:
      if (metersAcrossMaxWidth >= 1000) {
        unitsAcrossMaxWidth = metersAcrossMaxWidth / 1000;
        suffix = 'km';
      } else {
        unitsAcrossMaxWidth = metersAcrossMaxWidth;
        suffix = 'm';
      }
    case .imperial:
      if (metersAcrossMaxWidth >= 1609.344) {
        unitsAcrossMaxWidth = metersAcrossMaxWidth / 1609.344;
        suffix = 'mi';
      } else {
        unitsAcrossMaxWidth = metersAcrossMaxWidth * 3.280839895;
        suffix = 'ft';
      }
    case .nautical:
      unitsAcrossMaxWidth = metersAcrossMaxWidth / 1852;
      suffix = 'nm';
  }

  final niceUnits = _niceScaleFloor(unitsAcrossMaxWidth);
  final width = (niceUnits / unitsAcrossMaxWidth * maxWidth)
      .clamp(0, maxWidth)
      .toDouble();

  return .new(label: '${_formatScaleNumber(niceUnits)} $suffix', width: width);
}

double _niceScaleFloor(double value) {
  final exponent = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  final fraction = value / exponent;
  final niceFraction = fraction >= 5
      ? 5.0
      : fraction >= 2
      ? 2.0
      : 1.0;

  return niceFraction * exponent;
}

String _formatScaleNumber(double value) {
  if (value >= 10 || value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  if (value >= 1) return value.toStringAsFixed(1);

  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
