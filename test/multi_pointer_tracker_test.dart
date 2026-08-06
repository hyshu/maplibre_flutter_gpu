import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/state/gesture/multi_pointer_tracker.dart';

extension on MultiPointerTracker {
  MultiPointerCameraUpdate? evaluateAll({
    bool zoom = true,
    bool rotate = true,
    bool tilt = true,
  }) => evaluate(zoomEnabled: zoom, rotateEnabled: rotate, tiltEnabled: tilt);

  /// Places two fingers [gap] apart, horizontally, centred on (100, 100).
  void twoFingersDown({double gap = 100}) {
    down(1, Offset(100 - gap / 2, 100));
    down(2, Offset(100 + gap / 2, 100));
  }

  void twoFingersAt(Offset a, Offset b) {
    move(1, a);
    move(2, b);
  }
}

void main() {
  group('gesture commitment', () {
    test('a two-finger gesture below every threshold moves nothing', () {
      // A two-finger tap always jitters by a pixel or two. Acting on it would
      // zoom the map on what the user meant as a tap.
      final tracker = MultiPointerTracker()..twoFingersDown();

      tracker.twoFingersAt(const Offset(51, 100), const Offset(151, 101));

      expect(tracker.evaluateAll(), isNull);
      expect(tracker.mode, TwoFingerGestureMode.undecided);
    });

    test('a pinch past the threshold commits and reports a scale', () {
      final tracker = MultiPointerTracker()..twoFingersDown();

      tracker.twoFingersAt(const Offset(40, 100), const Offset(160, 100));
      final update = tracker.evaluateAll();

      expect(tracker.mode, TwoFingerGestureMode.transform);
      expect(update?.scale, closeTo(120 / 100, 1e-9));
      expect(update?.scaleFocus, const Offset(100, 100));
    });

    test('a rotation past 3 degrees commits without any pinch', () {
      final tracker = MultiPointerTracker()..twoFingersDown();
      final radius = 50.0;
      const angle = math.pi / 30; // 6°, distance unchanged.

      tracker.twoFingersAt(
        Offset(100 - radius * math.cos(angle), 100 - radius * math.sin(angle)),
        Offset(100 + radius * math.cos(angle), 100 + radius * math.sin(angle)),
      );
      final update = tracker.evaluateAll();

      expect(tracker.mode, TwoFingerGestureMode.transform);
      expect(update?.rotationDelta, closeTo(angle, 1e-9));
      expect(update?.scale, isNull);
    });

    test('a two-finger pan past the threshold commits', () {
      // Fingers keeping their spacing and angle still mean "move the map".
      final tracker = MultiPointerTracker()..twoFingersDown();

      tracker.twoFingersAt(const Offset(60, 100), const Offset(160, 100));
      tracker.evaluateAll();

      expect(tracker.mode, TwoFingerGestureMode.transform);
    });

    test('a committed gesture stays committed after returning to start', () {
      final tracker = MultiPointerTracker()..twoFingersDown();
      tracker.twoFingersAt(const Offset(40, 100), const Offset(160, 100));
      tracker.evaluateAll();

      tracker.twoFingersAt(const Offset(50, 100), const Offset(150, 100));
      final update = tracker.evaluateAll();

      expect(tracker.mode, TwoFingerGestureMode.transform);
      expect(update?.scale, closeTo(100 / 120, 1e-9));
    });
  });

  group('per-frame deltas', () {
    test('scale is measured against the previous frame, not the start', () {
      // Against the start, every frame of a slow pinch would re-apply the whole
      // zoom and the map would run away.
      final tracker = MultiPointerTracker()..twoFingersDown();
      tracker.twoFingersAt(const Offset(40, 100), const Offset(160, 100));
      tracker.evaluateAll();

      tracker.twoFingersAt(const Offset(20, 100), const Offset(180, 100));
      final update = tracker.evaluateAll();

      expect(update?.scale, closeTo(160 / 120, 1e-9));
    });

    test('a frame with no movement reports nothing', () {
      final tracker = MultiPointerTracker()..twoFingersDown();
      tracker.twoFingersAt(const Offset(40, 100), const Offset(160, 100));
      tracker.evaluateAll();

      expect(tracker.evaluateAll(), isNull);
    });

    test('rotation across the ±pi seam stays a small delta', () {
      // The raw angles are near +pi and -pi; a plain subtraction would report
      // almost a full turn and spin the map.
      final tracker = MultiPointerTracker()..twoFingersDown();
      const epsilon = 0.02;

      tracker.twoFingersAt(
        Offset(100 + 50 * math.cos(epsilon), 100 + 50 * math.sin(epsilon)),
        Offset(100 - 50 * math.cos(epsilon), 100 - 50 * math.sin(epsilon)),
      );
      tracker.evaluateAll();
      tracker.twoFingersAt(
        Offset(100 + 50 * math.cos(-epsilon), 100 + 50 * math.sin(-epsilon)),
        Offset(100 - 50 * math.cos(-epsilon), 100 - 50 * math.sin(-epsilon)),
      );
      final update = tracker.evaluateAll();

      expect(update?.rotationDelta, closeTo(-2 * epsilon, 1e-9));
    });
  });

  group('disabled gestures', () {
    test('a pinch with zoom disabled neither commits nor scales', () {
      final tracker = MultiPointerTracker()..twoFingersDown();

      tracker.twoFingersAt(const Offset(40, 100), const Offset(160, 100));
      final update = tracker.evaluateAll(zoom: false);

      // The fingers moved 10px apart symmetrically, so the centre did not
      // move: no pan threshold is cleared either.
      expect(tracker.mode, TwoFingerGestureMode.undecided);
      expect(update, isNull);
    });

    test('a committed gesture with zoom disabled still rotates', () {
      final tracker = MultiPointerTracker()..twoFingersDown();
      tracker.twoFingersAt(const Offset(40, 110), const Offset(160, 110));
      tracker.evaluateAll(zoom: false);
      expect(tracker.mode, TwoFingerGestureMode.transform);

      tracker.twoFingersAt(const Offset(40, 100), const Offset(160, 120));
      final update = tracker.evaluateAll(zoom: false);

      expect(update?.scale, isNull);
      expect(update?.rotationDelta, isNotNull);
    });

    test('rotation disabled leaves the pinch working', () {
      final tracker = MultiPointerTracker()..twoFingersDown();

      tracker.twoFingersAt(const Offset(40, 100), const Offset(160, 105));
      final update = tracker.evaluateAll(rotate: false);

      expect(update?.scale, isNotNull);
      expect(update?.rotationDelta, isNull);
    });
  });

  group('three fingers', () {
    test('three fingers down mean tilt immediately, with no threshold', () {
      final tracker = MultiPointerTracker()
        ..down(1, const Offset(100, 100))
        ..down(2, const Offset(200, 100))
        ..down(3, const Offset(300, 100));

      expect(tracker.mode, TwoFingerGestureMode.tilt);
    });

    test('a vertical three-finger drag reports a tilt', () {
      final tracker = MultiPointerTracker()
        ..down(1, const Offset(100, 100))
        ..down(2, const Offset(200, 100))
        ..down(3, const Offset(300, 100))
        ..move(1, const Offset(100, 80))
        ..move(2, const Offset(200, 80))
        ..move(3, const Offset(300, 80));

      final update = tracker.evaluateAll();

      expect(update?.tiltDelta, isNotNull);
      expect(update?.scale, isNull);
    });

    test('tilt disabled reports nothing but still advances the baseline', () {
      // Without the baseline advance, re-enabling tilt mid-gesture would
      // apply everything the fingers did while it was off, in one jump.
      final tracker = MultiPointerTracker()
        ..down(1, const Offset(100, 100))
        ..down(2, const Offset(200, 100))
        ..down(3, const Offset(300, 100))
        ..move(1, const Offset(100, 80))
        ..move(2, const Offset(200, 80))
        ..move(3, const Offset(300, 80));

      expect(tracker.evaluateAll(tilt: false), isNull);

      tracker
        ..move(1, const Offset(100, 78))
        ..move(2, const Offset(200, 78))
        ..move(3, const Offset(300, 78));
      final resumed = tracker.evaluateAll();
      final direct =
          (MultiPointerTracker()
                ..down(1, const Offset(100, 80))
                ..down(2, const Offset(200, 80))
                ..down(3, const Offset(300, 80))
                ..move(1, const Offset(100, 78))
                ..move(2, const Offset(200, 78))
                ..move(3, const Offset(300, 78)))
              .evaluateAll();

      expect(resumed?.tiltDelta, direct?.tiltDelta);
    });
  });

  group('pointer set changes', () {
    test('lifting a fourth pointer restarts tilt with the remaining three', () {
      final tracker = MultiPointerTracker()
        ..down(1, const Offset(100, 100))
        ..down(2, const Offset(200, 100))
        ..down(3, const Offset(300, 100))
        ..down(4, const Offset(400, 100));

      tracker.up(4);
      tracker
        ..move(1, const Offset(100, 80))
        ..move(2, const Offset(200, 80))
        ..move(3, const Offset(300, 80));

      expect(tracker.mode, TwoFingerGestureMode.tilt);
      expect(tracker.evaluateAll()?.tiltDelta, isNotNull);
    });

    test('lifting to two fingers restarts from the remaining pair', () {
      // Keeping the three-finger baseline would make the first two-finger
      // frame report the gap that the lifted finger used to span.
      final tracker = MultiPointerTracker()
        ..down(1, const Offset(100, 100))
        ..down(2, const Offset(200, 100))
        ..down(3, const Offset(300, 100));

      tracker.up(3);

      expect(tracker.mode, TwoFingerGestureMode.undecided);
      expect(tracker.pointerCount, 2);
      // No movement since the restart, so no camera change.
      expect(tracker.evaluateAll(), isNull);
    });

    test('dropping to one finger clears the gesture entirely', () {
      final tracker = MultiPointerTracker()..twoFingersDown();
      tracker.twoFingersAt(const Offset(40, 100), const Offset(160, 100));
      tracker.evaluateAll();

      tracker.up(2);

      expect(tracker.isMultiPointer, isFalse);
      expect(tracker.mode, TwoFingerGestureMode.undecided);
      expect(tracker.evaluateAll(), isNull);
    });

    test('a pointer set that no longer matches its baseline is ignored', () {
      // Pointer 3 arrives without a matching baseline entry; evaluating would
      // dereference a start position that does not exist.
      final tracker = MultiPointerTracker()..twoFingersDown();
      tracker.move(3, const Offset(300, 300));

      expect(tracker.pointerCount, 3);
      expect(tracker.evaluateAll(), isNull);
    });

    test('one finger alone reports nothing', () {
      final tracker = MultiPointerTracker()..down(1, const Offset(100, 100));

      expect(tracker.isMultiPointer, isFalse);
      expect(tracker.evaluateAll(), isNull);
    });
  });

  group('normalizedAngleDelta', () {
    test('reports the short way around the circle', () {
      expect(normalizedAngleDelta(0.1, -0.1), closeTo(0.2, 1e-12));
      expect(
        normalizedAngleDelta(-math.pi + 0.1, math.pi - 0.1),
        closeTo(0.2, 1e-12),
      );
      expect(
        normalizedAngleDelta(math.pi - 0.1, -math.pi + 0.1),
        closeTo(-0.2, 1e-12),
      );
    });
  });
}
