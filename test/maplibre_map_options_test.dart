import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/state/gesture/gesture_math.dart';

void main() {
  test('whole-world bounds retain their span through normalization', () {
    for (final east in [180.0, 540.0]) {
      final bounds = LatLngBounds(
        southwest: const LatLng(-80, -180),
        northeast: LatLng(80, east),
      );
      expect(bounds.coversAllLongitudes, isTrue);
      for (final longitude in [-180.0, -90.0, 0.0, 90.0, 179.0]) {
        expect(bounds.contains(LatLng(0, longitude)), isTrue);
      }
      expect(bounds.contains(const LatLng(85, 0)), isFalse);
      expect(bounds.toList(), [
        [-80.0, -180.0],
        [80.0, 180.0],
      ]);
      expect(
        bounds,
        isNot(
          const LatLngBounds(
            southwest: LatLng(-80, -180),
            northeast: LatLng(80, -180),
          ),
        ),
      );
    }
    const wrapped = LatLngBounds(
      southwest: LatLng(-10, 170),
      northeast: LatLng(10, 190),
    );
    expect(wrapped.coversAllLongitudes, isFalse);
    expect(wrapped.contains(const LatLng(0, 180)), isTrue);
    expect(wrapped.contains(const LatLng(0, 0)), isFalse);
  });

  test('LatLng normalizes longitude like maplibre_gl', () {
    expect(const LatLng(100, 540), const LatLng(90, -180));
    expect(const LatLng(-100, -540), const LatLng(-90, -180));
    expect(const LatLng(35, 139).toGeoJsonCoordinates(), <double>[139, 35]);
  });

  test('LatLngBounds supports antimeridian-crossing bounds', () {
    const bounds = LatLngBounds(
      southwest: LatLng(-10, 170),
      northeast: LatLng(10, -170),
    );

    expect(bounds.contains(const LatLng(0, 175)), isTrue);
    expect(bounds.contains(const LatLng(0, -175)), isTrue);
    expect(bounds.contains(const LatLng(0, 0)), isFalse);
    expect(bounds.contains(const LatLng(20, 175)), isFalse);
  });

  test('camera bounds and zoom preferences are value objects', () {
    const bounds = LatLngBounds(
      southwest: LatLng(30, 130),
      northeast: LatLng(40, 145),
    );

    expect(const CameraTargetBounds(bounds), const CameraTargetBounds(bounds));
    expect(const CameraTargetBounds(bounds).toJson(), [
      [
        [30.0, 130.0],
        [40.0, 145.0],
      ],
    ]);
    expect(
      const MinMaxZoomPreference(3, 18),
      const MinMaxZoomPreference(3, 18),
    );
    expect(MinMaxZoomPreference.unbounded.toJson(), [null, null]);
    expect(
      const MinMaxTiltPreference(10, 85),
      const MinMaxTiltPreference(10, 85),
    );
    expect(MinMaxTiltPreference.unbounded.toJson(), [null, null]);
  });

  test('gesture compatibility helpers resolve defaults and tilt intent', () {
    expect(doubleClickZoomIsEnabled(null, true), isTrue);
    expect(doubleClickZoomIsEnabled(null, false), isFalse);
    expect(doubleClickZoomIsEnabled(false, true), isFalse);
    expect(bearingGestureDelta(math.pi / 2), closeTo(-90, 0.0001));
    expect(bearingGestureDelta(-math.pi / 2), closeTo(90, 0.0001));
    expect(trackpadScaleDelta(1.2, 1), closeTo(1.2, 0.0001));
    expect(trackpadScaleDelta(1.2, 1.1), closeTo(1.0909, 0.0001));
    expect(trackpadScaleDelta(0, 1), 1);
    expect(trackpadScaleDelta(double.nan, 1), 1);
    expect(trackpadTiltDelta(8), -4);
    expect(mouseTiltDelta(8), -4);
    expect(mouseRotateDelta(8), 4);
    expect(quickZoomScaleDelta(-10), closeTo(0.90484, 0.00001));
    expect(quickZoomScaleDelta(10), closeTo(1.10517, 0.00001));
    expect(quickZoomScaleDelta(double.nan), 1);
    expect(quickZoomScaleDelta(10, sensitivity: 0), 1);

    expect(
      tiltGestureDelta(
        focalPointDelta: const Offset(0, -6),
        scaleDelta: 1,
        rotationDelta: 0,
        fingersApproximatelyHorizontal: true,
      ),
      3,
    );
    expect(
      tiltGestureDelta(
        focalPointDelta: const Offset(0, -6),
        scaleDelta: 1.1,
        rotationDelta: 0,
        fingersApproximatelyHorizontal: true,
      ),
      isNull,
    );
    expect(
      tiltGestureDelta(
        focalPointDelta: const Offset(0, -6),
        scaleDelta: 1,
        rotationDelta: 0,
        fingersApproximatelyHorizontal: false,
      ),
      isNull,
    );
    expect(
      tiltGestureDelta(
        focalPointDelta: const Offset(4, -6),
        scaleDelta: 1,
        rotationDelta: 0,
        fingersApproximatelyHorizontal: true,
      ),
      isNull,
    );
    expect(
      tiltGestureDelta(
        focalPointDelta: const Offset(0.5, -4),
        scaleDelta: 1,
        rotationDelta: 0,
        fingersApproximatelyHorizontal: true,
        minimumVerticalDelta: 4,
      ),
      2,
    );
    expect(
      tiltGestureDelta(
        focalPointDelta: const Offset(0.05, -0.5),
        scaleDelta: 1,
        rotationDelta: 0,
        fingersApproximatelyHorizontal: true,
        minimumVerticalDelta: 0,
      ),
      0.25,
    );
  });

  test('gesture options reject non-finite thresholds and sensitivity', () {
    expect(
      () => MapGestureOptions(flingVelocityThreshold: double.infinity),
      throwsAssertionError,
    );
    expect(
      () => MapGestureOptions(quickZoomSensitivity: double.infinity),
      throwsAssertionError,
    );
  });
}
