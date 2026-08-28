import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as reference;
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

Completer<reference.MapLibreMapController>? _controllerCompleter;

Future<reference.MapLibreMapController> get visualE2eController {
  final controllerCompleter = _controllerCompleter;
  if (controllerCompleter == null) {
    throw StateError('The visual E2E app has not started');
  }
  return controllerCompleter.future;
}

Future<void> animateVisualE2eCamera(
  VisualCamera camera,
  Duration duration,
) async {
  final controller = await visualE2eController;
  final start =
      controller.cameraPosition ??
      reference.CameraPosition(
        target: reference.LatLng(camera.latitude, camera.longitude),
        zoom: camera.zoom,
        bearing: camera.bearing,
        tilt: camera.tilt,
      );
  final steps =
      duration.inMicroseconds ~/
      const Duration(milliseconds: 16).inMicroseconds;
  final stepDelay = duration ~/ steps;
  for (var step = 1; step <= steps; step++) {
    final t = step / steps;
    final applyWatch = Stopwatch()..start();
    final completed = await controller.moveCamera(
      reference.CameraUpdate.newCameraPosition(
        reference.CameraPosition(
          target: reference.LatLng(
            start.target.latitude +
                (camera.latitude - start.target.latitude) * t,
            start.target.longitude +
                (camera.longitude - start.target.longitude) * t,
          ),
          zoom: start.zoom + (camera.zoom - start.zoom) * t,
          bearing: start.bearing + (camera.bearing - start.bearing) * t,
          tilt: start.tilt + (camera.tilt - start.tilt) * t,
        ),
      ),
    );
    if (completed == false) {
      throw StateError('maplibre_gl camera step failed');
    }
    applyWatch.stop();
    visualE2ePerformanceProbe.recordCameraStep(applyWatch.elapsed);
    await Future<void>.delayed(stepDelay);
  }
}

Future<void> main() {
  final controllerCompleter = Completer<reference.MapLibreMapController>();
  _controllerCompleter = controllerCompleter;

  return runVisualE2eApp(
    implementation: 'maplibre_gl',
    mapBuilder: (VisualScene scene, VoidCallback onMapIdle) {
      final camera = scene.camera;
      reference.MapLibreMapController? controller;
      var cameraApplied = false;
      var paintUpdateStarted = false;
      var paintUpdateApplied = false;
      final cameraPosition = reference.CameraPosition(
        target: reference.LatLng(camera.latitude, camera.longitude),
        zoom: camera.zoom,
        bearing: camera.bearing,
        tilt: camera.tilt,
      );

      Future<void> applyPaintUpdate() async {
        final mapController = controller;
        if (mapController == null) {
          throw StateError('maplibre_gl controller is unavailable');
        }
        await mapController.setLayerProperties(
          'paint-update-symbols',
          const _ReferenceSymbolPaintUpdate(),
        );
        paintUpdateApplied = true;
        debugPrint('VISUAL_E2E_PAINT_UPDATED|maplibre_gl|${scene.id}');
        onMapIdle();
      }

      void handleMapIdle() {
        if (!cameraApplied) return;
        if (scene.id != 'symbol-paint-update') {
          if (scene.id != 'flutter-markers') onMapIdle();

          return;
        }
        if (paintUpdateApplied) {
          onMapIdle();

          return;
        }
        if (paintUpdateStarted) return;
        paintUpdateStarted = true;
        unawaited(applyPaintUpdate());
      }

      return reference.MapLibreMap(
        styleString: scene.styleJson,
        initialCameraPosition: cameraPosition,
        rotateGesturesEnabled: false,
        scrollGesturesEnabled: false,
        zoomGesturesEnabled: false,
        tiltGesturesEnabled: false,
        doubleClickZoomEnabled: false,
        dragEnabled: false,
        trackCameraPosition: true,
        compassEnabled: false,
        logoEnabled: false,
        attributionButtonMargins: const math.Point<double>(0, 0),
        scaleControlEnabled: false,
        myLocationEnabled: false,
        foregroundLoadColor: scene.backgroundColor,
        translucentTextureSurface: false,
        onMapCreated: (value) {
          controller = value;
          if (!controllerCompleter.isCompleted) {
            controllerCompleter.complete(value);
          }
        },
        onStyleLoadedCallback: () async {
          await controller?.moveCamera(
            reference.CameraUpdate.newCameraPosition(cameraPosition),
          );
          cameraApplied = true;
          debugPrint(
            'VISUAL_E2E_CAMERA|maplibre_gl|${controller?.cameraPosition}',
          );
          if (scene.id == 'flutter-markers') {
            await Future<void>.delayed(const Duration(seconds: 12));
            onMapIdle();
          }
        },
        onMapIdle: handleMapIdle,
      );
    },
  );
}

final class _ReferenceSymbolPaintUpdate implements reference.LayerProperties {
  const new();

  @override
  Map<String, dynamic> toJson({bool skipNulls = true}) => {
    'icon-color': '#0284c7',
    'icon-opacity': 1,
    'icon-halo-color': '#f97316',
    'icon-halo-width': 4,
    'icon-halo-blur': 1,
    'text-color': '#c026d3',
    'text-opacity': 1,
    'text-halo-color': '#fef08a',
    'text-halo-width': 4,
    'text-halo-blur': 1,
  };
}
