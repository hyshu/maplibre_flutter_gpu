import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/state/gesture/pan_fling_tracker.dart';

final _t0 = DateTime.utc(2020);

DateTime _at(int milliseconds) => _t0.add(Duration(milliseconds: milliseconds));

void main() {
  group('velocity estimation', () {
    test('a single sample is not enough to divide by', () {
      final tracker = PanFlingTracker()..addPanSample(const Offset(10, 0), _t0);

      expect(tracker.estimateVelocity(), Offset.zero);
    });

    test('averages the sampled deltas over the sample window', () {
      final tracker = PanFlingTracker()
        ..addPanSample(const Offset(10, 5), _at(0))
        ..addPanSample(const Offset(10, 5), _at(50))
        ..addPanSample(const Offset(10, 5), _at(100));

      // The first sample establishes the start time. The remaining 20px spans
      // 100ms.
      expect(tracker.estimateVelocity(), const Offset(200, 100));
    });

    test('samples inside one frame report no velocity', () {
      // Dividing 20px by a sub-millisecond window would report thousands of
      // pixels per second and launch the map off screen.
      final tracker = PanFlingTracker()
        ..addPanSample(const Offset(10, 0), _t0)
        ..addPanSample(const Offset(10, 0), _t0);

      expect(tracker.estimateVelocity(), Offset.zero);
    });

    test('only the most recent samples count', () {
      // A long slow drag that ends in a fast flick should throw fast: older
      // samples must fall out of the window.
      final slow = <Offset>[for (var i = 0; i < 10; i++) const Offset(1, 0)];
      final tracker = PanFlingTracker();
      for (var i = 0; i < slow.length; i++) {
        tracker.addPanSample(slow[i], _at(i * 100));
      }
      for (var i = 0; i < 4; i++) {
        tracker.addPanSample(const Offset(40, 0), _at(1000 + i * 10));
      }

      // Only the last five samples survive. The sample at 900ms establishes
      // the start time and the four 40px flicks span the window to 1030ms.
      expect(tracker.estimateVelocity().dx, closeTo(160 / 0.13, 1e-6));
    });

    test('excludes movement recorded before the measured interval', () {
      final tracker = PanFlingTracker()
        ..addPanSample(const Offset(20, 0), _at(0))
        ..addPanSample(const Offset(-20, 0), _at(30));

      expect(tracker.estimateVelocity().dx, closeTo(-20 / 0.03, 1e-6));
    });

    test('clearing forgets the gesture', () {
      final tracker = PanFlingTracker()
        ..addPanSample(const Offset(10, 0), _at(0))
        ..addPanSample(const Offset(10, 0), _at(20))
        ..clearPanSamples();

      expect(tracker.estimateVelocity(), Offset.zero);
    });
  });

  group('fling threshold', () {
    test('a slow lift is not a fling', () {
      expect(PanFlingTracker().isFling(const Offset(60, 60)), isFalse);
    });

    test('speed is the diagonal, not either axis', () {
      // 80 on each axis is 113 px/s of actual motion.
      expect(PanFlingTracker().isFling(const Offset(80, 80)), isTrue);
    });

    test('accepts a custom velocity threshold', () {
      expect(
        PanFlingTracker().isFling(const Offset(80, 0), threshold: 50),
        isTrue,
      );
    });
  });

  group('fling progress', () {
    test('moves fastest at the start and decelerates', () {
      final tracker = PanFlingTracker()..beginFling(const Offset(1000, 0));

      final first = tracker.advance(0.25)!;
      final second = tracker.advance(0.5)!;
      final third = tracker.advance(0.75)!;

      expect(first.dx, greaterThan(second.dx));
      expect(second.dx, greaterThan(third.dx));
    });

    test('the steps add up to the damped throw distance', () {
      // Each step is a delta, so dropping or double-counting one would land
      // the camera somewhere other than where the throw aimed. The very last
      // steps of the ease-out fall under the visibility floor and are
      // deliberately skipped, which is the only shortfall allowed.
      final tracker = PanFlingTracker()..beginFling(const Offset(1000, 400));
      var total = Offset.zero;

      for (var i = 1; i <= 100; i++) {
        total += tracker.advance(i / 100) ?? Offset.zero;
      }

      const damping = 0.998 / 4.0;
      expect(total.dx, closeTo(1000 * damping, 0.05));
      expect(total.dy, closeTo(400 * damping, 0.05));
      expect(total.dx, lessThanOrEqualTo(1000 * damping));
    });

    test('a step too small to see reports nothing', () {
      // 0.02 px/s over the whole fling is well under one pixel.
      final tracker = PanFlingTracker()..beginFling(const Offset(0.02, 0));

      expect(tracker.advance(1), isNull);
    });

    test('a skipped step still advances the baseline', () {
      // Otherwise the invisible movement piles up and lands as one jump.
      final skipped = PanFlingTracker()..beginFling(const Offset(40, 0));
      expect(skipped.advance(0.0001), isNull);
      final afterSkip = skipped.advance(0.5)!;

      final fresh = PanFlingTracker()..beginFling(const Offset(40, 0));

      expect(afterSkip.dx, lessThan(fresh.advance(0.5)!.dx));
    });

    test('a new fling restarts from zero progress', () {
      // A second throw must not inherit the first one's progress and skip
      // most of its own distance.
      final tracker = PanFlingTracker()..beginFling(const Offset(1000, 0));
      tracker.advance(0.9);

      tracker.beginFling(const Offset(1000, 0));
      final fresh = tracker.advance(0.25)!;

      final reference = PanFlingTracker()..beginFling(const Offset(1000, 0));
      expect(fresh.dx, closeTo(reference.advance(0.25)!.dx, 1e-12));
    });
  });
}
