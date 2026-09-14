part of 'sprite_atlas.dart';

/// One source-to-destination slice used to draw a stretchable sprite axis.
typedef SpriteAxisSegment = ({
  double sourceStart,
  double sourceEnd,
  double destStart,
  double destEnd,
});

/// Maps one sprite axis while preserving fixed pixels around its content area.
@visibleForTesting
List<SpriteAxisSegment> spriteAxisSegments({
  required double sourceExtent,
  required List<(double, double)> stretches,
  required double destExtent,
  required double pixelRatio,
  double? contentStart,
  double? contentEnd,
}) {
  if (sourceExtent <= 0 || destExtent <= 0) {
    return [
      (
        sourceStart: 0,
        sourceEnd: sourceExtent,
        destStart: 0,
        destEnd: destExtent,
      ),
    ];
  }
  final ranges = <(double, double)>[];
  var lastEnd = 0.0;
  for (final stretch in stretches) {
    if (stretch.$1 < lastEnd ||
        stretch.$1 < 0 ||
        stretch.$2 <= stretch.$1 ||
        stretch.$2 > sourceExtent) {
      continue;
    }
    ranges.add(stretch);
    lastEnd = stretch.$2;
  }
  final hasContent =
      contentStart != null &&
      contentEnd != null &&
      contentStart >= 0 &&
      contentEnd > contentStart &&
      contentEnd <= sourceExtent;
  if (ranges.isEmpty && !hasContent) {
    return [
      (
        sourceStart: 0,
        sourceEnd: sourceExtent,
        destStart: 0,
        destEnd: destExtent,
      ),
    ];
  }
  if (ranges.isEmpty) ranges.add((0, sourceExtent));

  double stretchLength(double start, double end) {
    var result = 0.0;
    for (final range in ranges) {
      final overlapStart = start > range.$1 ? start : range.$1;
      final overlapEnd = end < range.$2 ? end : range.$2;
      if (overlapEnd > overlapStart) result += overlapEnd - overlapStart;
    }

    return result;
  }

  final safePixelRatio = pixelRatio.isFinite && pixelRatio > 0
      ? pixelRatio
      : 1.0;
  final contentFrom = hasContent ? contentStart : 0.0;
  final contentTo = hasContent ? contentEnd : sourceExtent;
  final totalStretch = stretchLength(0, sourceExtent);
  final stretchBeforeContent = stretchLength(0, contentFrom);
  final contentStretch = stretchLength(contentFrom, contentTo);
  final contentLength = contentTo - contentFrom;
  final contentFixed = contentLength - contentStretch;
  final fixedBeforeContent = contentFrom - stretchBeforeContent;
  if (totalStretch <= 0 || contentStretch <= 0) {
    return [
      (
        sourceStart: 0,
        sourceEnd: sourceExtent,
        destStart: 0,
        destEnd: destExtent,
      ),
    ];
  }

  // MapLibre keeps fixed sprite pixels at their intrinsic logical size. The
  // stretch coordinate supplies the fitted extent, while the pixel offset
  // compensates fixed cuts both inside and outside the content rectangle.
  double destination(double source) {
    final stretch = stretchLength(0, source);
    final fixed = source - stretch;
    final fitted =
        destExtent * (stretch - stretchBeforeContent) / contentStretch;
    final pixelOffset =
        (fixed - fixedBeforeContent - contentFixed * stretch / totalStretch) /
        safePixelRatio;

    return fitted + pixelOffset;
  }

  final boundaries = <double>{0, sourceExtent};
  for (final range in ranges) {
    boundaries
      ..add(range.$1)
      ..add(range.$2);
  }
  if (hasContent) {
    boundaries
      ..add(contentStart)
      ..add(contentEnd);
  }
  final sorted = boundaries.toList()..sort();

  return [
    for (var index = 0; index < sorted.length - 1; index += 1)
      (
        sourceStart: sorted[index],
        sourceEnd: sorted[index + 1],
        destStart: destination(sorted[index]),
        destEnd: destination(sorted[index + 1]),
      ),
  ];
}
