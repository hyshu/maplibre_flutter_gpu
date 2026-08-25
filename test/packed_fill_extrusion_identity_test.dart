import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('prepared packed fill extrusion ignores native pointer changes', () {
    const first = (
      bufferId: 0x80000007,
      bufferVersion: 3,
      dataAddress: 100,
      vertexCount: 128,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      gpuStride: 44,
    );
    const second = (
      bufferId: 0x80000007,
      bufferVersion: 3,
      dataAddress: 200,
      vertexCount: 128,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      gpuStride: 44,
    );

    final canonicalFirst = gpuCanonicalVertexBufferCacheKey(first);
    final canonicalSecond = gpuCanonicalVertexBufferCacheKey(second);

    expect(canonicalFirst, canonicalSecond);
    expect(canonicalFirst.dataAddress, 0);
  });

  test('prepared packed fill extrusion still respects content version', () {
    const first = (
      bufferId: 0x80000007,
      bufferVersion: 3,
      dataAddress: 100,
      vertexCount: 128,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      gpuStride: 44,
    );
    const nextVersion = (
      bufferId: 0x80000007,
      bufferVersion: 4,
      dataAddress: 200,
      vertexCount: 128,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      gpuStride: 44,
    );

    expect(
      gpuCanonicalVertexBufferCacheKey(first),
      isNot(gpuCanonicalVertexBufferCacheKey(nextVersion)),
    );
  });
}
