import 'dart:ffi' hide Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/fill_extrusion_customizer.dart';
import 'package:maplibre_flutter_gpu/src/gpu/render_context.dart';
import 'package:maplibre_flutter_gpu/src/gpu/renderer.dart';
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart';
import 'package:maplibre_flutter_gpu/src/widgets/map_gpu_painter.dart';

void main() {
  const android = TargetPlatformVariant({TargetPlatform.android});

  testWidgets('preparation releases before either stratum uses its surface', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.widget());

    expect(harness.events, [
      'prepare',
      'release',
      'surface:0',
      'replay',
      'surface:1',
    ]);
    expect(harness.bridge.metadataReads, 1);
    expect(harness.bridge.transformReads, 1);
    expect(harness.bridge.releases, [19]);
    expect(harness.releasedCallbacks, 1);
    expect(harness.snapshot.isActive, isFalse);
    expect(harness.paintingDepth, 0);
    expect(harness.renderer.finalizations, 1);
    expect(
      harness.resources.map((resource) => resource.lastPaintedGeneration),
      everyElement(19),
    );
    expect(
      harness.resources.map((resource) => resource.lastPaintedSeq),
      everyElement(7),
    );
    final prepared = harness.renderer.prepared!;
    expect(prepared.clearColor, _Bridge.clearColor);
    expect(prepared.mapTransform!.viewProjectionMatrix[0], 1);
    expect(harness.bridge.matrix[0], 99);

    harness.renderer.fillExtrusions.styleChanged();
    harness.repaint.notifyListeners();
    await tester.pump();

    expect(harness.bridge.metadataReads, 1);
    expect(harness.bridge.transformReads, 1);
    expect(harness.bridge.releases, [19]);
    expect(harness.releasedCallbacks, 1);
    expect(
      harness.resources.map((resource) => resource.lastPaintedGeneration),
      everyElement(19),
    );
    expect(tester.takeException(), isNull);
  }, variant: android);

  testWidgets('later stratum can prepare after an earlier preparation fails', (
    tester,
  ) async {
    final harness = _Harness(failedPreparations: 1);
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.widget());

    expect(harness.events, ['prepare', 'prepare', 'release', 'surface:1']);
    expect(harness.bridge.metadataReads, 2);
    expect(harness.bridge.releases, [19]);
    expect(harness.releasedCallbacks, 1);
    expect(harness.resources[0].lastPaintedSeq, -1);
    expect(harness.resources[1].lastPaintedGeneration, 19);
    expect(harness.paintingDepth, 0);
  }, variant: android);

  testWidgets('failed preparation returns the lease from the last stratum', (
    tester,
  ) async {
    final harness = _Harness(failedPreparations: 2);
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.widget());

    expect(harness.events, ['prepare', 'prepare', 'release']);
    expect(harness.bridge.releases, [19]);
    expect(harness.releasedCallbacks, 1);
    expect(harness.snapshot.isActive, isFalse);
    expect(harness.renderer.prepared, isNull);
    expect(harness.renderer.finalizations, 1);
    expect(harness.paintingDepth, 0);
  }, variant: android);

  testWidgets('paused paint leaves the snapshot available for resume', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.widget(renderingAllowed: false));

    expect(harness.events, isEmpty);
    expect(harness.bridge.metadataReads, 0);
    expect(harness.bridge.releases, isEmpty);
    expect(harness.snapshot.isActive, isTrue);
    expect(harness.releasedCallbacks, 0);
    expect(harness.paintingDepth, 0);
  }, variant: android);
}

class _Harness {
  _Harness({int failedPreparations = 0}) {
    bridge = _Bridge(events, () => paintingDepth);
    snapshot = bridge.acquireFrameSnapshot()!;
    pending = snapshot;
    renderer = _Renderer(events, failedPreparations, () {
      expect(snapshot.isActive, isTrue);
      expect(paintingDepth, 1);
    });
    resources = [
      for (var index = 0; index < 2; index++)
        _Resources(() {
          expect(snapshot.isActive, isFalse);
          expect(paintingDepth, 1);
          events.add('surface:$index');
        }),
    ];
  }

  final events = <String>[];
  final repaint = ChangeNotifier();
  late final _Bridge bridge;
  late final _Renderer renderer;
  late final NativeFrameSnapshotLease snapshot;
  NativeFrameSnapshotLease? pending;
  late final List<_Resources> resources;
  var releasedCallbacks = 0;
  var paintingDepth = 0;

  Widget widget({bool renderingAllowed = true}) => Row(
    textDirection: TextDirection.ltr,
    children: [
      for (var index = 0; index < 2; index++)
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
            gpuOverlayDepthMode: .isolated,
            gpuRenderingAllowed: () => renderingAllowed,
            frameSnapshotProvider: () => pending,
            onFrameSnapshotReleased: (released) {
              expect(released, same(snapshot));
              expect(released.isActive, isFalse);
              expect(paintingDepth, 1);
              releasedCallbacks++;
              pending = null;
            },
            onGpuPaintingChanged: (painting) =>
                paintingDepth += painting ? 1 : -1,
            stratumIndex: index,
            layerRanges: const [
              (minimumLayerIndex: null, maximumLayerIndex: 2),
              (minimumLayerIndex: 2, maximumLayerIndex: null),
            ],
            clearToTransparent: true,
            releaseFrameSnapshot: index == 1,
            advanceResourceFrame: index == 0,
            evictResourceCaches: index == 1,
            repaint: repaint,
          ),
        ),
    ],
  );

  void dispose() {
    renderer.fillExtrusions.dispose();
    repaint.dispose();
    for (final resource in resources) {
      resource.dispose();
    }
  }
}

class _Bridge extends Fake
    with MaplibreBridgeFrameBindings
    implements MaplibreBridge {
  _Bridge(this.events, this.paintingDepth);

  static const clearColor = (red: 0.25, green: 0.5, blue: 0.75, alpha: 1.0);
  final List<String> events;
  final int Function() paintingDepth;
  final releases = <int>[];
  final matrix = Float32List.fromList([
    for (var index = 0; index < 16; index++) index % 5 == 0 ? 1 : 0,
  ]);
  var metadataReads = 0;
  var transformReads = 0;

  @override
  bool get supportsAsyncRendering => true;

  @override
  int frameAcquire() => 19;

  @override
  void frameRelease(int generation) {
    expect(paintingDepth(), 1);
    releases.add(generation);
    matrix.fillRange(0, matrix.length, 99);
    events.add('release');
  }

  @override
  FrameCommandMetadata frameGetMetadata() {
    expect(releases, isEmpty, reason: 'Released native storage is unreadable.');
    metadataReads++;

    return (
      commands: nullptr,
      commandCount: 0,
      commandStride: 0,
      payload: nullptr,
      payloadSize: 0,
      clearColor: clearColor,
    );
  }

  @override
  FrameMapTransform frameGetMapTransform() {
    expect(releases, isEmpty, reason: 'Released native storage is unreadable.');
    transformReads++;

    return (
      viewProjectionMatrix: matrix,
      worldSize: 512,
      originX: 100,
      originY: 200,
      zoom: 1,
    );
  }
}

class _Renderer extends Fake implements GpuFrameRenderer {
  _Renderer(this.events, this.failedPreparations, this.beforePrepare);

  final List<String> events;
  int failedPreparations;
  final VoidCallback beforePrepare;
  GpuPreparedFrame? prepared;
  var finalizations = 0;

  @override
  final fillExtrusions = FillExtrusionCustomizer.withResources(
    createPipeline: (_, _, _) => throw StateError('No material expected'),
    uploadBuffer: (_) => throw StateError('No geometry expected'),
  );

  @override
  int get frameSeq => 7;

  @override
  void beginFrameReplay() {}

  @override
  void finishFrame() => finalizations++;

  @override
  GpuPreparedFrame prepareFrame({
    required FrameCommandMetadata frameMetadata,
    required int physicalWidth,
    required int physicalHeight,
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
    required List<GpuStyleLayerRange> layerRanges,
    MapLibreGpuMapTransform? mapTransform,
    int nativeGeneration = 0,
    bool advanceResourceFrame = true,
  }) {
    beforePrepare();
    events.add('prepare');
    if (failedPreparations > 0) {
      failedPreparations--;
      throw StateError('Preparation failed');
    }
    prepared = GpuPreparedFrame.emptyForTesting(
      clearColor: frameMetadata.clearColor,
      mapTransform: mapTransform,
      nativeGeneration: nativeGeneration,
    );

    return prepared!;
  }

  @override
  GpuPreparedFrame? prepareFrameReplay({
    required int physicalWidth,
    required int physicalHeight,
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
    required List<GpuStyleLayerRange> layerRanges,
  }) {
    events.add('replay');
    fillExtrusions.reapply(const []);

    return prepared;
  }
}

class _Resources extends MapGpuResources {
  _Resources(this.beforeSurface);

  final VoidCallback beforeSurface;

  @override
  void hideLastImage() {
    beforeSurface();
    super.hideLastImage();
  }
}
