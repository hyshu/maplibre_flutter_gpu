import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Places glyph centers along a screen-space path using their advance widths.
List<({Offset position, double angle})> layoutSymbolGlyphsAlongPath(
  List<Offset> path,
  List<double> advances, {
  bool keepUpright = true,
}) {
  if (path.length < 2 || advances.isEmpty) return const [];
  final points = <Offset>[];
  for (final point in path) {
    if (!point.dx.isFinite || !point.dy.isFinite) continue;
    if (points.isEmpty || (point - points.last).distanceSquared > 0.0001) {
      points.add(point);
    }
  }
  if (points.length < 2) return const [];

  var sampler = _MonotonicPathSampler(points);
  var pathLength = sampler.length;
  if (pathLength <= 0) return const [];

  // Follow the path in the direction that keeps text upright.
  if (keepUpright && math.cos(sampler.sample(pathLength / 2).angle) < 0) {
    final reversed = points.reversed.toList(growable: false);
    points
      ..clear()
      ..addAll(reversed);
    sampler = _MonotonicPathSampler(points);
    pathLength = sampler.length;
  }

  final safeAdvances = [
    for (final advance in advances)
      advance.isFinite && advance > 0 ? advance : 0.0,
  ];
  final advanceTotal = safeAdvances.fold<double>(
    0,
    (sum, value) => sum + value,
  );
  if (advanceTotal <= 0) return const [];
  final positionScale = math.min(1.0, pathLength / advanceTotal);
  var distance = (pathLength - advanceTotal * positionScale) / 2;
  final placements = <({Offset position, double angle})>[];
  for (final advance in safeAdvances) {
    final positionedAdvance = advance * positionScale;
    placements.add(sampler.sample(distance + positionedAdvance / 2));
    distance += positionedAdvance;
  }

  return placements;
}

class _MonotonicPathSampler(final List<Offset> points) {
  final segments = [
    for (var i = 1; i < points.length; i++)
      (points[i] - points[i - 1]).distance,
  ];
  late final length = segments.fold(0.0, (sum, value) => sum + value);
  var _segmentIndex = 0;
  var _segmentStart = 0.0;

  ({Offset position, double angle}) sample(double distance) {
    final target = distance.clamp(0.0, length);
    if (target < _segmentStart) {
      _segmentIndex = 0;
      _segmentStart = 0;
    }
    while (_segmentIndex < segments.length - 1 &&
        target > _segmentStart + segments[_segmentIndex]) {
      _segmentStart += segments[_segmentIndex];
      _segmentIndex += 1;
    }
    final segmentLength = segments[_segmentIndex];
    final delta = points[_segmentIndex + 1] - points[_segmentIndex];
    final t = segmentLength > 0
        ? (target - _segmentStart) / segmentLength
        : 0.0;

    return (
      position: points[_segmentIndex] + delta * t,
      angle: math.atan2(delta.dy, delta.dx),
    );
  }
}
