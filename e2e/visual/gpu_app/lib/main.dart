import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

Completer<gpu.MapLibreMapController>? _controllerCompleter;
List<gpu.LabelData>? _paintUpdatePlacementBefore;

Future<gpu.MapLibreMapController> get visualE2eController {
  final controllerCompleter = _controllerCompleter;
  if (controllerCompleter == null) {
    throw StateError('The visual E2E app has not started');
  }
  return controllerCompleter.future;
}

List<gpu.LabelData>? get visualE2ePaintUpdatePlacementBefore =>
    _paintUpdatePlacementBefore;

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
  _paintUpdatePlacementBefore = null;

  return runVisualE2eApp(
    implementation: 'maplibre_flutter_gpu',
    mapBuilder: (VisualScene scene, VoidCallback onMapIdle) {
      final camera = scene.camera;
      gpu.MapLibreMapController? controller;
      var cameraApplied = false;
      var nativeIdleSeen = false;
      var paintUpdateStarted = false;
      var paintUpdateApplied = false;
      final nativeIdle = Completer<void>();
      final cameraPosition = gpu.CameraPosition(
        target: gpu.LatLng(camera.latitude, camera.longitude),
        zoom: camera.zoom,
        bearing: camera.bearing,
        tilt: camera.tilt,
      );

      Future<void> applyPaintUpdate() async {
        final mapController = controller;
        if (mapController == null) {
          throw StateError('maplibre_flutter_gpu controller is unavailable');
        }
        _paintUpdatePlacementBefore = .unmodifiable(
          mapController.getPlacedLabels(),
        );
        await mapController.setLayerProperties(
          'paint-update-symbols',
          const _GpuSymbolPaintUpdate(),
        );
        paintUpdateApplied = true;
        debugPrint('VISUAL_E2E_PAINT_UPDATED|maplibre_flutter_gpu|${scene.id}');
        onMapIdle();
      }

      void handleMapIdle() {
        nativeIdleSeen = true;
        if (scene.id == 'flutter-markers' && !nativeIdle.isCompleted) {
          nativeIdle.complete();
        }
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

      return Builder(
        builder: (context) {
          final map = gpu.MapLibreMap(
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
              debugPrint(
                'VISUAL_E2E_CAMERA|maplibre_flutter_gpu|$appliedCamera',
              );
              if (nativeIdleSeen && scene.id != 'flutter-markers') {
                handleMapIdle();
              }
              if (scene.id == 'flutter-markers') {
                if (Platform.isAndroid) {
                  try {
                    await nativeIdle.future.timeout(
                      const Duration(seconds: 45),
                    );
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
            onMapIdle: handleMapIdle,
          );
          if (!Platform.isMacOS) return map;

          return MediaQuery(
            data: MediaQuery.of(context).copyWith(devicePixelRatio: 2),
            child: map,
          );
        },
      );
    },
  );
}

final class _GpuSymbolPaintUpdate implements gpu.LayerProperties {
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
