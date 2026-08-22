import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_metrics.dart';

void main() {
  test('upload size attribution uses slab-oriented boundaries', () {
    expect(gpuUploadSizeClassForBytes(0), GpuUploadSizeClass.small);
    expect(gpuUploadSizeClassForBytes(16 * 1024), GpuUploadSizeClass.small);
    expect(
      gpuUploadSizeClassForBytes(16 * 1024 + 1),
      GpuUploadSizeClass.medium,
    );
    expect(
      gpuUploadSizeClassForBytes(256 * 1024),
      GpuUploadSizeClass.medium,
    );
    expect(
      gpuUploadSizeClassForBytes(256 * 1024 + 1),
      GpuUploadSizeClass.large,
    );
  });

  test('upload size attribution rejects negative byte counts', () {
    expect(() => gpuUploadSizeClassForBytes(-1), throwsRangeError);
  });
}
