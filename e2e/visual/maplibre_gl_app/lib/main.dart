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
      final cameraPosition = reference.CameraPosition(
        target: reference.LatLng(camera.latitude, camera.longitude),
        zoom: camera.zoom,
        bearing: camera.bearing,
        tilt: camera.tilt,
      );

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
        onMapIdle: () {
          if (cameraApplied && scene.id != 'flutter-markers') onMapIdle();
        },
      );
    },
  );
}
