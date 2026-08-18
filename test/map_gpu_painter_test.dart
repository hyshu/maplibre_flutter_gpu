import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/widgets/map_gpu_painter.dart';

void main() {
  test('transparent empty strata do not need GPU surfaces', () {
    expect(
      gpuStratumNeedsSurface(
        clearToTransparent: true,
        hasNativeCommands: false,
        hasGpuCallback: false,
      ),
      isFalse,
    );
    expect(
      gpuStratumNeedsSurface(
        clearToTransparent: false,
        hasNativeCommands: false,
        hasGpuCallback: false,
      ),
      isTrue,
    );
    expect(
      gpuStratumNeedsSurface(
        clearToTransparent: true,
        hasNativeCommands: true,
        hasGpuCallback: false,
      ),
      isTrue,
    );
    expect(
      gpuStratumNeedsSurface(
        clearToTransparent: true,
        hasNativeCommands: false,
        hasGpuCallback: true,
      ),
      isTrue,
    );
  });

  test('hiding an empty stratum makes retained textures reusable', () {
    final resources = MapGpuResources()..displayIndex = 2;

    resources.hideLastImage();

    expect(resources.lastImage, isNull);
    expect(resources.displayIndex, -1);
  });
}
