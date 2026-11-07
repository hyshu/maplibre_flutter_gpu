import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/cpu_profile.dart';

void main() {
  test('disabled profiling creates no clocks and collects no samples', () {
    final profile = GpuCpuProfile(enabled: false);
    expect(profile.start(), isNull);
    profile.record('meshVertexPack', 100, bytes: 200);
    profile.finish('meshVertexPack', null);
    expect(profile.takeSnapshotAndReset(), isEmpty);
  });

  test('interval summaries preserve phase counts, bytes, and tail latency', () {
    final profile = GpuCpuProfile(enabled: true);
    for (var micros = 20; micros > 0; micros -= 1) {
      profile.record('meshVertexUploadCall', micros, bytes: 32);
    }
    profile.record('stratumRecord', 1000);
    final snapshot = profile.takeSnapshotAndReset();
    expect(snapshot['meshVertexUploadCall'], (
      count: 20,
      totalMicros: 210,
      p95Micros: 19,
      maxMicros: 20,
      bytes: 640,
    ));
    expect(snapshot['stratumRecord'], (
      count: 1,
      totalMicros: 1000,
      p95Micros: 1000,
      maxMicros: 1000,
      bytes: 0,
    ));
    expect(profile.takeSnapshotAndReset(), isEmpty);
    profile.record('meshVertexUploadCall', 5, bytes: 8);
    expect(profile.takeSnapshotAndReset()['meshVertexUploadCall'], (
      count: 1,
      totalMicros: 5,
      p95Micros: 5,
      maxMicros: 5,
      bytes: 8,
    ));
  });
}
