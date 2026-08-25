import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart';
import 'package:maplibre_flutter_gpu/src/state/gesture/gesture_coordinator.dart';
import 'package:maplibre_flutter_gpu/src/state/gesture/gesture_options.dart';

class _RecordingBridge implements MaplibreBridge {
  final List<({double scale, double x, double y})> scaleCalls =
      <({double scale, double x, double y})>[];
  final List<Offset> moveCalls = <Offset>[];
  final List<double> rotationCalls = <double>[];
  final List<double> pitchCalls = <double>[];
  int animatedScaleCalls = 0;

  @override
  void moveBy(double dx, double dy) => moveCalls.add(Offset(dx, dy));

  @override
  void scaleBy(double scale, double cx, double cy) {
    scaleCalls.add((scale: scale, x: cx, y: cy));
  }

  @override
  void rotateBy(double degrees) => rotationCalls.add(degrees);

  @override
  void pitchBy(double degrees) => pitchCalls.add(degrees);

  @override
  bool scaleByAnimated({
    required double amount,
    Offset? focus,
    required Duration duration,
    required int easing,
  }) {
    animatedScaleCalls++;

    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected ${invocation.memberName}');
}

class _FakeHost implements MapGestureHost {
  _FakeHost({this.bridge, MapGestureSettings? settings})
    : settings = settings ?? _allGesturesEnabled;

  static const MapGestureSettings _allGesturesEnabled = (
    scrollEnabled: true,
    zoomEnabled: true,
    rotateEnabled: true,
    tiltEnabled: true,
    doubleClickZoomEnabled: null,
  );

  MaplibreBridge? bridge;
  MapGestureSettings settings;
  final MapGestureOptions options = const MapGestureOptions();
  int beginCalls = 0;
  int endCalls = 0;
  int renderCalls = 0;
  int scheduleRepaintCalls = 0;

  @override
  MaplibreBridge? get gestureBridge => bridge;

  @override
  MapGestureSettings get gestureSettings => settings;

  @override
  MapGestureOptions get gestureOptions => options;

  @override
  Size get logicalMapSize => const Size(400, 300);

  @override
  void beginCameraGesture() => beginCalls++;

  @override
  void endCameraGesture() => endCalls++;

  @override
  void renderGesture() => renderCalls++;

  @override
  void scheduleRepaint() => scheduleRepaintCalls++;
}

void main() {
  testWidgets('coalesces wheel renders within one frame', (tester) async {
    final bridge = _RecordingBridge();
    final host = _FakeHost(bridge: bridge);
    final coordinator = MapGestureCoordinator(
      vsync: const TestVSync(),
      host: host,
    );
    addTearDown(coordinator.dispose);

    coordinator.onPointerSignal(
      const PointerScrollEvent(
        position: Offset(20, 30),
        scrollDelta: Offset(0, -1),
      ),
    );
    coordinator.onPointerSignal(
      const PointerScrollEvent(
        position: Offset(40, 50),
        scrollDelta: Offset(0, 1),
      ),
    );

    expect(bridge.scaleCalls, <({double scale, double x, double y})>[
      (scale: 1.03, x: 20, y: 30),
      (scale: 0.97, x: 40, y: 50),
    ]);
    expect(host.beginCalls, 2);
    expect(host.scheduleRepaintCalls, 2);
    expect(host.renderCalls, 0);

    await tester.pump();

    expect(host.renderCalls, 1);
  });

  testWidgets('drops scheduled wheel render when bridge becomes unavailable', (
    tester,
  ) async {
    final bridge = _RecordingBridge();
    final host = _FakeHost(bridge: bridge);
    final coordinator = MapGestureCoordinator(
      vsync: const TestVSync(),
      host: host,
    );
    addTearDown(coordinator.dispose);

    coordinator.onPointerSignal(
      const PointerScrollEvent(
        position: Offset(20, 30),
        scrollDelta: Offset(0, -1),
      ),
    );
    host.bridge = null;

    await tester.pump();

    expect(bridge.scaleCalls, hasLength(1));
    expect(host.renderCalls, 0);
  });

  testWidgets('suppresses touch scale while every input is disabled', (
    tester,
  ) async {
    final bridge = _RecordingBridge();
    final host = _FakeHost(
      bridge: bridge,
      settings: (
        scrollEnabled: false,
        zoomEnabled: false,
        rotateEnabled: false,
        tiltEnabled: false,
        doubleClickZoomEnabled: null,
      ),
    );
    final coordinator = MapGestureCoordinator(
      vsync: const TestVSync(),
      host: host,
    );
    addTearDown(coordinator.dispose);

    coordinator.onPointerDown(
      const PointerDownEvent(pointer: 1, position: Offset(10, 10)),
    );
    coordinator.onScaleStart(
      ScaleStartDetails(kind: PointerDeviceKind.touch, pointerCount: 1),
    );
    coordinator.onScaleUpdate(
      ScaleUpdateDetails(focalPointDelta: const Offset(8, 5), pointerCount: 1),
    );

    expect(coordinator.isScaleGestureActive, isFalse);
    expect(host.beginCalls, 0);
    expect(bridge.moveCalls, isEmpty);

    coordinator.onPointerEnd(
      const PointerUpEvent(pointer: 1, position: Offset(10, 10)),
    );
    host.settings = (
      scrollEnabled: true,
      zoomEnabled: false,
      rotateEnabled: false,
      tiltEnabled: false,
      doubleClickZoomEnabled: null,
    );
    coordinator.onScaleStart(
      ScaleStartDetails(kind: PointerDeviceKind.touch, pointerCount: 1),
    );
    coordinator.onScaleUpdate(
      ScaleUpdateDetails(focalPointDelta: const Offset(8, 5), pointerCount: 1),
    );

    expect(coordinator.isScaleGestureActive, isTrue);
    expect(host.beginCalls, 1);
    expect(bridge.moveCalls, <Offset>[const Offset(8, 5)]);

    coordinator.onScaleEnd(ScaleEndDetails(pointerCount: 1));
    await tester.pump();
  });

  testWidgets('applies incremental trackpad pan zoom and rotation', (
    tester,
  ) async {
    final bridge = _RecordingBridge();
    final host = _FakeHost(bridge: bridge);
    final coordinator = MapGestureCoordinator(
      vsync: const TestVSync(),
      host: host,
    );
    addTearDown(coordinator.dispose);

    coordinator.onScaleStart(
      ScaleStartDetails(kind: PointerDeviceKind.trackpad, pointerCount: 2),
    );
    coordinator.onScaleUpdate(
      ScaleUpdateDetails(
        localFocalPoint: const Offset(20, 30),
        focalPointDelta: const Offset(4, -3),
        scale: 1.2,
        rotation: math.pi / 4,
        pointerCount: 2,
      ),
    );
    coordinator.onScaleUpdate(
      ScaleUpdateDetails(
        localFocalPoint: const Offset(25, 35),
        scale: 1.8,
        rotation: math.pi / 2,
        pointerCount: 2,
      ),
    );

    expect(host.beginCalls, 1);
    expect(bridge.moveCalls, <Offset>[const Offset(4, -3)]);
    expect(bridge.scaleCalls, hasLength(2));
    expect(bridge.scaleCalls[0].scale, closeTo(1.2, 0.0001));
    expect(bridge.scaleCalls[1].scale, closeTo(1.5, 0.0001));
    expect(bridge.rotationCalls, hasLength(2));
    expect(bridge.rotationCalls[0], closeTo(-45, 0.0001));
    expect(bridge.rotationCalls[1], closeTo(-45, 0.0001));

    await tester.pump();
    coordinator.onScaleEnd(ScaleEndDetails(pointerCount: 2));

    expect(host.renderCalls, 2);
    expect(host.endCalls, 1);
  });

  testWidgets('applies macOS three-finger trackpad tilt', (tester) async {
    final bridge = _RecordingBridge();
    final host = _FakeHost(bridge: bridge);
    final coordinator = MapGestureCoordinator(
      vsync: const TestVSync(),
      host: host,
    );
    addTearDown(coordinator.dispose);

    coordinator.onMacosTrackpadTiltStart();
    coordinator.onMacosTrackpadTiltUpdate(8);
    coordinator.onMacosTrackpadTiltUpdate(-4);

    expect(host.beginCalls, 1);
    expect(bridge.pitchCalls, <double>[-4, 2]);

    await tester.pump();
    coordinator.onMacosTrackpadTiltEnd();

    expect(host.renderCalls, 2);
    expect(host.endCalls, 1);
  });

  testWidgets('applies Windows and Linux modifier mouse drags', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final bridge = _RecordingBridge();
    final host = _FakeHost(bridge: bridge);
    final coordinator = MapGestureCoordinator(
      vsync: const TestVSync(),
      host: host,
    );
    addTearDown(coordinator.dispose);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    coordinator.onPointerDown(
      const PointerDownEvent(
        pointer: 10,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
        position: Offset(20, 20),
      ),
    );
    coordinator.onPointerMove(
      const PointerMoveEvent(
        pointer: 10,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
        position: Offset(20, 28),
        delta: Offset(0, 8),
      ),
    );
    coordinator.onPointerEnd(
      const PointerUpEvent(
        pointer: 10,
        kind: PointerDeviceKind.mouse,
        position: Offset(20, 28),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    coordinator.onPointerDown(
      const PointerDownEvent(
        pointer: 11,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
        position: Offset(20, 20),
      ),
    );
    coordinator.onPointerMove(
      const PointerMoveEvent(
        pointer: 11,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
        position: Offset(28, 20),
        delta: Offset(8, 0),
      ),
    );
    coordinator.onPointerEnd(
      const PointerUpEvent(
        pointer: 11,
        kind: PointerDeviceKind.mouse,
        position: Offset(28, 20),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(bridge.pitchCalls, <double>[-4]);
    expect(bridge.rotationCalls, <double>[4]);
    expect(bridge.moveCalls, isEmpty);
    expect(host.beginCalls, 2);
    expect(host.endCalls, 2);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('dispose cancels pending tap zoom completion', (tester) async {
    final bridge = _RecordingBridge();
    final host = _FakeHost(bridge: bridge);
    final coordinator = MapGestureCoordinator(
      vsync: const TestVSync(),
      host: host,
    );

    coordinator.onDoubleTapDown(
      TapDownDetails(localPosition: const Offset(80, 90)),
    );
    coordinator.onDoubleTap();

    expect(bridge.animatedScaleCalls, 1);
    expect(host.beginCalls, 1);
    expect(host.scheduleRepaintCalls, 1);

    coordinator.dispose();
    await tester.pump(const Duration(seconds: 1));

    expect(host.renderCalls, 0);
    expect(host.endCalls, 0);
  });
}
