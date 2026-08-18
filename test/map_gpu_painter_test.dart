import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/widgets/map_gpu_painter.dart';

import 'support/source_files.dart';

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

  test('resource pool reuses slots across topology changes', () {
    final pool = MapGpuResourcePool();
    addTearDown(pool.dispose);
    final first = pool.acquire(
      0,
      minimumLayerIndex: null,
      maximumLayerIndex: 4,
      clearToTransparent: false,
    );
    first
      ..lastPaintedSeq = 10
      ..lastPaintedGeneration = 7
      ..width = 400
      ..height = 300;
    pool.acquire(
      1,
      minimumLayerIndex: 4,
      maximumLayerIndex: 8,
      clearToTransparent: true,
    );

    final reused = pool.acquire(
      0,
      minimumLayerIndex: null,
      maximumLayerIndex: 6,
      clearToTransparent: false,
    );

    expect(identical(reused, first), isTrue);
    expect(reused.lastPaintedSeq, -1);
    expect(reused.lastPaintedGeneration, -1);
    expect(reused.width, 400);
    expect(reused.height, 300);
    expect(pool.length, 2);
  });

  test('unchanged resource range keeps its completed frame', () {
    final pool = MapGpuResourcePool();
    addTearDown(pool.dispose);
    final resources = pool.acquire(
      0,
      minimumLayerIndex: 3,
      maximumLayerIndex: 9,
      clearToTransparent: true,
    )..lastPaintedSeq = 12;

    final reused = pool.acquire(
      0,
      minimumLayerIndex: 3,
      maximumLayerIndex: 9,
      clearToTransparent: true,
    );

    expect(identical(reused, resources), isTrue);
    expect(reused.lastPaintedSeq, 12);
  });

  test('frame preparation precedes empty stratum surface selection', () {
    final painter = SourceFiles.gpuPainterOnly;
    final prepare = painter.indexOf('gpuRenderer.prepareFrame(');
    final surface = painter.indexOf('final needsSurface =');

    expect(prepare, greaterThanOrEqualTo(0));
    expect(surface, greaterThan(prepare));
    expect(painter, contains('preparedFrame.hasCommandsInStratum('));
    expect(painter, contains('gpuRenderer.renderPreparedFrame('));
  });

  test('last stratum finalizes caches even when recording is skipped', () {
    final painter = SourceFiles.gpuPainterOnly;
    final finallyBlock = painter.indexOf('} finally {');
    final finish = painter.indexOf(
      'if (evictResourceCaches) gpuRenderer.finishFrame();',
      finallyBlock,
    );

    expect(finallyBlock, greaterThanOrEqualTo(0));
    expect(finish, greaterThan(finallyBlock));
  });

  test('first stratum starts replay lifecycle before stale-frame checks', () {
    final painter = SourceFiles.gpuPainterOnly;
    final begin = painter.indexOf(
      'if (advanceResourceFrame) gpuRenderer.beginFrameReplay();',
    );
    final staleCheck = painter.indexOf(
      'currentFrameSeq != resources.lastPaintedSeq',
    );

    expect(begin, greaterThanOrEqualTo(0));
    expect(staleCheck, greaterThan(begin));
  });
}
