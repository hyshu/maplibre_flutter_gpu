import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/geo/camera.dart';
import 'package:maplibre_flutter_gpu/src/state/external_camera.dart';

class _Harness {
  new() {
    camera = ExternalCamera(
      canApply: () => ready,
      beforeApply: () {
        barrierCalls++;

        return barrier();
      },
      apply: (position) {
        onApply?.call(position);
        applied.add(position);
      },
      schedule: callbacks.add,
      onError: (error, stackTrace) => errors.add(error),
    );
  }

  late final ExternalCamera camera;
  var ready = true;
  var barrierCalls = 0;
  Future<void> Function() barrier = () => Future<void>.value();
  void Function(CameraPosition position)? onApply;
  final callbacks = <void Function()>[];
  final applied = <CameraPosition>[];
  final errors = <Object>[];

  Future<void> pumpFrame() async {
    final queued = List.of(callbacks);
    callbacks.clear();
    for (final callback in queued) {
      callback();
    }
    await settle();
  }

  Future<void> settle() => Future<void>.value();
}

void main() {
  const first = CameraPosition(target: LatLng(35, 139), zoom: 8);
  const second = CameraPosition(target: LatLng(36, 140), zoom: 10);
  const latest = CameraPosition(target: LatLng(37, 141), zoom: 12, bearing: 90);

  test(
    'a burst applies only the newest camera in one scheduled frame',
    () async {
      final h = _Harness();
      h.camera
        ..update(first)
        ..update(second)
        ..update(latest);

      expect(h.callbacks, hasLength(1));
      await h.pumpFrame();

      expect(h.applied, [latest]);
      expect(h.barrierCalls, 1);
      expect(h.callbacks, isEmpty);
    },
  );

  test(
    'new inputs replace the camera while a native frame is leased',
    () async {
      final h = _Harness();
      final release = Completer<void>();
      h.barrier = () => release.future;
      h.camera.update(first);
      await h.pumpFrame();

      expect(h.barrierCalls, 1);
      expect(h.applied, isEmpty);
      h.camera
        ..update(second)
        ..update(latest);
      expect(h.callbacks, isEmpty);

      release.complete();
      await h.settle();

      expect(h.applied, [latest]);
      expect(h.barrierCalls, 1);
      expect(h.callbacks, isEmpty);
    },
  );

  test(
    'a camera received before initialization is retained for reapply',
    () async {
      final h = _Harness()..ready = false;
      h.camera.update(first);
      await h.pumpFrame();

      expect(h.applied, isEmpty);
      expect(h.barrierCalls, 0);
      expect(h.callbacks, isEmpty);

      h.ready = true;
      h.camera.reapply();
      await h.pumpFrame();

      expect(h.applied, [first]);
    },
  );

  test('readiness lost during the lease barrier preserves the input', () async {
    final h = _Harness();
    final release = Completer<void>();
    h.barrier = () => release.future;
    h.camera.update(first);
    await h.pumpFrame();

    h.ready = false;
    release.complete();
    await h.settle();
    expect(h.applied, isEmpty);
    expect(h.callbacks, isEmpty);

    h.ready = true;
    h.camera.reapply();
    await h.pumpFrame();

    expect(h.applied, [first]);
  });

  test(
    'initialization can consume the retained camera without replay',
    () async {
      final h = _Harness();
      h.camera
        ..update(first)
        ..markApplied(first);
      await h.pumpFrame();

      expect(h.applied, isEmpty);
      expect(h.barrierCalls, 0);

      h.camera.reapply();
      await h.pumpFrame();

      expect(h.applied, [first]);
    },
  );

  test('null releases ownership before a pending frame runs', () async {
    final h = _Harness();
    h.camera
      ..update(first)
      ..update(null)
      ..reapply();
    await h.pumpFrame();

    expect(h.applied, isEmpty);
    expect(h.barrierCalls, 0);
    expect(h.callbacks, isEmpty);
  });

  test(
    'null cancels mutation after an outstanding lease is released',
    () async {
      final h = _Harness();
      final release = Completer<void>();
      h.barrier = () => release.future;
      h.camera.update(first);
      await h.pumpFrame();

      h.camera.update(null);
      release.complete();
      await h.settle();

      expect(h.applied, isEmpty);
      expect(h.callbacks, isEmpty);

      h.camera.update(second);
      await h.pumpFrame();
      expect(h.applied, [second]);
    },
  );

  test('disposal cancels leased input and rejects later updates', () async {
    final h = _Harness();
    final release = Completer<void>();
    h.barrier = () => release.future;
    h.camera.update(first);
    await h.pumpFrame();

    h.camera
      ..dispose()
      ..update(second)
      ..reapply()
      ..dispose();
    release.complete();
    await h.settle();

    expect(h.applied, isEmpty);
    expect(h.callbacks, isEmpty);
    expect(h.errors, isEmpty);
    expect(h.barrierCalls, 1);
  });

  test(
    'reapply resends an unchanged camera after style or lifecycle changes',
    () async {
      final h = _Harness();
      h.camera.update(first);
      await h.pumpFrame();

      h.camera.update(first);
      expect(h.callbacks, isEmpty);
      h.camera
        ..reapply()
        ..reapply();
      expect(h.callbacks, hasLength(1));
      await h.pumpFrame();

      expect(h.applied, [first, first]);
      expect(h.callbacks, isEmpty);
    },
  );

  test('a barrier failure reports once and a later request recovers', () async {
    final h = _Harness();
    final failure = StateError('Native lease release failed');
    h.barrier = () => Future<void>.error(failure);
    h.camera.update(first);
    await h.pumpFrame();

    expect(h.errors, [failure]);
    expect(h.applied, isEmpty);
    expect(h.callbacks, isEmpty);
    await h.pumpFrame();
    expect(h.barrierCalls, 1);

    h.barrier = () => Future<void>.value();
    h.camera.update(second);
    await h.pumpFrame();

    expect(h.applied, [second]);
    expect(h.errors, [failure]);
    expect(h.callbacks, isEmpty);
  });

  test('a native mutation failure can be retried explicitly', () async {
    final h = _Harness();
    final failure = StateError('Native camera update failed');
    h.onApply = (_) => throw failure;
    h.camera.update(first);
    await h.pumpFrame();

    expect(h.errors, [failure]);
    expect(h.applied, isEmpty);
    expect(h.callbacks, isEmpty);

    h.onApply = null;
    h.camera.reapply();
    await h.pumpFrame();

    expect(h.applied, [first]);
    expect(h.errors, [failure]);
  });

  test(
    'a newer camera survives failure of the previous lease barrier',
    () async {
      final h = _Harness();
      final release = Completer<void>();
      final failure = StateError('Native lease release failed');
      h.barrier = () => release.future;
      h.camera.update(first);
      await h.pumpFrame();

      h.camera.update(latest);
      release.completeError(failure);
      await h.settle();

      expect(h.errors, [failure]);
      expect(h.applied, isEmpty);
      expect(h.callbacks, hasLength(1));

      h.barrier = () => Future<void>.value();
      await h.pumpFrame();

      expect(h.applied, [latest]);
      expect(h.errors, [failure]);
      expect(h.callbacks, isEmpty);
    },
  );

  test(
    'an input received during native mutation schedules its own frame',
    () async {
      final h = _Harness();
      h.onApply = (position) {
        if (position == first) {
          h.camera
            ..update(second)
            ..update(latest);
        }
      };
      h.camera.update(first);
      await h.pumpFrame();

      expect(h.applied, [first]);
      expect(h.callbacks, hasLength(1));
      await h.pumpFrame();

      expect(h.applied, [first, latest]);
      expect(h.callbacks, isEmpty);
    },
  );
}
