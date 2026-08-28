import 'package:flutter/widgets.dart';
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

  test('resource pool trims inactive tail without resetting active slots', () {
    final pool = MapGpuResourcePool();
    addTearDown(pool.dispose);
    final active = pool.acquire(
      0,
      minimumLayerIndex: null,
      maximumLayerIndex: 3,
      clearToTransparent: false,
    );
    final inactive = pool.acquire(
      1,
      minimumLayerIndex: 3,
      maximumLayerIndex: 7,
      clearToTransparent: true,
    );
    active
      ..width = 400
      ..height = 300
      ..lastPaintedSeq = 12;
    inactive
      ..width = 400
      ..height = 300
      ..lastPaintedSeq = 12;

    pool.trimToActiveSlotCount(1);

    expect(pool.length, 1);
    expect(active.width, 400);
    expect(active.height, 300);
    expect(active.lastPaintedSeq, 12);
    expect(inactive.width, 0);
    expect(inactive.height, 0);
    expect(inactive.lastPaintedSeq, -1);

    final replacement = pool.acquire(
      1,
      minimumLayerIndex: 3,
      maximumLayerIndex: 9,
      clearToTransparent: true,
    );
    expect(identical(replacement, inactive), isFalse);
  });

  test('resource pool rejects counts outside its acquired prefix', () {
    final pool = MapGpuResourcePool();
    addTearDown(pool.dispose);
    pool.acquire(
      0,
      minimumLayerIndex: null,
      maximumLayerIndex: null,
      clearToTransparent: false,
    );

    expect(() => pool.trimToActiveSlotCount(-1), throwsRangeError);
    expect(() => pool.trimToActiveSlotCount(2), throwsRangeError);
    expect(pool.length, 1);
  });

  testWidgets('widget topology shrink releases inactive pooled resources', (
    tester,
  ) async {
    final key = GlobalKey<_GpuResourcePoolHostState>();
    await tester.pumpWidget(_GpuResourcePoolHost(key: key, activeSlotCount: 3));
    final state = key.currentState!;
    final active = state.resources[0]
      ..width = 640
      ..height = 480
      ..lastPaintedSeq = 20;
    final inactive = state.resources[1]
      ..width = 640
      ..height = 480
      ..lastPaintedSeq = 20;

    await tester.pumpWidget(_GpuResourcePoolHost(key: key, activeSlotCount: 1));

    expect(state.retainedSlotCount, 1);
    expect(state.resources.single, same(active));
    expect(active.width, 640);
    expect(active.lastPaintedSeq, 20);
    expect(inactive.width, 0);
    expect(inactive.lastPaintedSeq, -1);

    await tester.pumpWidget(_GpuResourcePoolHost(key: key, activeSlotCount: 2));
    expect(state.resources[0], same(active));
    expect(state.resources[1], isNot(same(inactive)));

    await tester.pumpWidget(const SizedBox.shrink());
    expect(active.width, 0);
    expect(active.lastPaintedSeq, -1);
  });

  test('map trims pooled targets after assembling the active composition', () {
    final map = SourceFiles.mapWidgetOnly;
    final start = map.indexOf('Widget _buildRenderedMap(Size screenSize)');
    final end = map.indexOf('void _emitMapClick(', start);
    final buildRenderedMap = map.substring(start, end);

    expect(
      RegExp(
        r'_gpuStratumResources\.trimToActiveSlotCount\('
        r'gpuLayerRanges\.length\);',
      ).allMatches(buildRenderedMap).length,
      2,
    );
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

class _GpuResourcePoolHost extends StatefulWidget {
  const new({super.key, required this.activeSlotCount});

  final int activeSlotCount;

  @override
  State<_GpuResourcePoolHost> createState() => _GpuResourcePoolHostState();
}

class _GpuResourcePoolHostState extends State<_GpuResourcePoolHost> {
  final _pool = MapGpuResourcePool();
  List<MapGpuResources> resources = const [];

  int get retainedSlotCount => _pool.length;

  @override
  Widget build(BuildContext context) {
    resources = [
      for (var index = 0; index < widget.activeSlotCount; index += 1)
        _pool.acquire(
          index,
          minimumLayerIndex: index,
          maximumLayerIndex: index + 1,
          clearToTransparent: index != 0,
        ),
    ];
    _pool.trimToActiveSlotCount(widget.activeSlotCount);

    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _pool.dispose();
    super.dispose();
  }
}
