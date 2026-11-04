import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

GpuVertexBufferCacheKey _key({
  int bufferId = 0xC0000007,
  int bufferVersion = 4,
  int dataAddress = 100,
  int vertexCount = 128,
  int sourceStride = 44,
  int shader = ShaderType.fillExtrusion,
  int gpuStride = 56,
}) => (
  bufferId: bufferId,
  bufferVersion: bufferVersion,
  dataAddress: dataAddress,
  vertexCount: vertexCount,
  sourceStride: sourceStride,
  shader: shader,
  gpuStride: gpuStride,
);

void main() {
  for (final flags in [0, DrawCommandFlags.fillExtrusionDataDriven]) {
    final sourceStride = fillExtrusionVertexStride(flags);
    final gpuStride = gpuVertexStride(ShaderType.fillExtrusion, flags);
    test('recreated $sourceStride to $gpuStride extrusion reuses geometry', () {
      final first = gpuCanonicalVertexBufferCacheKey(
        _key(sourceStride: sourceStride, gpuStride: gpuStride),
      );
      final recreated = gpuCanonicalVertexBufferCacheKey(
        _key(
          dataAddress: 200,
          sourceStride: sourceStride,
          gpuStride: gpuStride,
        ),
      );
      final cached = {first: Object()};

      expect(sourceStride, isNot(gpuStride));
      expect(recreated.dataAddress, 0);
      expect(cached[recreated], same(cached[first]));
    });
  }

  test('stable extrusion identity preserves content and layout boundaries', () {
    final first = gpuCanonicalVertexBufferCacheKey(_key());
    final variants = [
      _key(bufferId: 0xC0000008),
      _key(bufferVersion: 5),
      _key(vertexCount: 64),
      _key(sourceStride: 12),
      _key(gpuStride: 24),
      _key(shader: ShaderType.line),
    ];

    for (final variant in variants) {
      expect(gpuCanonicalVertexBufferCacheKey(variant), isNot(first));
    }
  });

  test('ordinary packed extrusion vertices retain pointer identity', () {
    for (final bufferId in [7, 0x80000007]) {
      final first = gpuCanonicalVertexBufferCacheKey(_key(bufferId: bufferId));
      final recreated = gpuCanonicalVertexBufferCacheKey(
        _key(bufferId: bufferId, dataAddress: 200),
      );

      expect(first.dataAddress, 100);
      expect(recreated, isNot(first));
    }
  });

  test('extrusion namespace does not canonicalize packed line vertices', () {
    final first = gpuCanonicalVertexBufferCacheKey(
      _key(shader: ShaderType.line, sourceStride: 8, gpuStride: 24),
    );
    final recreated = gpuCanonicalVertexBufferCacheKey(
      _key(
        shader: ShaderType.line,
        sourceStride: 8,
        gpuStride: 24,
        dataAddress: 200,
      ),
    );

    expect(first.dataAddress, 100);
    expect(recreated, isNot(first));
  });
}
