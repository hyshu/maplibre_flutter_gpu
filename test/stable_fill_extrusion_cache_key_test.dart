import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('native stable fill extrusion id ignores recreated vertex pointer', () {
    const first = (
      bufferId: 0xC0000007,
      bufferVersion: 4,
      dataAddress: 100,
      vertexCount: 128,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      gpuStride: 44,
    );
    const recreated = (
      bufferId: 0xC0000007,
      bufferVersion: 4,
      dataAddress: 200,
      vertexCount: 128,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      gpuStride: 44,
    );

    expect(
      gpuCanonicalVertexBufferCacheKey(first),
      gpuCanonicalVertexBufferCacheKey(recreated),
    );
  });

  test('native stable fill extrusion id still invalidates by version', () {
    const first = (
      bufferId: 0xC0000007,
      bufferVersion: 4,
      dataAddress: 100,
      vertexCount: 128,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      gpuStride: 44,
    );
    const changed = (
      bufferId: 0xC0000007,
      bufferVersion: 5,
      dataAddress: 200,
      vertexCount: 128,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      gpuStride: 44,
    );

    expect(
      gpuCanonicalVertexBufferCacheKey(first),
      isNot(gpuCanonicalVertexBufferCacheKey(changed)),
    );
  });
}
