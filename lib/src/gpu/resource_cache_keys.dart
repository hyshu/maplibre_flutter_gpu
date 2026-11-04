import '../native/draw_command.dart';
import 'resource_cache_policy.dart';

/// Values that uniquely identify repacked vertex data in the GPU cache.
typedef GpuVertexBufferCacheKey = ({
  int bufferId,
  int bufferVersion,
  int dataAddress,
  int vertexCount,
  int sourceStride,
  int shader,
  int gpuStride,
});

/// Values that uniquely identify index data in the GPU cache.
typedef GpuIndexBufferCacheKey = ({
  int bufferId,
  int bufferVersion,
  int dataAddress,
});

/// Values that uniquely identify pixel data in the GPU texture cache.
typedef GpuTextureCacheKey = ({int textureId, int textureVersion});

const _gpuBridgePreparedBufferIdNamespace = 0x8000_0000;
const _gpuContentAddressedFillExtrusionNamespace = 0xC000_0000;

bool _isContentAddressedFillExtrusionKey(GpuVertexBufferCacheKey key) =>
    key.shader == ShaderType.fillExtrusion &&
    (key.bufferId & _gpuContentAddressedFillExtrusionNamespace) ==
        _gpuContentAddressedFillExtrusionNamespace;

bool _isBridgePreparedVertexKey(GpuVertexBufferCacheKey key) =>
    (key.bufferId & _gpuBridgePreparedBufferIdNamespace) != 0 &&
    key.sourceStride == key.gpuStride &&
    (gpuCacheClassForShader(key.shader) == .line ||
        key.shader == ShaderType.fillExtrusion);

/// Normalizes vertex keys whose native identity survives allocation changes.
///
/// Bridge-prepared line and fill extrusion segments use high-bit buffer IDs.
/// Their ID and version preserve content identity when CPU allocations move.
/// Packed fill extrusion segments use the top two bits and a content-addressed
/// version, so their repacked GPU buffers also survive native pointer changes.
/// Ordinary buffer IDs also include the CPU address in their cache identity.
GpuVertexBufferCacheKey gpuCanonicalVertexBufferCacheKey(
  GpuVertexBufferCacheKey key,
) {
  if (key.dataAddress == 0 ||
      (!_isBridgePreparedVertexKey(key) &&
          !_isContentAddressedFillExtrusionKey(key))) {
    return key;
  }

  return (
    bufferId: key.bufferId,
    bufferVersion: key.bufferVersion,
    dataAddress: 0,
    vertexCount: key.vertexCount,
    sourceStride: key.sourceStride,
    shader: key.shader,
    gpuStride: key.gpuStride,
  );
}

/// Normalizes prepared index keys to their stable segment identity.
///
/// High-bit buffer IDs are reserved for bridge/native segment identities whose
/// index contents are versioned independently of the backing CPU allocation.
GpuIndexBufferCacheKey gpuCanonicalIndexBufferCacheKey(
  GpuIndexBufferCacheKey key,
) {
  if ((key.bufferId & _gpuBridgePreparedBufferIdNamespace) == 0 ||
      key.dataAddress == 0) {
    return key;
  }
  return (
    bufferId: key.bufferId,
    bufferVersion: key.bufferVersion,
    dataAddress: 0,
  );
}
