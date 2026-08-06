import 'dart:math' as math;

import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

/// Time for one car to complete the full Tokyo Station road loop.
const carLoopDuration = Duration(minutes: 5);

LatLng sampleClosedRoute(List<LatLng> route, double progress) {
  if (route.length < 2) {
    throw ArgumentError.value(route, 'route', 'requires at least two points');
  }
  final segmentLengths = [
    for (var index = 0; index < route.length - 1; index++)
      _routeSegmentLength(route[index], route[index + 1]),
  ];
  final totalLength = segmentLengths.fold(0.0, (sum, value) => sum + value);
  if (totalLength == 0) return route.first;

  final wrapped = (progress % 1 + 1) % 1;
  var remaining = wrapped * totalLength;
  for (var index = 0; index < segmentLengths.length; index += 1) {
    final segmentLength = segmentLengths[index];
    if (remaining <= segmentLength || index == segmentLengths.length - 1) {
      final fraction = segmentLength == 0 ? 0.0 : remaining / segmentLength;
      final start = route[index];
      final end = route[index + 1];

      return LatLng(
        start.latitude + (end.latitude - start.latitude) * fraction,
        start.longitude + (end.longitude - start.longitude) * fraction,
      );
    }
    remaining -= segmentLength;
  }
  return route.last;
}

double _routeSegmentLength(LatLng start, LatLng end) {
  final meanLatitude = (start.latitude + end.latitude) * 0.5 * math.pi / 180;
  final north = end.latitude - start.latitude;
  final east = (end.longitude - start.longitude) * math.cos(meanLatitude);

  return math.sqrt(north * north + east * east);
}
