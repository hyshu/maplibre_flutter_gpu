import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/prepared_graph_metrics.dart';

void main() {
  test('detailed timing metrics aggregate phases, maxima, and reasons', () {
    final metrics = PreparedGraphDetailedTimingMetrics()
      ..recordHit(totalMicros: 80, validationMicros: 20, refreshMicros: 60)
      ..recordHit(totalMicros: 120, validationMicros: 30, refreshMicros: 90)
      ..recordRebuild(
        totalMicros: 5000,
        reason: .topologyMismatch,
        validationMicros: 40,
        decodeMicros: 4800,
        captureMicros: 160,
      )
      ..recordRebuild(
        totalMicros: 6200,
        reason: .refreshFailed,
        validationMicros: 50,
        refreshMicros: 400,
        decodeMicros: 5500,
        captureMicros: 250,
      )
      ..recordRebuild(
        totalMicros: 1000,
        reason: .noGraph,
        decodeMicros: 900,
        captureMicros: 100,
      );

    final snapshot = metrics.takeSnapshotAndReset();

    expect(snapshot.totals.hitCount, 2);
    expect(snapshot.totals.rebuildCount, 3);
    expect(snapshot.totals.hitRate, closeTo(0.4, 0.000001));
    expect(snapshot.hitMaxMicros, 120);
    expect(snapshot.rebuildMaxMicros, 6200);
    expect(snapshot.validationCount, 4);
    expect(snapshot.averageValidationMicros, 35);
    expect(snapshot.refreshCount, 3);
    expect(snapshot.averageRefreshMicros, closeTo(550 / 3, 0.000001));
    expect(snapshot.decodeCount, 3);
    expect(snapshot.averageDecodeMicros, closeTo(11200 / 3, 0.000001));
    expect(snapshot.captureCount, 3);
    expect(snapshot.averageCaptureMicros, 170);
    expect(snapshot.noGraphRebuildCount, 1);
    expect(snapshot.topologyMismatchRebuildCount, 1);
    expect(snapshot.refreshFailedRebuildCount, 1);
  });

  test('detailed timing snapshots reset every interval', () {
    final metrics = PreparedGraphDetailedTimingMetrics()
      ..recordHit(totalMicros: 75, validationMicros: 25, refreshMicros: 50);

    metrics.takeSnapshotAndReset();
    final empty = metrics.takeSnapshotAndReset();

    expect(empty.totals.sampleCount, 0);
    expect(empty.hitMaxMicros, 0);
    expect(empty.rebuildMaxMicros, 0);
    expect(empty.averageValidationMicros, isNull);
    expect(empty.averageRefreshMicros, isNull);
    expect(empty.averageDecodeMicros, isNull);
    expect(empty.averageCaptureMicros, isNull);
    expect(empty.noGraphRebuildCount, 0);
    expect(empty.topologyMismatchRebuildCount, 0);
    expect(empty.refreshFailedRebuildCount, 0);
  });
}
