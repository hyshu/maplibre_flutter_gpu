import 'dart:typed_data';

import '../native/command_payload.dart';

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
  required Uint8List payload,
  required int commandCount,
  required int commandStride,
  required int shaderTypeOffset,
  required int expectedStride,
}) {
  const empty = (
    commandCount: 0,
    countByShader: <int, int>{},
    countByStencilMode: <int, int>{},
  );
  if (commandCount <= 0 || commandStride != expectedStride) return empty;
  if (commands.lengthInBytes < commandCount * commandStride) return empty;

  if (shaderTypeOffset < 0 || shaderTypeOffset + 4 > commandStride) {
    return empty;
  }
  final data = ByteData.sublistView(commands);
  final reader = CommandPayloadReader(payload);
  final countByShader = <int, int>{};
  final countByStencilMode = <int, int>{};
  for (var index = 0; index < commandCount; index += 1) {
    final offset = index * commandStride;
    final shader = data.getUint32(offset + shaderTypeOffset, .little);
    if (!reader.read(data, offset)) return empty;
    final stencilMode = reader.stencilMode;
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
  if (commandCount <= 0 || commandStride != expectedStride) return const {};
  if (layerIndexOffset < 0 || layerIndexOffset + 4 > commandStride) {
    return const {};
  }
  if (commands.lengthInBytes < commandCount * commandStride) return const {};

  final data = ByteData.sublistView(commands);
  final result = <int>{};
  for (var index = 0; index < commandCount; index += 1) {
    result.add(
      data.getUint32(index * commandStride + layerIndexOffset, .little),
    );
  }

  return .unmodifiable(result);
}
