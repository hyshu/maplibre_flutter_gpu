import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_metrics.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('resource timing metrics aggregate lookups, uploads, and evictions', () {
    final metrics = GpuResourceTimingMetrics()
      ..recordVertexLookup(hit: true)
      ..recordVertexLookup(hit: false)
      ..recordIndexLookup(hit: true)
      ..recordTextureLookup(hit: false)
      ..recordRepack(micros: 40)
      ..recordRepack(micros: 80)
      ..recordVertexUpload(micros: 120, bytes: 1024)
      ..recordVertexUpload(micros: 300, bytes: 2048, frameOwned: true)
      ..recordIndexUpload(micros: 90, bytes: 512, frameOwned: true)
      ..recordTextureUpload(micros: 500, bytes: 4096)
      ..recordExpiryEvictions(count: 3, bytes: 8192)
      ..recordBudgetEviction(bytes: 16384);

    final snapshot = metrics.takeSnapshotAndReset();

    expect(snapshot.vertexCacheHits, 1);
    expect(snapshot.vertexCacheMisses, 1);
    expect(snapshot.indexCacheHits, 1);
    expect(snapshot.indexCacheMisses, 0);
    expect(snapshot.textureCacheHits, 0);
    expect(snapshot.textureCacheMisses, 1);
    expect(snapshot.averageRepackMicros, 60);
    expect(snapshot.repackMaxMicros, 80);
    expect(snapshot.repackLayouts, isEmpty);
    expect(snapshot.vertexUploadCount, 2);
    expect(snapshot.averageVertexUploadMicros, 210);
    expect(snapshot.vertexUploadBytes, 3072);
    expect(snapshot.vertexUploadMaxMicros, 300);
    expect(snapshot.indexUploadCount, 1);
    expect(snapshot.indexUploadBytes, 512);
    expect(snapshot.textureUploadCount, 1);
    expect(snapshot.textureUploadBytes, 4096);
    expect(snapshot.frameVertexUploadCount, 1);
    expect(snapshot.frameVertexUploadBytes, 2048);
    expect(snapshot.frameIndexUploadCount, 1);
    expect(snapshot.frameIndexUploadBytes, 512);
    expect(snapshot.expiryEvictionCount, 3);
    expect(snapshot.expiryEvictionBytes, 8192);
    expect(snapshot.budgetEvictionCount, 1);
    expect(snapshot.budgetEvictionBytes, 16384);
  });

  test('cached repacks are grouped by shader and vertex layout', () {
    final metrics = GpuResourceTimingMetrics()
      ..recordVertexLookup(
        hit: false,
        shader: ShaderType.line,
        sourceStride: 8,
        gpuStride: 16,
        vertexCount: 100,
      )
      ..recordRepack(micros: 100)
      ..recordVertexLookup(
        hit: false,
        shader: ShaderType.line,
        sourceStride: 8,
        gpuStride: 16,
        vertexCount: 200,
      )
      ..recordRepack(micros: 300)
      ..recordVertexLookup(
        hit: false,
        shader: ShaderType.lineSDF,
        sourceStride: 12,
        gpuStride: 20,
        vertexCount: 50,
      )
      ..recordRepack(micros: 500);

    final snapshot = metrics.takeSnapshotAndReset();

    expect(snapshot.repackLayouts, hasLength(2));
    final sdf = snapshot.repackLayouts[0];
    expect(sdf.shader, ShaderType.lineSDF);
    expect(sdf.sourceStride, 12);
    expect(sdf.gpuStride, 20);
    expect(sdf.count, 1);
    expect(sdf.micros, 500);
    expect(sdf.inputBytes, 600);
    expect(sdf.outputBytes, 1000);

    final line = snapshot.repackLayouts[1];
    expect(line.shader, ShaderType.line);
    expect(line.sourceStride, 8);
    expect(line.gpuStride, 16);
    expect(line.count, 2);
    expect(line.averageMicros, 200);
    expect(line.maxMicros, 300);
    expect(line.inputBytes, 2400);
    expect(line.outputBytes, 4800);
  });

  test('resource timing snapshots reset the interval', () {
    final metrics = GpuResourceTimingMetrics()
      ..recordVertexLookup(
        hit: false,
        shader: ShaderType.fill,
        sourceStride: 4,
        gpuStride: 8,
        vertexCount: 10,
      )
      ..recordRepack(micros: 20)
      ..recordVertexUpload(micros: 10, bytes: 32);

    metrics.takeSnapshotAndReset();
    final empty = metrics.takeSnapshotAndReset();

    expect(empty.vertexLookupCount, 0);
    expect(empty.indexLookupCount, 0);
    expect(empty.textureLookupCount, 0);
    expect(empty.repackCount, 0);
    expect(empty.repackLayouts, isEmpty);
    expect(empty.vertexUploadCount, 0);
    expect(empty.indexUploadCount, 0);
    expect(empty.textureUploadCount, 0);
    expect(empty.expiryEvictionCount, 0);
    expect(empty.budgetEvictionCount, 0);
  });
}
