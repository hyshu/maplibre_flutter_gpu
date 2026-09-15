import 'package:flutter/foundation.dart';

import '../native/abi_generated.dart';
import '../native/draw_command.dart';
import 'draw_entry.dart';

/// One native style layer interval assigned to a compositing stratum.
typedef GpuStyleLayerRange = ({int? minimumLayerIndex, int? maximumLayerIndex});

/// Restores sublayer order within one layer while keeping stencil setup
/// barriers fixed in the native command stream.
///
/// Only contiguous clipping-test commands for the same layer are stably
/// sorted. This preserves established tile masks and command order outside
/// each run.
void sortClippingRunsBySubLayer(
  List<DrawEntry> entries, [
  ByteData? commandData,
]) {
  int subLayerOf(DrawEntry entry) => commandData == null
      ? entry.subLayerIndex
      : commandData.getInt32(
          entry.commandOffset + DrawCommandAbi.subLayerIndex,
          Endian.little,
        );

  var start = 0;
  while (start < entries.length) {
    final first = entries[start];
    if (first.stencilMode != StencilModeType.clippingTest) {
      start += 1;
      continue;
    }
    final layer = first.layer;
    var end = start + 1;
    while (end < entries.length &&
        entries[end].stencilMode == StencilModeType.clippingTest &&
        entries[end].layer == layer) {
      end += 1;
    }
    for (var index = start + 1; index < end; index += 1) {
      final entry = entries[index];
      final subLayer = subLayerOf(entry);
      var insertion = index;
      while (insertion > start) {
        final previous = entries[insertion - 1];
        final previousSubLayer = subLayerOf(previous);
        if (previousSubLayer <= subLayer) break;
        entries[insertion] = previous;
        insertion -= 1;
      }
      entries[insertion] = entry;
    }
    start = end;
  }
}

/// Whether a native style layer belongs to one compositing stratum.
///
/// Bounds are inclusive at [minimumLayerIndex] and exclusive at
/// [maximumLayerIndex]. Null leaves that side unbounded.
bool layerIndexInRange(
  int layerIndex, {
  int? minimumLayerIndex,
  int? maximumLayerIndex,
}) =>
    (minimumLayerIndex == null || layerIndex >= minimumLayerIndex) &&
    (maximumLayerIndex == null || layerIndex < maximumLayerIndex);

/// Returns the ordered compositing range containing [layerIndex].
///
/// The input ranges must be sorted and non-overlapping. Gaps are allowed.
int? gpuStyleLayerRangeIndex(int layerIndex, List<GpuStyleLayerRange> ranges) {
  var low = 0;
  var high = ranges.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    final maximum = ranges[middle].maximumLayerIndex;
    if (maximum != null && layerIndex >= maximum) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  if (low >= ranges.length) return null;
  final range = ranges[low];
  if (!layerIndexInRange(
    layerIndex,
    minimumLayerIndex: range.minimumLayerIndex,
    maximumLayerIndex: range.maximumLayerIndex,
  )) {
    return null;
  }
  return low;
}

/// Partitions native entries without separating stencil consumers from setup.
///
/// Tile clipping state is shared across native style layers. Setup controls
/// are replayed only in partitions that contain stencil consumers.
/// Clipping masks feed clipping tests. Clears also feed fill extrusions because
/// native rendering can recycle a 3D stencil reference after clearing it.
void partitionDrawEntriesByStyleLayerRanges({
  required List<DrawEntry> entries,
  required List<GpuStyleLayerRange> ranges,
  required List<List<DrawEntry>> partitions,
  required List<bool> clippingMaskPartitions,
  required List<bool> stencilClearPartitions,
}) {
  if (partitions.length < ranges.length) {
    throw ArgumentError.value(
      partitions.length,
      'partitions',
      'must contain storage for every style layer range',
    );
  }
  if (clippingMaskPartitions.length < ranges.length) {
    throw ArgumentError.value(
      clippingMaskPartitions.length,
      'clippingMaskPartitions',
      'must contain storage for every style layer range',
    );
  }
  if (stencilClearPartitions.length < ranges.length) {
    throw ArgumentError.value(
      stencilClearPartitions.length,
      'stencilClearPartitions',
      'must contain storage for every style layer range',
    );
  }
  for (final partition in partitions) {
    partition.clear();
  }
  for (var index = 0; index < clippingMaskPartitions.length; index += 1) {
    clippingMaskPartitions[index] = false;
  }
  for (var index = 0; index < stencilClearPartitions.length; index += 1) {
    stencilClearPartitions[index] = false;
  }
  for (final entry in entries) {
    if (entry.stencilMode != StencilModeType.clippingTest &&
        entry.stencilMode != StencilModeType.fillExtrusion) {
      continue;
    }
    final partitionIndex = gpuStyleLayerRangeIndex(entry.layer, ranges);
    if (partitionIndex != null) {
      stencilClearPartitions[partitionIndex] = true;
      if (entry.stencilMode == StencilModeType.clippingTest) {
        clippingMaskPartitions[partitionIndex] = true;
      }
    }
  }
  for (final entry in entries) {
    if (entry.stencilMode == StencilModeType.clippingMask) {
      for (var index = 0; index < ranges.length; index += 1) {
        if (clippingMaskPartitions[index]) partitions[index].add(entry);
      }
      continue;
    }
    if (entry.stencilMode == StencilModeType.clear) {
      for (var index = 0; index < ranges.length; index += 1) {
        if (stencilClearPartitions[index]) partitions[index].add(entry);
      }
      continue;
    }
    final partitionIndex = gpuStyleLayerRangeIndex(entry.layer, ranges);
    if (partitionIndex != null) partitions[partitionIndex].add(entry);
  }
}

/// Whether [ranges] satisfy the ordering required by binary range lookup.
bool gpuStyleLayerRangesAreOrdered(List<GpuStyleLayerRange> ranges) {
  if (ranges.isEmpty) return false;
  int? previousMaximum;
  for (var index = 0; index < ranges.length; index += 1) {
    final range = ranges[index];
    final minimum = range.minimumLayerIndex;
    final maximum = range.maximumLayerIndex;
    if (index > 0 && minimum == null) return false;
    if (index + 1 < ranges.length && maximum == null) return false;
    if (minimum != null && maximum != null && minimum >= maximum) return false;
    if (index > 0 &&
        previousMaximum != null &&
        minimum != null &&
        minimum < previousMaximum) {
      return false;
    }
    previousMaximum = maximum;
  }
  return true;
}

/// Whether any native command belongs to one compositing stratum.
bool commandLayersIntersectRange(
  Iterable<int> commandLayerIndices, {
  int? minimumLayerIndex,
  int? maximumLayerIndex,
}) {
  for (final layerIndex in commandLayerIndices) {
    if (layerIndexInRange(
      layerIndex,
      minimumLayerIndex: minimumLayerIndex,
      maximumLayerIndex: maximumLayerIndex,
    )) {
      return true;
    }
  }
  return false;
}

/// Whether one style range owns the geographic 3D callback boundary.
///
/// The boundary follows the last fill-extrusion layer. Styles without a
/// fill-extrusion place it after the final bounded range.
bool threeDimensionalCallbackInLayerRange(
  int? lastFillExtrusionLayerIndex, {
  int? minimumLayerIndex,
  int? maximumLayerIndex,
}) {
  if (lastFillExtrusionLayerIndex == null) return maximumLayerIndex == null;

  return layerIndexInRange(
    lastFillExtrusionLayerIndex,
    minimumLayerIndex: minimumLayerIndex,
    maximumLayerIndex: maximumLayerIndex,
  );
}
