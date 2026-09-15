import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../frame/draw_flags.dart';
import '../frame/vertex_repack.dart';
import '../native/draw_command.dart';
import 'resource_cache.dart';

/// A view over the [byteLength] bytes native owns at [dataAddress].
///
/// The bytes are borrowed rather than copied and remain valid only until the
/// native frame that exported them ends. Callers must upload them before
/// returning.
Uint8List _nativeBytes(int dataAddress, int byteLength) =>
    Pointer<Uint8>.fromAddress(dataAddress).asTypedList(byteLength);

/// Copies [bytes] into a fresh device buffer.
GpuBufferEntry _uploadBuffer(Uint8List bytes) => .new(
  gpu.gpuContext.createDeviceBufferWithCopy(ByteData.sublistView(bytes)),
  bytes.lengthInBytes,
);

/// Resolves native geometry and pixels into frame-owned or cached GPU resources.
///
/// Native data is borrowed only while each call uploads its contents.
final class GpuCommandResources {
  /// Uses [resourceCache] for persistent resources and upload metrics.
  GpuCommandResources(GpuResourceCache resourceCache)
    : _resourceCache = resourceCache;

  final GpuResourceCache _resourceCache;

  /// Returns cached geometry or uploads it using the shader's GPU layout.
  GpuBufferEntry cachedVertexBuffer(
    int bufferId,
    int bufferVersion,
    int dataAddress,
    int vertexCount,
    int sourceStride,
    int shader,
    int flags,
  ) {
    final cacheKey = (
      bufferId: bufferId,
      bufferVersion: bufferVersion,
      dataAddress: dataAddress,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      shader: shader,
      gpuStride: gpuVertexStride(shader, flags),
    );
    var cached = _resourceCache.vertexBuffer(cacheKey);
    if (cached != null) return cached;
    final source = _nativeBytes(dataAddress, vertexCount * sourceStride);
    final repackStopwatch = Stopwatch()..start();
    final vertices = repackVertexDataForGpu(
      source,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      shader: shader,
      flags: flags,
    );
    _resourceCache.timingMetrics.recordRepack(
      micros: repackStopwatch.elapsedMicroseconds,
    );
    final uploadStopwatch = Stopwatch()..start();
    cached = _resourceCache.uploadCachedBuffer(
      vertices,
      isFillExtrusion: shader == ShaderType.fillExtrusion,
    );
    _resourceCache.timingMetrics.recordVertexUpload(
      micros: uploadStopwatch.elapsedMicroseconds,
      bytes: vertices.lengthInBytes,
    );
    _resourceCache.storeVertexBuffer(cacheKey, cached);

    return cached;
  }

  /// Returns cached 16-bit indices or uploads their current native generation.
  GpuBufferEntry cachedIndexBuffer(
    int bufferId,
    int bufferVersion,
    int dataAddress,
    int indexCount,
    int shader,
  ) {
    final cacheKey = (
      bufferId: bufferId,
      bufferVersion: bufferVersion,
      dataAddress: dataAddress,
    );
    var cached = _resourceCache.indexBuffer(cacheKey);
    if (cached != null) return cached;
    final bytes = _nativeBytes(dataAddress, indexCount * 2);
    final uploadStopwatch = Stopwatch()..start();
    cached = _resourceCache.uploadCachedBuffer(
      bytes,
      isFillExtrusion: shader == ShaderType.fillExtrusion,
    );
    _resourceCache.timingMetrics.recordIndexUpload(
      micros: uploadStopwatch.elapsedMicroseconds,
      bytes: bytes.lengthInBytes,
    );
    _resourceCache.storeIndexBuffer(cacheKey, cached);

    return cached;
  }

  /// Uploads frame-owned 16-bit indices without retaining them in the cache.
  GpuBufferEntry frameIndexBuffer(int dataAddress, int byteLength) {
    final bytes = _nativeBytes(dataAddress, byteLength);
    final uploadStopwatch = Stopwatch()..start();
    final uploaded = _uploadBuffer(bytes);
    _resourceCache.timingMetrics.recordIndexUpload(
      micros: uploadStopwatch.elapsedMicroseconds,
      bytes: bytes.lengthInBytes,
      frameOwned: true,
    );

    return uploaded;
  }

  /// Uploads frame-owned geometry, repacking only when its stride differs.
  GpuBufferEntry frameVertexBuffer(
    int dataAddress,
    int vertexCount,
    int sourceStride,
    int shader,
    int flags,
  ) {
    final source = _nativeBytes(dataAddress, vertexCount * sourceStride);
    Uint8List vertices;
    if (sourceStride == gpuVertexStride(shader, flags)) {
      vertices = source;
    } else {
      final repackStopwatch = Stopwatch()..start();
      vertices = repackVertexDataForGpu(
        source,
        vertexCount: vertexCount,
        sourceStride: sourceStride,
        shader: shader,
        flags: flags,
      );
      _resourceCache.timingMetrics.recordRepack(
        micros: repackStopwatch.elapsedMicroseconds,
      );
    }
    final uploadStopwatch = Stopwatch()..start();
    final uploaded = _uploadBuffer(vertices);
    _resourceCache.timingMetrics.recordVertexUpload(
      micros: uploadStopwatch.elapsedMicroseconds,
      bytes: vertices.lengthInBytes,
      frameOwned: true,
    );

    return uploaded;
  }

  /// Gets or creates a GPU texture for exported native pixel data.
  ///
  /// One-channel data uploads as R8. Four-channel data uploads as RGBA8.
  gpu.Texture? textureForCommand(
    int textureId,
    int textureVersion,
    int dataAddress,
    int width,
    int height,
    int channels,
  ) {
    if (dataAddress == 0 ||
        width <= 0 ||
        height <= 0 ||
        (channels != 1 && channels != 4)) {
      return null;
    }
    final cacheKey = (textureId: textureId, textureVersion: textureVersion);
    final cached = _resourceCache.texture(cacheKey);
    if (cached != null) return cached.texture;
    try {
      final uploadStopwatch = Stopwatch()..start();
      final texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        width,
        height,
        format: channels == 1
            ? gpu.PixelFormat.r8UNormInt
            : gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
        enableShaderReadUsage: true,
      );
      final byteLength = width * height * channels;
      final bytes = Pointer<Uint8>.fromAddress(dataAddress)
          .asTypedList(byteLength);
      texture.overwrite(ByteData.sublistView(bytes));
      _resourceCache.timingMetrics.recordTextureUpload(
        micros: uploadStopwatch.elapsedMicroseconds,
        bytes: byteLength,
      );
      _resourceCache.storeTexture(cacheKey, .new(texture, byteLength));

      return texture;
    } catch (e) {
      debugPrint(
        '[GpuRenderer] texture upload failed '
        '($width x $height ch=$channels): $e',
      );

      return null;
    }
  }
}
