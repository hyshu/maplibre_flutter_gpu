import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/persistent_buffer_pool.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

class _BufferEntry extends Fake implements GpuBufferEntry {
  _BufferEntry(this.lengthInBytes, {this.isFillExtrusion = false});

  @override
  final int lengthInBytes;

  @override
  final bool isFillExtrusion;

  @override
  int lastUsed = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TextureEntry extends Fake implements GpuTextureEntry {
  _TextureEntry(this.lengthInBytes);

  @override
  final int lengthInBytes;

  @override
  int lastUsed = 0;
}

GpuVertexBufferCacheKey _vertex(int id, {bool extrusion = false}) => (
  bufferId: id,
  bufferVersion: 1,
  dataAddress: id,
  vertexCount: 1,
  sourceStride: 12,
  shader: extrusion ? ShaderType.fillExtrusion : ShaderType.fill,
  gpuStride: 12,
);

const _smallBudget = GpuResourceCacheBudget(
  regularMinBytes: 16,
  regularMaxBytes: 32,
  fillExtrusionMinBytes: 16,
  fillExtrusionMaxBytes: 32,
  textureBytes: 32,
  poolBytes: 0,
);

void main() {
  test('each cache uses its own buffer and texture byte limits', () {
    final small = GpuResourceCache(budget: _smallBudget);
    final large = GpuResourceCache();
    for (final cache in [small, large]) {
      cache.beginFrame();
      cache.storeVertexBuffer(_vertex(1), _BufferEntry(48));
      cache.storeVertexBuffer(
        _vertex(2, extrusion: true),
        _BufferEntry(48, isFillExtrusion: true),
      );
      cache.storeTexture((textureId: 1, textureVersion: 1), _TextureEntry(48));
      cache.beginFrame();
      cache.storeVertexBuffer(_vertex(3), _BufferEntry(8));
      cache.storeVertexBuffer(
        _vertex(4, extrusion: true),
        _BufferEntry(8, isFillExtrusion: true),
      );
      cache.storeTexture((textureId: 2, textureVersion: 1), _TextureEntry(8));
      cache.evictCaches();
    }

    expect(small.sizeSnapshot.vertexBytes, 16);
    expect(small.sizeSnapshot.textureBytes, 8);
    expect(large.sizeSnapshot.vertexBytes, 112);
    expect(large.sizeSnapshot.textureBytes, 56);
    small.dispose();
    large.dispose();
  });

  test('lowering limits evicts old buffers and protects the current frame', () {
    final cache = GpuResourceCache();
    cache.beginFrame();
    cache.storeIndexBuffer((
      bufferId: 1,
      bufferVersion: 1,
      dataAddress: 1,
    ), _BufferEntry(48));
    cache.beginFrame();
    cache.storeIndexBuffer((
      bufferId: 2,
      bufferVersion: 1,
      dataAddress: 2,
    ), _BufferEntry(64));

    cache.updateBudget(_smallBudget);
    expect(cache.sizeSnapshot.indexBytes, 64);
    cache.beginFrame();
    cache.evictCaches();
    expect(cache.sizeSnapshot.indexBytes, 0);
    cache.dispose();
  });

  test('memory pressure clears ownership and permits a fresh cache frame', () {
    final cache = GpuResourceCache(budget: _smallBudget);
    cache.beginFrame();
    cache.storeVertexBuffer(_vertex(1), _BufferEntry(48));
    cache.storeIndexBuffer((
      bufferId: 1,
      bufferVersion: 1,
      dataAddress: 1,
    ), _BufferEntry(48));
    cache.storeTexture((textureId: 1, textureVersion: 1), _TextureEntry(48));

    cache.reduceMemoryUse();
    expect(cache.sizeSnapshot.totalBytes, 0);
    expect(cache.budget, same(_smallBudget));
    cache.beginFrame();
    cache.storeVertexBuffer(_vertex(2), _BufferEntry(8));
    cache.evictCaches();
    expect(cache.sizeSnapshot.vertexBytes, 8);
    cache.dispose();
  });

  test('invalid updates preserve the existing cache budget', () {
    final cache = GpuResourceCache(budget: _smallBudget);
    expect(
      () => cache.updateBudget(
        const GpuResourceCacheBudget(regularMinBytes: 32, regularMaxBytes: 16),
      ),
      throwsArgumentError,
    );
    expect(cache.budget, same(_smallBudget));
    expect(
      () => GpuResourceCache(
        budget: const GpuResourceCacheBudget(textureBytes: -1),
      ),
      throwsArgumentError,
    );
    cache.dispose();
  });

  test('pool budget can disable uploads and rejects negative updates', () {
    final pool = GpuPersistentBufferPool(maxPageBytes: 0);
    expect(pool.allocate(Uint8List(16), frame: 0), isNull);
    pool.updateMaxPageBytes(1024 * 1024);
    expect(pool.maxPageBytes, 1024 * 1024);
    pool.updateMaxPageBytes(0);
    expect(pool.allocate(Uint8List(16), frame: 1), isNull);
    expect(() => pool.updateMaxPageBytes(-1), throwsRangeError);
    expect(pool.maxPageBytes, 0);
    pool.dispose();
  });
}
