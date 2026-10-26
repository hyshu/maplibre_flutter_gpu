import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/widgets/map/map_render_pause_transition.dart';

Future<void> _nextTurn() => Future<void>.delayed(Duration.zero);

class _NativeRequest {
  _NativeRequest(this.paused);

  final bool paused;
  final result = Completer<bool>();
}

class _Harness {
  final events = <String>[];
  final requests = <_NativeRequest>[];
  Completer<void>? releaseBarrier;
  Object? prepareError;
  var alive = true;
  var displayPaused = false;

  late final transition = MapRenderPauseTransition(
    isAlive: () => alive,
    pauseDisplay: () {
      events.add('pause display');
      displayPaused = true;
    },
    prepareResume: () {
      events.add('prepare resume');
      if (prepareError case final error?) throw error;
    },
    resumeDisplay: () {
      events.add('resume display');
      displayPaused = false;
    },
    releaseFrame: () {
      events.add('release frame');

      return releaseBarrier?.future ?? Future<void>.value();
    },
    setNativePaused: (paused) {
      events.add('native $paused');
      final request = _NativeRequest(paused);
      requests.add(request);

      return request.result.future;
    },
  );
}

void main() {
  test(
    'pause closes admission before releasing the frame without blocking',
    () async {
      final harness = _Harness()..releaseBarrier = Completer<void>();
      var completed = false;
      final pause = harness.transition.setPaused(true)
        ..then((_) => completed = true);
      expect(harness.displayPaused, isTrue);
      expect(harness.events, ['pause display', 'native true', 'release frame']);

      var heartbeat = false;
      Timer.run(() => heartbeat = true);
      await _nextTurn();
      expect(heartbeat, isTrue);
      expect(completed, isFalse);
      harness.requests.single.result.complete(true);
      await _nextTurn();
      expect(completed, isFalse);
      harness.releaseBarrier!.complete();
      await pause;
      expect(completed, isTrue);
      expect(harness.displayPaused, isTrue);
      expect(harness.transition.dispose(), isNull);
    },
  );

  test(
    'resume waits for the native owner before applying the camera and drawing',
    () async {
      final harness = _Harness()..displayPaused = true;
      var completed = false;
      final resume = harness.transition.setPaused(false)
        ..then((_) => completed = true);
      await _nextTurn();
      expect(harness.events, ['release frame', 'native false']);
      expect(harness.displayPaused, isTrue);
      expect(completed, isFalse);

      harness.requests.single.result.complete(true);
      await resume;
      expect(harness.events, [
        'release frame',
        'native false',
        'prepare resume',
        'resume display',
      ]);
      expect(harness.displayPaused, isFalse);
      harness.transition.dispose();
    },
  );

  test(
    'out-of-order pause and resume results cannot reopen the latest pause',
    () async {
      final harness = _Harness();
      final first = harness.transition.setPaused(true);
      final second = harness.transition.setPaused(false);
      await _nextTurn();
      final third = harness.transition.setPaused(true);
      expect(harness.requests.map((request) => request.paused), [
        true,
        false,
        true,
      ]);

      harness.requests[2].result.complete(true);
      await third;
      harness.requests[1].result.complete(false);
      harness.requests[0].result.complete(false);
      await Future.wait([first, second]);
      expect(harness.displayPaused, isTrue);
      expect(harness.events, isNot(contains('resume display')));
      expect(harness.events, isNot(contains('prepare resume')));
      harness.transition.dispose();
    },
  );

  test(
    'a newer pause prevents a resume waiting on a frame lease from dispatching',
    () async {
      final harness = _Harness()..releaseBarrier = Completer<void>();
      final resume = harness.transition.setPaused(false);
      final pause = harness.transition.setPaused(true);
      expect(harness.requests.map((request) => request.paused), [true]);

      harness.releaseBarrier!.complete();
      harness.requests.single.result.complete(true);
      await Future.wait([resume, pause]);
      expect(harness.requests.map((request) => request.paused), [true]);
      expect(harness.displayPaused, isTrue);
      harness.transition.dispose();
    },
  );

  test('an earlier failure cannot roll back a newer pause', () async {
    final harness = _Harness();
    final first = expectLater(
      harness.transition.setPaused(true),
      throwsStateError,
    );
    final second = harness.transition.setPaused(true);
    harness.requests[0].result.completeError(StateError('old request failed'));
    harness.requests[1].result.complete(true);
    await Future.wait([first, second]);
    expect(harness.requests.map((request) => request.paused), [true, true]);
    expect(harness.displayPaused, isTrue);
    harness.transition.dispose();
  });

  test('a rejected pause restores the display and reports failure', () async {
    final harness = _Harness();
    final pause = expectLater(
      harness.transition.setPaused(true),
      throwsStateError,
    );
    harness.requests.single.result.complete(false);
    await pause;
    expect(harness.displayPaused, isFalse);
    expect(harness.events.last, 'resume display');
    harness.transition.dispose();
  });

  test(
    'a lease release failure waits for async native recovery before drawing',
    () async {
      final harness = _Harness()..releaseBarrier = Completer<void>();
      final pause = expectLater(
        harness.transition.setPaused(true),
        throwsStateError,
      );
      harness.releaseBarrier!.completeError(StateError('lease release failed'));
      harness.requests.single.result.complete(true);
      await _nextTurn();
      expect(harness.requests.map((request) => request.paused), [true, false]);
      expect(harness.displayPaused, isTrue);

      harness.requests.last.result.complete(true);
      await pause;
      expect(harness.displayPaused, isFalse);
      harness.transition.dispose();
    },
  );

  test(
    'a failed resume preparation restores the native pause asynchronously',
    () async {
      final harness = _Harness()
        ..displayPaused = true
        ..prepareError = StateError('camera update failed');
      final resume = expectLater(
        harness.transition.setPaused(false),
        throwsStateError,
      );
      await _nextTurn();
      harness.requests.single.result.complete(true);
      await _nextTurn();
      expect(harness.requests.map((request) => request.paused), [false, true]);
      expect(harness.displayPaused, isTrue);

      harness.requests.last.result.complete(true);
      await resume;
      expect(harness.events, isNot(contains('resume display')));
      harness.transition.dispose();
    },
  );

  test('a new request invalidates an in-flight rollback', () async {
    final harness = _Harness()..releaseBarrier = Completer<void>();
    final first = harness.transition.setPaused(true);
    harness.releaseBarrier!.completeError(StateError('lease release failed'));
    harness.requests.single.result.complete(true);
    await _nextTurn();
    expect(harness.requests.map((request) => request.paused), [true, false]);
    harness.releaseBarrier = null;
    final latest = harness.transition.setPaused(true);
    harness.requests[1].result.complete(false);
    harness.requests[2].result.complete(true);
    await Future.wait([first, latest]);
    expect(harness.displayPaused, isTrue);
    expect(harness.events, isNot(contains('resume display')));
    harness.transition.dispose();
  });

  test(
    'dispose completes callers immediately and drains every native callback',
    () async {
      final harness = _Harness();
      final first = harness.transition.setPaused(true);
      final second = harness.transition.setPaused(false);
      await _nextTurn();
      final third = harness.transition.setPaused(true);
      final eventsBeforeDispose = [...harness.events];

      final barrier = harness.transition.dispose();
      expect(barrier, isNotNull);
      var cleanedUp = false;
      final cleanup = barrier!.then((_) => cleanedUp = true);
      await Future.wait([first, second, third]);
      await harness.transition.setPaused(false);
      expect(cleanedUp, isFalse);

      harness.requests[2].result.complete(true);
      harness.requests[0].result.completeError(StateError('owner was stopped'));
      await _nextTurn();
      expect(cleanedUp, isFalse);
      harness.requests[1].result.complete(false);
      await cleanup;
      expect(cleanedUp, isTrue);
      expect(harness.events, eventsBeforeDispose);
    },
  );

  test('dispose prevents dispatch after a pending lease release', () async {
    final harness = _Harness()..releaseBarrier = Completer<void>();
    final resume = harness.transition.setPaused(false);
    expect(harness.transition.dispose(), isNull);
    await resume;
    harness.releaseBarrier!.complete();
    await _nextTurn();
    expect(harness.requests, isEmpty);
    expect(harness.events, ['release frame']);
  });
}
