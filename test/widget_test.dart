// Rendering the map needs the native bridge and a GPU context. Public value
// objects and constructor wiring can still be covered without pumping it.
import 'dart:math' show Point;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

void main() {
  test('CameraPosition / LatLng public API', () {
    const pos = CameraPosition(target: LatLng(35.6812, 139.7671), zoom: 13);
    expect(pos.target.latitude, closeTo(35.6812, 1e-9));
    expect(pos.zoom, 13);
    expect(MapLibreStyles.demo, contains('maplibre.org'));
  });

  test('MapLibreMap stores symbol builders and GPU render hooks', () {
    Widget? iconBuilder(BuildContext context, MapSymbol symbol) => null;
    Widget? textBuilder(BuildContext context, MapSymbol symbol) => null;
    void gpuMapRenderCallback(MapLibreGpuRenderContext context) {}
    void gpuRenderCallback(MapLibreGpuRenderContext context) {}
    final repaint = ChangeNotifier();

    final map = MapLibreMap(
      symbolIconBuilder: iconBuilder,
      symbolTextBuilder: textBuilder,
      gpuMapRenderCallback: gpuMapRenderCallback,
      gpuRenderCallback: gpuRenderCallback,
      gpuRepaint: repaint,
      gpuOverlayDepthMode: MapLibreGpuDepthMode.shared,
    );

    expect(map.symbolIconBuilder, same(iconBuilder));
    expect(map.symbolTextBuilder, same(textBuilder));
    expect(map.gpuMapRenderCallback, same(gpuMapRenderCallback));
    expect(map.gpuRenderCallback, same(gpuRenderCallback));
    expect(map.gpuRepaint, same(repaint));
    expect(map.gpuOverlayDepthMode, MapLibreGpuDepthMode.shared);

    repaint.dispose();
  });

  test('MapLibreMap custom rendering hooks default to disabled', () {
    const map = MapLibreMap();

    expect(map.symbolIconBuilder, MapLibreMap.defaultSymbolIconBuilder);
    expect(map.symbolTextBuilder, MapLibreMap.defaultSymbolTextBuilder);
    expect(map.compassBuilder, MapLibreMap.defaultCompassBuilder);
    expect(map.logoBuilder, MapLibreMap.defaultLogoBuilder);
    expect(
      map.attributionButtonBuilder,
      MapLibreMap.defaultAttributionButtonBuilder,
    );
    expect(
      map.attributionDialogBuilder,
      MapLibreMap.defaultAttributionDialogBuilder,
    );
    expect(map.scaleControlBuilder, MapLibreMap.defaultScaleControlBuilder);
    expect(map.loadingBuilder, MapLibreMap.defaultLoadingBuilder);
    expect(map.errorBuilder, MapLibreMap.defaultErrorBuilder);
    expect(map.symbolFadeDuration, const Duration(milliseconds: 150));
    expect(
      map.symbolCullingPadding,
      const EdgeInsets.symmetric(horizontal: 120, vertical: 60),
    );
    expect(map.gpuMapRenderCallback, isNull);
    expect(map.gpuRenderCallback, isNull);
    expect(map.gpuRepaint, isNull);
    expect(map.gpuOverlayDepthMode, MapLibreGpuDepthMode.isolated);
  });

  test('MapLibreMap accepts null builders to hide symbol parts', () {
    const map = MapLibreMap(
      symbolIconBuilder: null,
      symbolTextBuilder: null,
      compassBuilder: null,
      logoBuilder: null,
      attributionButtonBuilder: null,
      attributionDialogBuilder: null,
      scaleControlBuilder: null,
      loadingBuilder: null,
      errorBuilder: null,
    );

    expect(map.symbolIconBuilder, isNull);
    expect(map.symbolTextBuilder, isNull);
    expect(map.compassBuilder, isNull);
    expect(map.logoBuilder, isNull);
    expect(map.attributionButtonBuilder, isNull);
    expect(map.attributionDialogBuilder, isNull);
    expect(map.scaleControlBuilder, isNull);
    expect(map.loadingBuilder, isNull);
    expect(map.errorBuilder, isNull);
  });

  test(
    'MapLibreMap core maplibre_gl-compatible options use matching defaults',
    () {
      const map = MapLibreMap();

      expect(map.cameraTargetBounds, CameraTargetBounds.unbounded);
      expect(map.minMaxZoomPreference, MinMaxZoomPreference.unbounded);
      expect(map.minMaxTiltPreference, MinMaxTiltPreference.unbounded);
      expect(map.rotateGesturesEnabled, isTrue);
      expect(map.scrollGesturesEnabled, isTrue);
      expect(map.zoomGesturesEnabled, isTrue);
      expect(map.tiltGesturesEnabled, isTrue);
      expect(map.doubleClickZoomEnabled, isNull);
      expect(map.gestureOptions, const MapGestureOptions());
      expect(map.trackCameraPosition, isFalse);
      expect(map.compassEnabled, isTrue);
      expect(map.logoEnabled, isFalse);
      expect(map.logoViewPosition, isNull);
      expect(map.logoViewMargins, isNull);
      expect(map.compassViewPosition, isNull);
      expect(map.compassViewMargins, isNull);
      expect(map.attributionButtonEnabled, isTrue);
      expect(
        map.attributionButtonPosition,
        AttributionButtonPosition.bottomRight,
      );
      expect(map.attributionButtonMargins, isNull);
      expect(map.scaleControlEnabled, isFalse);
      expect(map.scaleControlPosition, ScaleControlPosition.bottomLeft);
      expect(map.scaleControlUnit, ScaleControlUnit.metric);
      expect(map.scaleControlMargins, const Point<num>(8, 8));
      expect(map.scaleControlMaxWidth, 80);
      expect(map.scaleControlAvoidLogo, isTrue);
      expect(map.scaleControlLogoOffset, 27);
      expect(map.foregroundLoadColor, const Color(0x00000000));
      expect(map.onMapClick, isNull);
      expect(map.onMapLongClick, isNull);
    },
  );

  test('MapLibreMap stores core maplibre_gl-compatible options', () {
    const bounds = CameraTargetBounds(
      LatLngBounds(southwest: LatLng(30, 130), northeast: LatLng(40, 145)),
    );
    const zoom = MinMaxZoomPreference(4, 18);
    void onClick(Point<double> point, LatLng coordinates) {}

    final map = MapLibreMap(
      cameraTargetBounds: bounds,
      minMaxZoomPreference: zoom,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      doubleClickZoomEnabled: false,
      onMapClick: onClick,
      onMapLongClick: onClick,
      compassEnabled: false,
      logoEnabled: true,
      logoViewPosition: LogoViewPosition.topLeft,
      logoViewMargins: const Point(3, 4),
      compassViewPosition: CompassViewPosition.bottomRight,
      compassViewMargins: const Point(5, 6),
      attributionButtonEnabled: false,
      attributionButtonPosition: AttributionButtonPosition.topRight,
      attributionButtonMargins: const Point(7, 8),
      scaleControlEnabled: true,
      scaleControlPosition: ScaleControlPosition.topLeft,
      scaleControlUnit: ScaleControlUnit.nautical,
      foregroundLoadColor: const Color(0xFF123456),
    );

    expect(map.cameraTargetBounds, bounds);
    expect(map.minMaxZoomPreference, zoom);
    expect(map.rotateGesturesEnabled, isFalse);
    expect(map.tiltGesturesEnabled, isFalse);
    expect(map.doubleClickZoomEnabled, isFalse);
    expect(map.onMapClick, same(onClick));
    expect(map.onMapLongClick, same(onClick));
    expect(map.compassEnabled, isFalse);
    expect(map.logoEnabled, isTrue);
    expect(map.logoViewPosition, LogoViewPosition.topLeft);
    expect(map.logoViewMargins, const Point(3, 4));
    expect(map.compassViewPosition, CompassViewPosition.bottomRight);
    expect(map.compassViewMargins, const Point(5, 6));
    expect(map.attributionButtonEnabled, isFalse);
    expect(map.attributionButtonPosition, AttributionButtonPosition.topRight);
    expect(map.attributionButtonMargins, const Point(7, 8));
    expect(map.scaleControlEnabled, isTrue);
    expect(map.scaleControlPosition, ScaleControlPosition.topLeft);
    expect(map.scaleControlUnit, ScaleControlUnit.nautical);
    expect(map.foregroundLoadColor, const Color(0xFF123456));
  });
}
