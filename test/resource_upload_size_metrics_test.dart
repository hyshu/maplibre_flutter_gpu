import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_metrics.dart';

void main() {
  test('upload diagnostics report the largest individual allocation', () {
    final previousPrint = debugPrint;
    final messages = <String>[];
    debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
    addTearDown(() => debugPrint = previousPrint);
    final metrics = GpuResourceTimingMetrics();
    metrics.recordVertexUpload(micros: 12, bytes: 3669960);
    metrics.recordVertexUpload(micros: 5, bytes: 1000000);
    metrics.recordIndexUpload(micros: 2, bytes: 400);
    metrics.takeSnapshotAndReset();
    final upload = messages.singleWhere(
      (message) => message.startsWith('[GpuUploadSize]'),
    );
    expect(upload, contains('maxBytes=3669960'));
    expect(upload, contains('maxBytes=400'));
    messages.clear();
    metrics.recordVertexUpload(micros: 4, bytes: 500000);
    metrics.takeSnapshotAndReset();
    expect(messages.join(), contains('maxBytes=500000'));
    expect(messages.join(), isNot(contains('maxBytes=3669960')));
  });

  test('upload size attribution uses slab-oriented boundaries', () {
    expect(gpuUploadSizeClassForBytes(0), GpuUploadSizeClass.small);
    expect(gpuUploadSizeClassForBytes(16 * 1024), GpuUploadSizeClass.small);
    expect(
      gpuUploadSizeClassForBytes(16 * 1024 + 1),
      GpuUploadSizeClass.medium,
    );
    expect(gpuUploadSizeClassForBytes(256 * 1024), GpuUploadSizeClass.medium);
    expect(
      gpuUploadSizeClassForBytes(256 * 1024 + 1),
      GpuUploadSizeClass.large,
    );
  });

  test(
    'upload size attribution rejects negative byte counts',
    () => expect(() => gpuUploadSizeClassForBytes(-1), throwsRangeError),
  );
}
