import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/fill_extrusion_customizer.dart';
import 'package:maplibre_flutter_gpu/src/gpu/render_context.dart';
import 'package:maplibre_flutter_gpu/src/gpu/renderer.dart';
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart';
import 'package:maplibre_flutter_gpu/src/widgets/map_gpu_painter.dart';

import 'support/source_files.dart';

void main() {
  for (final (asyncSnapshots, replayAvailable) in const [
    (true, false),
    (true, true),
    (false, true),
  ]) {
    testWidgets('stationary repaint updates each stratum '
        '(async $asyncSnapshots, retained $replayAvailable)', (tester) async {
      final customizer = FillExtrusionCustomizer.withResources(
        createPipeline: (_, _, _) => throw StateError('No material expected'),
        uploadBuffer: (_) => throw StateError('No geometry expected'),
      );
      final repaint = ChangeNotifier();
      addTearDown(customizer.dispose);
      addTearDown(repaint.dispose);
      const clearColor = (red: 0.25, green: 0.5, blue: 0.75, alpha: 1.0);
      final matrix = Float32List.fromList([
        for (var index = 0; index < 16; index += 1) index % 5 == 0 ? 1 : 0,
      ]);
      final preparedFrame = GpuPreparedFrame.emptyForTesting(
        clearColor: clearColor,
        mapTransform: MapLibreGpuMapTransform(
          viewProjectionMatrix: matrix,
          worldSize: 512,
          originX: 100,
          originY: 200,
          zoom: 1,
        ),
      );
      matrix[0] = 99;
      final renderer = _ReplayRenderer(
        customizer,
        replayAvailable ? preparedFrame : null,
      );
      final bridge = _ReplayBridge(asyncSnapshots);
      var paintingDepth = 0;
      final resources = [
        for (var index = 0; index < 2; index += 1)
          MapGpuResources()
            ..lastPaintedSeq = renderer.frameSeq
            ..lastPaintedGeneration = 3
            ..lastPaintedFillExtrusionRevision = customizer.repaintRevision,
      ];
      const ranges = [
        (minimumLayerIndex: null, maximumLayerIndex: 2),
        (minimumLayerIndex: 2, maximumLayerIndex: null),
      ];
      await tester.pumpWidget(
        Row(
          textDirection: TextDirection.ltr,
          children: [
            for (var index = 0; index < resources.length; index += 1)
              CustomPaint(
                size: const Size(100, 100),
                painter: MapGpuPainter(
                  bridge: bridge,
                  gpuRenderer: renderer,
                  resources: resources[index],
                  width: 100,
                  height: 100,
                  logicalWidth: 100,
                  logicalHeight: 100,
                  devicePixelRatio: 1,
                  frameSeq: renderer.frameSeq,
                  gpuMapRenderCallback: null,
                  gpuRenderCallback: null,
                  gpuOverlayDepthMode: MapLibreGpuDepthMode.isolated,
                  gpuRenderingAllowed: () => true,
                  frameSnapshotProvider: () {
                    expect(paintingDepth, 1);

                    return null;
                  },
                  onFrameSnapshotReleased: null,
                  onGpuPaintingChanged: (painting) =>
                      paintingDepth += painting ? 1 : -1,
                  stratumIndex: index,
                  layerRanges: ranges,
                  clearToTransparent: true,
                  advanceResourceFrame: index == 0,
                  evictResourceCaches: index == resources.length - 1,
                  repaint: repaint,
                ),
              ),
          ],
        ),
      );
      expect(renderer.replayRequests, 0);
      expect(paintingDepth, 0);

      customizer.styleChanged();
      repaint.notifyListeners();
      await tester.pump();

      expect(renderer.replayRequests, 2);
      expect(paintingDepth, 0);
      expect(customizer.needsReapply, isFalse);
      expect(bridge.metadataReads, 0);
      expect(bridge.transformReads, 0);
      expect(renderer.frameSeq, 7);
      expect(preparedFrame.clearColor, clearColor);
      expect(preparedFrame.mapTransform!.viewProjectionMatrix[0], 1);
      expect(preparedFrame.mapTransform!.originX, 100);
      expect(
        resources.map((resource) => resource.lastPaintedFillExtrusionRevision),
        everyElement(replayAvailable ? customizer.repaintRevision : 0),
        reason: 'Each stratum acknowledges a successful replay independently.',
      );
      expect(
        resources.map((resource) => resource.lastPaintedGeneration),
        everyElement(3),
      );

      repaint.notifyListeners();
      await tester.pump();

      expect(renderer.replayRequests, replayAvailable ? 2 : 4);
      expect(bridge.metadataReads, 0);
      expect(bridge.transformReads, 0);
    });
  }

  testWidgets(
    'paused GPU painter ignores external repaint and resource changes',
    (tester) async {
      final customizer = FillExtrusionCustomizer.withResources(
        createPipeline: (_, _, _) => throw StateError('No material expected'),
        uploadBuffer: (_) => throw StateError('No geometry expected'),
      );
      final repaint = ChangeNotifier();
      final renderer = _ReplayRenderer(customizer, null);
      final bridge = _ReplayBridge(true);
      final resources = MapGpuResources()..lastPaintedSeq = 5;
      var callbacks = 0;
      var frameReads = 0;
      var paints = 0;
      addTearDown(customizer.dispose);
      addTearDown(repaint.dispose);
      addTearDown(resources.dispose);

      await tester.pumpWidget(
        CustomPaint(
          size: const Size(100, 100),
          painter: MapGpuPainter(
            bridge: bridge,
            gpuRenderer: renderer,
            resources: resources,
            width: 100,
            height: 100,
            logicalWidth: 100,
            logicalHeight: 100,
            devicePixelRatio: 1,
            frameSeq: renderer.frameSeq,
            gpuMapRenderCallback: (_) => callbacks++,
            gpuRenderCallback: (_) => callbacks++,
            gpuOverlayDepthMode: MapLibreGpuDepthMode.isolated,
            gpuRenderingAllowed: () => false,
            frameSnapshotProvider: () {
              frameReads++;

              return null;
            },
            onFrameSnapshotReleased: null,
            onFramePainted: () => paints++,
            stratumIndex: 0,
            layerRanges: const [
              (minimumLayerIndex: null, maximumLayerIndex: null),
            ],
            repaint: repaint,
          ),
        ),
      );
      for (var frame = 0; frame < 3; frame++) {
        customizer.styleChanged();
        repaint.notifyListeners();
        await tester.pump();
      }
      expect(callbacks, 0);
      expect(frameReads, 0);
      expect(paints, 0);
      expect(renderer.replayRequests, 0);
      expect(bridge.metadataReads, 0);
      expect(bridge.transformReads, 0);
      expect(resources.lastPaintedSeq, 5);
      expect(tester.takeException(), isNull);
    },
  );

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
      ..lastPaintedFillExtrusionRevision = 2
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
    expect(reused.lastPaintedFillExtrusionRevision, -1);
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

  test('memory pressure frees images without replacing painter resources', () {
    final pool = MapGpuResourcePool();
    addTearDown(pool.dispose);
    final resources = pool.acquire(
      0,
      minimumLayerIndex: null,
      maximumLayerIndex: 3,
      clearToTransparent: false,
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const Color(0xff000000), BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(4, 4);
    picture.dispose();
    resources
      ..lastImage = image
      ..lastPaintedSeq = 12
      ..width = 4
      ..height = 4;
    resources.images.add(image);

    pool.reduceMemoryUse();

    expect(image.debugDisposed, isTrue);
    expect(resources.lastImage, isNull);
    expect(resources.images, isEmpty);
    expect(resources.width, 0);
    expect(resources.lastPaintedSeq, -1);
    expect(
      pool.acquire(
        0,
        minimumLayerIndex: null,
        maximumLayerIndex: 3,
        clearToTransparent: false,
      ),
      same(resources),
    );
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

    expect(
      RegExp(
        r'resources\.trimToActiveSlotCount\('
        r'gpuLayerRanges\.length\);',
      ).allMatches(map).length,
      1,
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

class _ReplayRenderer extends Fake implements GpuFrameRenderer {
  _ReplayRenderer(this.fillExtrusions, this.preparedFrame);

  @override
  final FillExtrusionCustomizer fillExtrusions;
  final GpuPreparedFrame? preparedFrame;
  var replayRequests = 0;

  @override
  int get frameSeq => 7;

  @override
  void beginFrameReplay() {}

  @override
  void finishFrame() {}

  @override
  GpuPreparedFrame? prepareFrameReplay({
    required int physicalWidth,
    required int physicalHeight,
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
    required List<GpuStyleLayerRange> layerRanges,
  }) {
    replayRequests += 1;
    fillExtrusions.reapply(const []);

    return preparedFrame;
  }
}

class _ReplayBridge extends Fake implements MaplibreBridge {
  _ReplayBridge(this.supportsAsyncRendering);

  @override
  final bool supportsAsyncRendering;
  var metadataReads = 0;
  var transformReads = 0;

  @override
  FrameCommandMetadata frameGetMetadata() {
    metadataReads += 1;
    throw StateError('No active native snapshot');
  }

  @override
  FrameMapTransform? frameGetMapTransform() {
    transformReads += 1;
    throw StateError('No active native snapshot');
  }
}

class _GpuResourcePoolHost extends StatefulWidget {
  const new({super.key, required this.activeSlotCount});

  final int activeSlotCount;

  @override
  State<_GpuResourcePoolHost> createState() => _GpuResourcePoolHostState();
}

class _GpuResourcePoolHostState extends State<_GpuResourcePoolHost> {
  final _pool = MapGpuResourcePool();
  var resources = const <MapGpuResources>[];

  int get retainedSlotCount => _pool.length;

  @override
  Widget build(context) {
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
