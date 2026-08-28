import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/state/map_render_scheduler.dart';

/// Drives the scheduler without a real clock or frame pipeline.
class _Harness {
  new({this.nativeWork = true}) {
    scheduler = MapRenderScheduler(
      isAlive: () => alive,
      hasPendingNativeWork: () {
        nativeWorkChecks++;

        return nativeWork;
      },
      render: () => renders++,
      createTimer: (duration, callback) {
        timerDurations.add(duration);
        _timerCallback = callback;

        return _FakeTimer(() => _timerCallback = null);
      },
      scheduleFrameCallback: (callback) {
        frameCallbacks.add(callback);
      },
    );
  }

  late final MapRenderScheduler scheduler;

  /// Stands in for the widget's `mounted && _initialized`.
  var alive = true;
  bool nativeWork;
  var renders = 0;
  var nativeWorkChecks = 0;
  final List<Duration> timerDurations = [];
  final List<void Function()> frameCallbacks = [];
  void Function()? _timerCallback;

  /// Fires the pending repaint timer, as the event loop would.
  void fireTimer() {
    final callback = _timerCallback;
    expect(callback, isNotNull, reason: 'no repaint timer was armed');
    _timerCallback = null;
    callback!();
  }

  /// Runs every queued frame callback, as the scheduler binding would.
  void pumpFrame() {
    final queued = List.of(frameCallbacks);
    frameCallbacks.clear();
    for (final callback in queued) {
      callback();
    }
  }
}

class _FakeTimer implements Timer {
  new(this._onCancel);

  final void Function() _onCancel;
  var _active = true;

  @override
  void cancel() {
    _active = false;
    _onCancel();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

void main() {
  group('repaint timer', () {
    test('arms once and renders when it fires', () {
      final h = _Harness();

      h.scheduler.scheduleRepaint(const Duration(milliseconds: 16));
      expect(h.scheduler.isRepaintPending, isTrue);
      h.fireTimer();

      expect(h.renders, 1);
      expect(h.scheduler.isRepaintPending, isFalse);
      expect(h.timerDurations, [const Duration(milliseconds: 16)]);
    });

    test('a second request while one is armed is ignored', () {
      // The caller re-decides the interval on every render; re-arming here
      // would stack timers and multiply the frame rate.
      final h = _Harness();

      h.scheduler.scheduleRepaint(const Duration(milliseconds: 150));
      h.scheduler.scheduleRepaint(const Duration(milliseconds: 16));

      expect(h.timerDurations, hasLength(1));
    });

    test('a timer that fires after the map went away renders nothing', () {
      final h = _Harness();
      h.scheduler.scheduleRepaint(const Duration(milliseconds: 16));

      h.alive = false;
      h.fireTimer();

      expect(h.renders, 0);
    });

    test('cancelling clears the pending state', () {
      final h = _Harness();
      h.scheduler.scheduleRepaint(const Duration(milliseconds: 16));

      h.scheduler.cancelRepaint();

      expect(h.scheduler.isRepaintPending, isFalse);
      h.scheduler.scheduleRepaint(const Duration(milliseconds: 16));
      expect(h.timerDurations, hasLength(2));
    });
  });

  group('native render requests', () {
    test('a burst collapses into one frame', () {
      final h = _Harness();

      h.scheduler.scheduleNativeRender();
      h.scheduler.scheduleNativeRender();
      h.scheduler.scheduleNativeRender();

      expect(h.frameCallbacks, hasLength(1));
      h.pumpFrame();
      expect(h.renders, 1);
    });

    test('a frame with no native work renders nothing', () {
      final h = _Harness(nativeWork: false);

      h.scheduler.scheduleNativeRender();
      h.pumpFrame();

      expect(h.renders, 0);
      expect(h.nativeWorkChecks, 1);
    });

    test('force renders without consulting native', () {
      // A resume or a style swap must repaint even when native believes
      // nothing changed, because the surface contents are gone.
      final h = _Harness(nativeWork: false);

      h.scheduler.scheduleNativeRender(force: true);
      h.pumpFrame();

      expect(h.renders, 1);
      expect(h.nativeWorkChecks, 0);
    });

    test('force survives being coalesced with unforced requests', () {
      final h = _Harness(nativeWork: false);

      h.scheduler.scheduleNativeRender(force: true);
      h.scheduler.scheduleNativeRender();

      h.pumpFrame();
      expect(h.renders, 1);
    });

    test('force does not leak into the next frame', () {
      final h = _Harness(nativeWork: false);
      h.scheduler.scheduleNativeRender(force: true);
      h.pumpFrame();

      h.scheduler.scheduleNativeRender();
      h.pumpFrame();

      expect(h.renders, 1);
    });

    test('a rendered frame cancels the repaint timer', () {
      // Otherwise the timer fires right behind the frame and renders twice.
      final h = _Harness();
      h.scheduler.scheduleRepaint(const Duration(milliseconds: 150));

      h.scheduler.scheduleNativeRender();
      h.pumpFrame();

      expect(h.renders, 1);
      expect(h.scheduler.isRepaintPending, isFalse);
    });

    test('a skipped frame leaves the repaint timer armed', () {
      final h = _Harness(nativeWork: false);
      h.scheduler.scheduleRepaint(const Duration(milliseconds: 150));

      h.scheduler.scheduleNativeRender();
      h.pumpFrame();

      expect(h.scheduler.isRepaintPending, isTrue);
    });

    test('a frame arriving after the map went away renders nothing', () {
      final h = _Harness();
      h.scheduler.scheduleNativeRender();

      h.alive = false;
      h.pumpFrame();

      expect(h.renders, 0);
    });

    test('the next request after a frame schedules again', () {
      final h = _Harness();
      h.scheduler.scheduleNativeRender();
      h.pumpFrame();

      h.scheduler.scheduleNativeRender();

      expect(h.frameCallbacks, hasLength(1));
    });
  });

  group('app lifecycle', () {
    test('backgrounding cancels the repaint timer', () {
      // A GPU submit against a surface the platform reclaimed is a crash, not
      // a wasted frame.
      final h = _Harness();
      h.scheduler.scheduleRepaint(const Duration(milliseconds: 16));

      expect(h.scheduler.setAppActive(false), isTrue);

      expect(h.scheduler.isRepaintPending, isFalse);
      expect(h.scheduler.isAppActive, isFalse);
    });

    test('a backgrounded scheduler queues no work at all', () {
      final h = _Harness()..scheduler.setAppActive(false);

      h.scheduler.scheduleNativeRender(force: true);
      h.scheduler.scheduleRepaint(const Duration(milliseconds: 16));

      expect(h.frameCallbacks, isEmpty);
      expect(h.scheduler.isRepaintPending, isFalse);
    });

    test('resuming replays the render that was skipped, forced', () {
      final h = _Harness(nativeWork: false)..scheduler.setAppActive(false);
      h.scheduler.scheduleNativeRender();

      h.scheduler.setAppActive(true);
      h.pumpFrame();

      expect(h.renders, 1);
    });

    test('a render deferred by the widget is replayed on resume', () {
      final h = _Harness(nativeWork: false);

      h.scheduler.setAppActive(false);
      h.scheduler.deferToResume();
      h.scheduler.setAppActive(true);
      h.pumpFrame();

      expect(h.renders, 1);
    });

    test('any backgrounding owes a render, even with no request pending', () {
      // Going away is itself the reason to repaint: the platform can discard
      // the surface while backgrounded, and native reports no new work for
      // pixels it still believes are on screen.
      final h = _Harness(nativeWork: false);

      h.scheduler.setAppActive(false);
      h.scheduler.setAppActive(true);
      h.pumpFrame();

      expect(h.renders, 1);
    });

    test('the debt is cleared by the resume that settles it', () {
      final h = _Harness(nativeWork: false)..scheduler.setAppActive(false);
      h.scheduler.setAppActive(true);
      h.pumpFrame();
      expect(h.renders, 1);

      // No second background, so nothing is owed: a request now goes through
      // the ordinary native-work check instead of being forced.
      h.scheduler.scheduleNativeRender();
      h.pumpFrame();

      expect(h.renders, 1);
    });

    test('a repeated state is not a transition', () {
      final h = _Harness();
      expect(h.scheduler.setAppActive(true), isFalse);
    });

    test('an unmounted map does not render on resume', () {
      final h = _Harness()..scheduler.setAppActive(false);
      h.scheduler.deferToResume();

      h.alive = false;
      h.scheduler.setAppActive(true);

      expect(h.frameCallbacks, isEmpty);
    });
  });

  test('dispose cancels queued work and rejects future requests', () {
    final h = _Harness();
    h.scheduler.scheduleRepaint(const Duration(milliseconds: 16));
    h.scheduler.scheduleNativeRender(force: true);

    h.scheduler.dispose();
    h.scheduler.dispose();
    h.scheduler.scheduleRepaint(const Duration(milliseconds: 16));
    h.scheduler.scheduleNativeRender(force: true);
    h.scheduler.deferToResume();
    expect(h.scheduler.setAppActive(false), isFalse);
    h.pumpFrame();

    expect(h.scheduler.isRepaintPending, isFalse);
    expect(h.timerDurations, hasLength(1));
    expect(h.renders, 0);
    expect(h.nativeWorkChecks, 0);
  });
}
