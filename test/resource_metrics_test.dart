import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_metrics.dart';

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

  test('resource timing snapshots reset the interval', () {
    final metrics = GpuResourceTimingMetrics()
      ..recordVertexLookup(hit: true)
      ..recordVertexUpload(micros: 10, bytes: 32);

    metrics.takeSnapshotAndReset();
    final empty = metrics.takeSnapshotAndReset();

    expect(empty.vertexLookupCount, 0);
    expect(empty.indexLookupCount, 0);
    expect(empty.textureLookupCount, 0);
    expect(empty.repackCount, 0);
    expect(empty.vertexUploadCount, 0);
    expect(empty.indexUploadCount, 0);
    expect(empty.textureUploadCount, 0);
    expect(empty.expiryEvictionCount, 0);
    expect(empty.budgetEvictionCount, 0);
  });
}
