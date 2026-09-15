part of '../resource_cache.dart';

/// A cached device buffer and the metadata used to manage its lifetime.
class GpuBufferEntry(
  /// The cached GPU buffer.
  final gpu.DeviceBuffer buffer,

  /// Number of bytes available through [view].
  final int lengthInBytes, {

  /// Whether this buffer uses the fill extrusion retention policy.
  final bool isFillExtrusion = false,

  /// Byte offset of this entry inside [buffer].
  final int offsetInBytes = 0,
  GpuPersistentBufferAllocation? pooledAllocation,
}) {
  GpuPersistentBufferAllocation? _pooledAllocation = pooledAllocation;

  /// Frame in which this entry was most recently requested.
  int lastUsed = 0;

  /// A view covering this entry's range inside [buffer].
  late final view = gpu.BufferView(
    buffer,
    offsetInBytes: offsetInBytes,
    lengthInBytes: lengthInBytes,
  );

  void _releasePooledAllocation(int frame) {
    final allocation = _pooledAllocation;
    if (allocation == null) return;
    _pooledAllocation = null;
    allocation.release(frame);
  }
}

/// A cached texture and the metadata used to manage its lifetime.
class GpuTextureEntry(
  /// The cached GPU texture.
  final gpu.Texture texture,

  /// Number of source bytes represented by [texture].
  final int lengthInBytes,
) {
  /// Frame in which this entry was most recently requested.
  int lastUsed = 0;
}

/// Current cache occupancy sampled when the renderer emits its periodic log.
final class const GpuResourceCacheSizeSnapshot({
  required final int vertexCount,
  required final int vertexBytes,
  required final int indexCount,
  required final int indexBytes,
  required final int textureCount,
  required final int textureBytes,
}) {
  int get totalBytes => vertexBytes + indexBytes + textureBytes;
}
