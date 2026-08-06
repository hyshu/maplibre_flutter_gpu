import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/state/map_viewport.dart';

ViewportRequest _v(double width, double height, [double dpr = 2]) =>
    (logicalSize: Size(width, height), dpr: dpr);

void main() {
  group('scheduling', () {
    test('the first request schedules a callback', () {
      expect(MapViewportCoalescer().request(_v(800, 600)), isTrue);
    });

    test('a burst within one frame schedules only one callback', () {
      // Otherwise every LayoutBuilder rebuild during a drag-resize would queue
      // its own post-frame apply and resize the native map repeatedly.
      final coalescer = MapViewportCoalescer();

      expect(coalescer.request(_v(800, 600)), isTrue);
      expect(coalescer.request(_v(900, 600)), isFalse);
      expect(coalescer.request(_v(1000, 600)), isFalse);

      // The queued callback still applies the newest size, not the first.
      expect(coalescer.takePending(), _v(1000, 600));
    });

    test('an identical repeat of the pending request changes nothing', () {
      final coalescer = MapViewportCoalescer()..request(_v(800, 600));
      expect(coalescer.request(_v(800, 600)), isFalse);
      expect(coalescer.takePending(), _v(800, 600));
    });

    test('invalid pixel ratios normalize before deduplication', () {
      final coalescer = MapViewportCoalescer();

      expect(coalescer.request(_v(800, 600, double.nan)), isTrue);
      expect(coalescer.request(_v(800, 600, double.nan)), isFalse);
      expect(coalescer.takePending()?.dpr, 1);
    });
  });

  group('deduplication against the applied viewport', () {
    test('re-requesting the applied viewport does nothing', () {
      final coalescer = MapViewportCoalescer()..markApplied(_v(800, 600));
      expect(coalescer.request(_v(800, 600)), isFalse);
      expect(coalescer.takePending(), isNull);
    });

    test('a device pixel ratio change alone is a real change', () {
      final coalescer = MapViewportCoalescer()..markApplied(_v(800, 600, 2));
      expect(coalescer.request(_v(800, 600, 3)), isTrue);
    });

    test(
      'returning to the applied viewport while one is pending still applies',
      () {
        // The map is mid-transition: something else is queued, so the applied
        // value is not what the map will show. Skipping here would leave the
        // intermediate size in effect.
        final coalescer = MapViewportCoalescer()..markApplied(_v(800, 600));
        coalescer
          ..request(_v(900, 600))
          ..takePending();
        coalescer.markApplied(_v(900, 600));
        coalescer.request(_v(1000, 600));

        expect(coalescer.request(_v(900, 600)), isFalse);
        expect(coalescer.takePending(), _v(900, 600));
      },
    );
  });

  group('post-frame handoff', () {
    test('a request made during the apply queues a new callback', () {
      // takePending clears the flag first, so an apply that itself triggers a
      // relayout does not lose the resulting viewport.
      final coalescer = MapViewportCoalescer()..request(_v(800, 600));
      coalescer.takePending();

      expect(coalescer.request(_v(900, 600)), isTrue);
    });

    test('taking twice yields nothing the second time', () {
      final coalescer = MapViewportCoalescer()..request(_v(800, 600));
      expect(coalescer.takePending(), isNotNull);
      expect(coalescer.takePending(), isNull);
    });

    test('cancelling drops the queued request', () {
      final coalescer = MapViewportCoalescer()..request(_v(800, 600));
      coalescer.cancel();

      expect(coalescer.isScheduled, isFalse);
      expect(coalescer.takePending(), isNull);
      // A later request must schedule again rather than assuming a live queue.
      expect(coalescer.request(_v(800, 600)), isTrue);
    });
  });

  group('MapViewport', () {
    test('initialization pins the observed ratio and derives dimensions', () {
      final viewport = MapViewport()
        ..adoptForInitialization(const Size(800.5, 600.5), 2);
      expect(viewport.devicePixelRatio, 2);
      expect(viewport.logicalWidth, 800);
      expect(viewport.logicalHeight, 600);
      expect(viewport.physicalWidth, 1600);
      expect(viewport.physicalHeight, 1200);
    });

    test('a nonsensical ratio falls back to 1', () {
      final viewport = MapViewport()
        ..adoptForInitialization(const Size(400, 300), 0);
      expect(viewport.devicePixelRatio, 1);
      expect(viewport.physicalWidth, 400);
    });

    test('initialization dimensions can only be adopted once', () {
      final viewport = MapViewport()
        ..adoptForInitialization(const Size(800, 600), 2)
        ..adoptForInitialization(const Size(400, 300), 3);

      expect(viewport.devicePixelRatio, 2);
      expect(viewport.logicalSize, const Size(800, 600));
      expect(viewport.physicalWidth, 1600);
      expect(viewport.physicalHeight, 1200);
    });

    test('layout before initialization records but resizes nothing', () {
      final viewport = MapViewport();
      expect(
        viewport.applyLayout(const Size(800, 600), 2, initialized: false),
        isFalse,
      );
      // Recorded, so initialization can read the first laid-out viewport.
      expect(viewport.applied?.logicalSize, const Size(800, 600));
      expect(viewport.logicalWidth, 0);
    });

    test('a logical resize reports that native must be resized', () {
      final viewport = MapViewport()
        ..adoptForInitialization(const Size(800, 600), 2)
        ..applyLayout(const Size(800, 600), 2, initialized: true);
      expect(
        viewport.applyLayout(const Size(400, 300), 2, initialized: true),
        isTrue,
      );
      expect(viewport.logicalWidth, 400);
      expect(viewport.physicalWidth, 800);
    });

    test('re-applying the same size resizes nothing', () {
      final viewport = MapViewport()
        ..adoptForInitialization(const Size(800, 600), 2)
        ..applyLayout(const Size(800, 600), 2, initialized: true);
      expect(
        viewport.applyLayout(const Size(800, 600), 2, initialized: true),
        isFalse,
      );
    });

    test('a ratio change after initialization does not re-scale', () {
      final viewport = MapViewport()
        ..adoptForInitialization(const Size(800, 600), 2)
        ..applyLayout(const Size(800, 600), 2, initialized: true);
      // HeadlessFrontend keeps the ratio it was constructed with, so the
      // render target must stay on it even as the display's ratio moves.
      expect(
        viewport.applyLayout(const Size(400, 300), 3, initialized: true),
        isTrue,
      );
      expect(viewport.devicePixelRatio, 2);
      expect(viewport.physicalWidth, 800);
    });

    test('a collapsed layout still yields a viewport native accepts', () {
      final viewport = MapViewport()
        ..adoptForInitialization(const Size(0, 0), 2);
      expect(viewport.logicalWidth, 1);
      expect(viewport.logicalHeight, 1);
      expect(viewport.physicalWidth, 2);
      expect(viewport.physicalHeight, 2);
    });

    test('non-finite dimensions normalize to a safe viewport', () {
      final dimensions = viewportDimensions(
        const Size(double.nan, double.infinity),
        double.nan,
      );

      expect(dimensions.logicalWidth, 1);
      expect(dimensions.logicalHeight, 1);
      expect(dimensions.physicalWidth, 1);
      expect(dimensions.physicalHeight, 1);
    });
  });
}
