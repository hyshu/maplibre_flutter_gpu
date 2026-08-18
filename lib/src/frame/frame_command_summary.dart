// Counts what a native frame's DrawCommand buffer actually contains.
//
// Some render paths leave no direct trace in a screenshot. A clipping mask
// writes only to the stencil buffer, and a stencil clear draws nothing at all.
// This summary lets tests verify that those paths ran.
//
// The function reads the same ABI bytes as the renderer's decode loop but
// keeps no GPU state, so it can be tested against a synthetic command buffer.
import 'dart:typed_data';

/// How many commands a frame carried, grouped by the fields that select a
/// render path.
typedef FrameCommandSummary = ({
  int commandCount,
  Map<int, int> countByShader,
  Map<int, int> countByStencilMode,
});

/// Groups [commandCount] DrawCommand records by shader type and stencil mode.
///
/// [commands] must be the frame's command buffer and [commandStride] its
/// per-record size, exactly as reported by the native frame metadata. A stride
/// that disagrees with the compiled ABI yields an empty summary rather than
/// reading past a record boundary.
FrameCommandSummary summarizeFrameCommands({
  required Uint8List commands,
  required int commandCount,
  required int commandStride,
  required int shaderTypeOffset,
  required int stencilModeOffset,
  required int expectedStride,
}) {
  const empty = (
    commandCount: 0,
    countByShader: <int, int>{},
    countByStencilMode: <int, int>{},
  );
  if (commandCount <= 0 || commandStride != expectedStride) return empty;
  if (commands.lengthInBytes < commandCount * commandStride) return empty;

  final data = ByteData.sublistView(commands);
  final countByShader = <int, int>{};
  final countByStencilMode = <int, int>{};
  for (var index = 0; index < commandCount; index += 1) {
    final offset = index * commandStride;
    final shader = data.getUint32(offset + shaderTypeOffset, Endian.little);
    final stencilMode = data.getUint32(
      offset + stencilModeOffset,
      Endian.little,
    );
    countByShader[shader] = (countByShader[shader] ?? 0) + 1;
    countByStencilMode[stencilMode] =
        (countByStencilMode[stencilMode] ?? 0) + 1;
  }
  return (
    commandCount: commandCount,
    countByShader: countByShader,
    countByStencilMode: countByStencilMode,
  );
}

/// Returns style layer indices referenced by valid command records.
///
/// The returned set is empty when [commandStride] disagrees with
/// [expectedStride], the buffer is too short, or [layerIndexOffset] does not
/// fit inside one record.
Set<int> frameCommandLayerIndices({
  required Uint8List commands,
  required int commandCount,
  required int commandStride,
  required int layerIndexOffset,
  required int expectedStride,
}) {
  if (commandCount <= 0 || commandStride != expectedStride) {
    return const <int>{};
  }
  if (layerIndexOffset < 0 || layerIndexOffset + 4 > commandStride) {
    return const <int>{};
  }
  if (commands.lengthInBytes < commandCount * commandStride) {
    return const <int>{};
  }

  final data = ByteData.sublistView(commands);
  final result = <int>{};
  for (var index = 0; index < commandCount; index += 1) {
    result.add(
      data.getUint32(index * commandStride + layerIndexOffset, Endian.little),
    );
  }

  return Set<int>.unmodifiable(result);
}
