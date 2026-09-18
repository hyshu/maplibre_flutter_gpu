part of '../command_decoder.dart';

/// Reuses entry storage while releasing resources outside the active topology.
final class _GpuDrawEntryPool {
  final List<DrawEntry> _entries = [];
  var _cursor = 0;

  void reset() {
    _cursor = 0;
  }

  void dispose() {
    for (final entry in _entries) {
      entry.releaseResources();
    }
    _entries.clear();
    _cursor = 0;
  }

  /// Acquires the next pooled entry and resets all command-specific state.
  ///
  /// The caller records the result after admission succeeds.
  DrawEntry acquireDrawEntry(
    int commandOffset,
    int shader,
    int drawMode,
    int flags,
    int layer,
    int vertexCount,
    int indexCount,
    GpuBufferEntry? vertexBuffer,
    GpuBufferEntry? indexBuffer,
    gpu.Texture? texture,
    int textureFilter,
    int stencilReference,
    int stencilMode,
    int subLayerIndex,
  ) {
    if (_cursor == _entries.length) {
      _entries.add(
        .new(
          commandOffset,
          shader,
          drawMode,
          flags,
          layer,
          vertexCount,
          indexCount,
          vertexBuffer,
          indexBuffer,
          texture,
          textureFilter,
          stencilReference,
          stencilMode,
          subLayerIndex: subLayerIndex,
        ),
      );
    } else {
      _entries[_cursor].reset(
        commandOffset,
        shader,
        drawMode,
        flags,
        layer,
        vertexCount,
        indexCount,
        vertexBuffer,
        indexBuffer,
        texture,
        textureFilter,
        stencilReference,
        stencilMode,
        nextSubLayerIndex: subLayerIndex,
      );
    }
    return _entries[_cursor++];
  }

  /// Drops resource references held by pool entries outside the active topology.
  void releaseUnused() {
    for (var index = _cursor; index < _entries.length; index += 1) {
      _entries[index].releaseResources();
    }
  }
}
