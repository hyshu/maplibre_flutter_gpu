import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

Completer<gpu.MapLibreMapController>? _controllerCompleter;

Future<gpu.MapLibreMapController> get visualE2eController {
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
      await controller.queryCameraPosition() ??
      gpu.CameraPosition(
        target: gpu.LatLng(camera.latitude, camera.longitude),
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
      gpu.CameraUpdate.newCameraPosition(
        gpu.CameraPosition(
          target: gpu.LatLng(
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
    if (completed != true) {
      throw StateError('maplibre_flutter_gpu camera step failed');
    }
    applyWatch.stop();
    visualE2ePerformanceProbe.recordCameraStep(applyWatch.elapsed);
    await Future<void>.delayed(stepDelay);
  }
}

Future<void> main() {
  final controllerCompleter = Completer<gpu.MapLibreMapController>();
  _controllerCompleter = controllerCompleter;

  return runVisualE2eApp(
    implementation: 'maplibre_flutter_gpu',
    mapBuilder: (VisualScene scene, VoidCallback onMapIdle) {
      final camera = scene.camera;
      gpu.MapLibreMapController? controller;
      var cameraApplied = false;
      final nativeIdle = Completer<void>();
      final cameraPosition = gpu.CameraPosition(
        target: gpu.LatLng(camera.latitude, camera.longitude),
        zoom: camera.zoom,
        bearing: camera.bearing,
        tilt: camera.tilt,
      );

      return gpu.MapLibreMap(
        styleString: scene.styleJson,
        initialCameraPosition: cameraPosition,
        rotateGesturesEnabled: false,
        scrollGesturesEnabled: false,
        zoomGesturesEnabled: false,
        tiltGesturesEnabled: false,
        doubleClickZoomEnabled: false,
        trackCameraPosition: true,
        compassEnabled: false,
        logoEnabled: false,
        attributionButtonEnabled: false,
        scaleControlEnabled: false,
        foregroundLoadColor: scene.backgroundColor,
        onMapCreated: (value) {
          controller = value;
          if (!controllerCompleter.isCompleted) {
            controllerCompleter.complete(value);
          }
        },
        onStyleLoadedCallback: () async {
          await controller?.moveCamera(
            gpu.CameraUpdate.newCameraPosition(cameraPosition),
          );
          cameraApplied = true;
          final appliedCamera = await controller?.queryCameraPosition();
          debugPrint('VISUAL_E2E_CAMERA|maplibre_flutter_gpu|$appliedCamera');
          if (scene.id == 'flutter-markers') {
            if (Platform.isAndroid) {
              try {
                await nativeIdle.future.timeout(const Duration(seconds: 45));
              } on TimeoutException {
                debugPrint(
                  'VISUAL_E2E_IDLE_TIMEOUT|maplibre_flutter_gpu|'
                  '${scene.id}',
                );
              }
              await Future<void>.delayed(const Duration(seconds: 2));
            } else {
              await Future<void>.delayed(const Duration(seconds: 12));
            }
            onMapIdle();
          }
        },
        onMapIdle: () {
          if (!cameraApplied) return;
          if (scene.id == 'flutter-markers') {
            if (!nativeIdle.isCompleted) nativeIdle.complete();
          } else {
            onMapIdle();
          }
        },
      );
    },
  );
}
