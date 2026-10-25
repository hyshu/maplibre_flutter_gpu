import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'support/controller_fixtures.dart';

void main() {
  test(
    'reports requests immediately and shares the pending pause barrier',
    () async {
      final barrier = Completer<void>();
      final calls = <bool>[];
      final bridge = FakeControllerBridge();
      final controller = MapLibreMapController.bind(
        bridge,
        onRenderingPausedChanged: (paused) {
          calls.add(paused);

          return barrier.future;
        },
      );
      addTearDown(controller.dispose);
      expect(controller.isRenderingPaused, isFalse);
      var completed = 0;
      final first = controller.setRenderingPaused(paused: true)
        ..then((_) => completed++);
      final duplicate = controller.setRenderingPaused(paused: true)
        ..then((_) => completed++);
      expect(controller.isRenderingPaused, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(completed, 0);
      expect(calls, [true]);
      expect(bridge.cancelCount, 0);

      barrier.complete();
      await Future.wait([first, duplicate]);
      expect(completed, 2);
    },
  );

  test('latest request wins even when callbacks finish out of order', () async {
    final barriers = <Completer<void>>[];
    final requests = <bool>[];
    final controller = MapLibreMapController.bind(
      FakeControllerBridge(),
      onRenderingPausedChanged: (paused) {
        requests.add(paused);
        final barrier = Completer<void>();
        barriers.add(barrier);

        return barrier.future;
      },
    );
    addTearDown(controller.dispose);
    final first = controller.setRenderingPaused(paused: true);
    final second = controller.setRenderingPaused(paused: false);
    final third = controller.setRenderingPaused(paused: true);
    expect(requests, [true, false, true]);
    barriers[2].complete();
    barriers[0].complete();
    barriers[1].complete();
    await Future.wait([first, second, third]);
    expect(controller.isRenderingPaused, isTrue);
  });

  test('failed pause leaves the previous requested state available', () async {
    var fail = true;
    final controller = MapLibreMapController.bind(
      FakeControllerBridge(),
      onRenderingPausedChanged: (_) async {
        if (fail) throw UnsupportedError('unsupported native runtime');
      },
    );
    addTearDown(controller.dispose);
    await expectLater(
      controller.setRenderingPaused(paused: true),
      throwsUnsupportedError,
    );
    expect(controller.isRenderingPaused, isFalse);
    fail = false;
    await controller.setRenderingPaused(paused: true);
    expect(controller.isRenderingPaused, isTrue);
  });

  test(
    'a rejected paint-time request does not mutate the native camera',
    () async {
      final bridge = FakeControllerBridge();
      final controller = MapLibreMapController.bind(
        bridge,
        onRenderingPausedChanged: (_) {
          throw StateError('Rendering state cannot change during GPU paint');
        },
      );
      addTearDown(controller.dispose);
      await expectLater(
        controller.setRenderingPaused(paused: true),
        throwsStateError,
      );
      expect(controller.isRenderingPaused, isFalse);
      expect(bridge.cancelCount, 0);
    },
  );

  test('an earlier failure cannot overwrite the latest request', () async {
    final firstBarrier = Completer<void>();
    final controller = MapLibreMapController.bind(
      FakeControllerBridge(),
      onRenderingPausedChanged: (paused) =>
          paused ? firstBarrier.future : Future<void>.value(),
    );
    addTearDown(controller.dispose);
    final first = expectLater(
      controller.setRenderingPaused(paused: true),
      throwsStateError,
    );
    await controller.setRenderingPaused(paused: false);
    firstBarrier.completeError(StateError('old pause failed'));
    await first;
    expect(controller.isRenderingPaused, isFalse);
  });

  test(
    'disposal completes pending requests and rejects later access',
    () async {
      final barrier = Completer<void>();
      final controller = MapLibreMapController.bind(
        FakeControllerBridge(),
        onRenderingPausedChanged: (_) => barrier.future,
      );
      final pending = controller.setRenderingPaused(paused: true);
      final duplicate = controller.setRenderingPaused(paused: true);
      controller.dispose();
      await Future.wait([pending, duplicate]);
      expect(() => controller.isRenderingPaused, throwsStateError);
      await expectLater(
        controller.setRenderingPaused(paused: false),
        throwsStateError,
      );
      barrier.complete();
      controller.dispose();
    },
  );

  test(
    'unbound controllers reject rendering control without a false state',
    () async {
      final controller = MapLibreMapController.bind(FakeControllerBridge());
      addTearDown(controller.dispose);
      await expectLater(
        controller.setRenderingPaused(paused: true),
        throwsStateError,
      );
      expect(controller.isRenderingPaused, isFalse);
    },
  );

  test('paused maps accept immediate updates and reject animations', () async {
    final bridge = FakeControllerBridge();
    final controller = MapLibreMapController.bind(
      bridge,
      onRenderingPausedChanged: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.setRenderingPaused(paused: true);
    expect(await controller.moveCamera(CameraUpdate.zoomTo(16)), isTrue);
    await controller.updateContentInsets(const EdgeInsets.all(12));
    await controller.setLayerVisibility('roads', false);
    expect(bridge.zoom, 16);
    expect(bridge.lastContentInsets, const EdgeInsets.all(12));
    expect(bridge.layerVisibility['roads'], isFalse);
    final callCount = bridge.callCount;
    expect(await controller.animateCamera(CameraUpdate.zoomTo(20)), isFalse);
    expect(
      await controller.easeCamera(
        CameraUpdate.zoomTo(20),
        duration: Duration.zero,
      ),
      isFalse,
    );
    await controller.updateContentInsets(const EdgeInsets.all(20), true);
    await controller.setCameraBounds(
      west: 138,
      north: 36,
      south: 34,
      east: 140,
      padding: 10,
    );
    expect(bridge.callCount, callCount);

    await controller.setRenderingPaused(paused: false);
    expect(
      await controller.animateCamera(
        CameraUpdate.zoomTo(20),
        duration: Duration.zero,
      ),
      isTrue,
    );
    expect(bridge.zoom, 20);
  });

  test('pausing interrupts a pending camera animation', () async {
    final barrier = Completer<void>();
    final bridge = FakeControllerBridge();
    final controller = MapLibreMapController.bind(
      bridge,
      beforeCameraMutation: () => barrier.future,
      onRenderingPausedChanged: (_) async {},
    );
    addTearDown(controller.dispose);
    final animation = controller.animateCamera(CameraUpdate.zoomTo(20));
    await controller.setRenderingPaused(paused: true);
    barrier.complete();
    expect(await animation, isFalse);
    expect(bridge.zoom, 12);
    expect(bridge.cancelCount, 0);
  });

  test(
    'pausing completes an active transition with an interrupted result',
    () async {
      final bridge = FakeControllerBridge();
      final controller = MapLibreMapController.bind(
        bridge,
        onRenderingPausedChanged: (_) async {},
      );
      addTearDown(controller.dispose);
      final animation = controller.easeCamera(
        CameraUpdate.zoomTo(20),
        duration: const Duration(seconds: 5),
      );
      await Future<void>.delayed(Duration.zero);
      await controller.setRenderingPaused(paused: true);
      expect(await animation, isFalse);
      expect(bridge.cancelCount, 0);
    },
  );
}
