import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('expiry eviction callback reports removed keys and values', () {
    final cache = <({int id, int version}), ({int lastUsed, int bytes})>{
      (id: 1, version: 1): (lastUsed: 1, bytes: 100),
      (id: 1, version: 2): (lastUsed: 10, bytes: 200),
    };
    var evictedBytes = 0;
    ({int id, int version})? evictedKey;

    evictExpiredCacheVersions(
      cache,
      frame: 10,
      idOf: (key) => key.id,
      versionOf: (key) => key.version,
      lastUsedOf: (value) => value.lastUsed,
      unusedRetentionFramesOf: (_) => 100,
      onEvict: (key, value) {
        evictedKey = key;
        evictedBytes += value.bytes;
      },
    );

    expect(cache.keys, contains((id: 1, version: 2)));
    expect(cache.keys, isNot(contains((id: 1, version: 1))));
    expect(evictedKey, (id: 1, version: 1));
    expect(evictedBytes, 100);
  });

  test('entry-specific retention can use cache key metadata', () {
    final cache = <({int id, int version, bool longLived}), ({int lastUsed})>{
      (id: 1, version: 1, longLived: true): (lastUsed: 0),
      (id: 2, version: 1, longLived: false): (lastUsed: 0),
    };

    evictExpiredCacheVersions(
      cache,
      frame: 70,
      idOf: (key) => key.id,
      versionOf: (key) => key.version,
      lastUsedOf: (value) => value.lastUsed,
      unusedRetentionFramesForEntry: (key, _) => key.longLived ? 120 : 60,
    );

    expect(cache.keys, contains((id: 1, version: 1, longLived: true)));
    expect(cache.keys, isNot(contains((id: 2, version: 1, longLived: false))));
  });

  GpuVertexBufferCacheKey vertexKey({
    required int shader,
    required int dataAddress,
    required int sourceStride,
    required int gpuStride,
    int bufferId = 0x80000007,
    int bufferVersion = 3,
    int vertexCount = 128,
  }) => (
    bufferId: bufferId,
    bufferVersion: bufferVersion,
    dataAddress: dataAddress,
    vertexCount: vertexCount,
    sourceStride: sourceStride,
    shader: shader,
    gpuStride: gpuStride,
  );

  test('prepared bridge vertices canonicalize away native pointer changes', () {
    final lineA = gpuCanonicalVertexBufferCacheKey(
      vertexKey(
        shader: ShaderType.line,
        dataAddress: 100,
        sourceStride: 24,
        gpuStride: 24,
      ),
    );
    final lineB = gpuCanonicalVertexBufferCacheKey(
      vertexKey(
        shader: ShaderType.line,
        dataAddress: 200,
        sourceStride: 24,
        gpuStride: 24,
      ),
    );
    final extrusionA = gpuCanonicalVertexBufferCacheKey(
      vertexKey(
        shader: ShaderType.fillExtrusion,
        dataAddress: 300,
        sourceStride: 56,
        gpuStride: 56,
      ),
    );
    final extrusionB = gpuCanonicalVertexBufferCacheKey(
      vertexKey(
        shader: ShaderType.fillExtrusion,
        dataAddress: 400,
        sourceStride: 56,
        gpuStride: 56,
      ),
    );

    expect(lineA, lineB);
    expect(lineA.dataAddress, 0);
    expect(extrusionA, extrusionB);
    expect(extrusionA.dataAddress, 0);
  });

  test('canonical prepared keys still distinguish content generations', () {
    final base = gpuCanonicalVertexBufferCacheKey(
      vertexKey(
        shader: ShaderType.lineSDF,
        dataAddress: 100,
        sourceStride: 120,
        gpuStride: 120,
      ),
    );
    final nextVersion = gpuCanonicalVertexBufferCacheKey(
      vertexKey(
        shader: ShaderType.lineSDF,
        dataAddress: 200,
        sourceStride: 120,
        gpuStride: 120,
        bufferVersion: 4,
      ),
    );
    final differentCount = gpuCanonicalVertexBufferCacheKey(
      vertexKey(
        shader: ShaderType.lineSDF,
        dataAddress: 200,
        sourceStride: 120,
        gpuStride: 120,
        vertexCount: 64,
      ),
    );

    expect(base, isNot(nextVersion));
    expect(base, isNot(differentCount));
  });

  test('legacy or packed vertices keep strict native pointer identity', () {
    final oldNativeA = gpuCanonicalVertexBufferCacheKey(
      vertexKey(
        shader: ShaderType.line,
        dataAddress: 100,
        sourceStride: 24,
        gpuStride: 24,
        bufferId: 7,
      ),
    );
    final oldNativeB = gpuCanonicalVertexBufferCacheKey(
      vertexKey(
        shader: ShaderType.line,
        dataAddress: 200,
        sourceStride: 24,
        gpuStride: 24,
        bufferId: 7,
      ),
    );
    final packedA = gpuCanonicalVertexBufferCacheKey(
      vertexKey(
        shader: ShaderType.line,
        dataAddress: 100,
        sourceStride: 8,
        gpuStride: 24,
      ),
    );
    final packedB = gpuCanonicalVertexBufferCacheKey(
      vertexKey(
        shader: ShaderType.line,
        dataAddress: 200,
        sourceStride: 8,
        gpuStride: 24,
      ),
    );

    expect(oldNativeA, isNot(oldNativeB));
    expect(oldNativeA.dataAddress, 100);
    expect(packedA, isNot(packedB));
    expect(packedA.dataAddress, 100);
  });

  test('regular buffer budget grows in bounded pressure steps', () {
    const mib = 1024 * 1024;

    expect(gpuRegularBufferBudgetForResidentBytes(0), 64 * mib);
    expect(gpuRegularBufferBudgetForResidentBytes(64 * mib), 64 * mib);
    expect(gpuRegularBufferBudgetForResidentBytes(65 * mib), 72 * mib);
    expect(gpuRegularBufferBudgetForResidentBytes(72 * mib), 72 * mib);
    expect(gpuRegularBufferBudgetForResidentBytes(73 * mib), 80 * mib);
    expect(gpuRegularBufferBudgetForResidentBytes(100 * mib), 96 * mib);
    expect(gpuRegularBufferBudgetForResidentBytes(128 * mib), 96 * mib);
    expect(gpuRegularBufferBudgetForResidentBytes(160 * mib), 96 * mib);
  });

  test('regular buffer budget rejects invalid inputs and bounds', () {
    expect(() => gpuRegularBufferBudgetForResidentBytes(-1), throwsRangeError);
    expect(
      () => gpuRegularBufferBudgetForResidentBytes(
        1,
        minBytes: 100,
        maxBytes: 99,
      ),
      throwsArgumentError,
    );
    expect(
      () => gpuRegularBufferBudgetForResidentBytes(1, growthStepBytes: 0),
      throwsArgumentError,
    );
  });

  test('fill extrusion cache budget follows two recent working sets', () {
    const mib = 1024 * 1024;

    expect(gpuFillExtrusionBudgetForWorkingSetBytes(0), 64 * mib);
    expect(gpuFillExtrusionBudgetForWorkingSetBytes(16 * mib), 64 * mib);
    expect(gpuFillExtrusionBudgetForWorkingSetBytes(32 * mib), 64 * mib);
    expect(gpuFillExtrusionBudgetForWorkingSetBytes(40 * mib), 80 * mib);
    expect(gpuFillExtrusionBudgetForWorkingSetBytes(64 * mib), 96 * mib);
    expect(gpuFillExtrusionBudgetForWorkingSetBytes(80 * mib), 96 * mib);
    expect(gpuFillExtrusionBudgetForWorkingSetBytes(96 * mib), 96 * mib);
    expect(gpuFillExtrusionBudgetForWorkingSetBytes(128 * mib), 96 * mib);
  });

  test(
    'fill extrusion budget grows immediately but shrinks only after idle',
    () {
      const mib = 1024 * 1024;

      expect(
        gpuFillExtrusionBudgetWithHysteresis(
          currentBudgetBytes: 64 * mib,
          targetBudgetBytes: 112 * mib,
          hasRecentWorkingSet: true,
          framesSinceRecentUse: 0,
        ),
        112 * mib,
      );
      expect(
        gpuFillExtrusionBudgetWithHysteresis(
          currentBudgetBytes: 112 * mib,
          targetBudgetBytes: 64 * mib,
          hasRecentWorkingSet: true,
          framesSinceRecentUse: 0,
        ),
        112 * mib,
      );
      expect(
        gpuFillExtrusionBudgetWithHysteresis(
          currentBudgetBytes: 112 * mib,
          targetBudgetBytes: 64 * mib,
          hasRecentWorkingSet: false,
          framesSinceRecentUse: 119,
          idleShrinkFrames: 120,
        ),
        112 * mib,
      );
      expect(
        gpuFillExtrusionBudgetWithHysteresis(
          currentBudgetBytes: 112 * mib,
          targetBudgetBytes: 64 * mib,
          hasRecentWorkingSet: false,
          framesSinceRecentUse: 120,
          idleShrinkFrames: 120,
        ),
        64 * mib,
      );
    },
  );

  test('fill extrusion cache budget rejects invalid inputs and bounds', () {
    expect(
      () => gpuFillExtrusionBudgetForWorkingSetBytes(-1),
      throwsRangeError,
    );
    expect(
      () => gpuFillExtrusionBudgetForWorkingSetBytes(
        1,
        minBytes: 100,
        maxBytes: 99,
      ),
      throwsArgumentError,
    );
    expect(
      () => gpuFillExtrusionBudgetWithHysteresis(
        currentBudgetBytes: -1,
        targetBudgetBytes: 0,
        hasRecentWorkingSet: false,
        framesSinceRecentUse: 0,
      ),
      throwsArgumentError,
    );
  });
}
