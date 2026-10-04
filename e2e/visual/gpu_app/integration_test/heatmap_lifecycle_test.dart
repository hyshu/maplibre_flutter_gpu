import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

const _diagnostics = bool.fromEnvironment('HEATMAP_DIAGNOSTICS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('heatmap survives camera, viewport, and style changes', (
    tester,
  ) async {
    setVisualE2eRuntimeSceneId('heatmap');
    final style = (await loadVisualScene()).styleJson;
    final size = ValueNotifier(const Size(400, 300));
    final boundaryKey = GlobalKey();
    gpu.MapLibreMapController? controller;
    var styleLoads = 0;
    String? initializationError;
    const overlap = gpu.LatLng(7, 0);
    const densityColor = [249.0, 118.0, 61.0];
    const backgroundColor = [231.0, 237.0, 243.0];

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      size.dispose();
      await stopVisualE2eAssetServer();
      setVisualE2eRuntimeSceneId(null);
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2),
          child: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder(
              valueListenable: size,
              builder: (context, dimensions, _) => RepaintBoundary(
                key: boundaryKey,
                child: SizedBox.fromSize(
                  size: dimensions,
                  child: gpu.MapLibreMap(
                    styleString: style,
                    initialCameraPosition: const gpu.CameraPosition(
                      target: overlap,
                      zoom: 4,
                    ),
                    compassEnabled: false,
                    logoEnabled: false,
                    attributionButtonEnabled: false,
                    scaleControlEnabled: false,
                    symbolCompositingMode: .interleaved,
                    symbolTextBuilder: (context, symbol) =>
                        const SizedBox(width: 1, height: 1),
                    errorBuilder: (context, error) {
                      initializationError = error;

                      return Text(error);
                    },
                    onMapCreated: (value) => controller = value,
                    onStyleLoadedCallback: () => styleLoads++,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _waitForMap(
      tester,
      () => styleLoads > 0 && controller!.isMapIdle,
      diagnosticState: () =>
          'styleLoads=$styleLoads controller=${controller != null} '
          'nativeStyleLoaded=${controller?.bridge.isStyleLoaded()} '
          'nativeIdle=${controller?.isMapIdle} '
          'initializationError=$initializationError',
    );

    Future<void> verify(
      List<double> expected,
      String phase, {
      double tolerance = 30,
    }) async {
      if (_diagnostics) debugPrint('VISUAL_E2E_HEATMAP|$phase|capture-start');
      final actual = await _sampleMap(
        tester,
        boundaryKey,
        controller!.toScreenOffset(overlap),
      );
      if (_diagnostics) {
        debugPrint('VISUAL_E2E_HEATMAP|$phase|capture-ready|$actual');
      }
      if ([0, 1, 2].any(
        (channel) => (actual[channel] - expected[channel]).abs() > tolerance,
      )) {
        await _writeFailureImage(tester, boundaryKey, phase);
        await _logNativeHeatmaps(controller!, phase);
      }
      for (var channel = 0; channel < 3; channel++) {
        expect(
          actual[channel],
          closeTo(expected[channel], tolerance),
          reason: '$phase channel $channel, RGB $actual',
        );
      }
      expect(tester.takeException(), isNull, reason: phase);
    }

    Future<void> replaceStyle(String replacement, String phase) async {
      final before = styleLoads;
      await controller!.setStyle(replacement);
      await _waitForMap(
        tester,
        () => styleLoads > before && controller!.isMapIdle,
      );
      if (_diagnostics) {
        debugPrint('VISUAL_E2E_HEATMAP|$phase|style-ready');
        await _logNativeHeatmaps(controller!, phase);
      }
    }

    await verify(densityColor, 'initial density');
    await controller!.moveCamera(
      gpu.CameraUpdate.newLatLngZoom(const gpu.LatLng(8, 2), 4.4),
    );
    await _waitForMap(tester, () => controller!.isMapIdle);
    await verify(densityColor, 'pan and zoom');

    for (final dimensions in [const Size(280, 220), const Size(600, 360)]) {
      size.value = dimensions;
      await _waitForMap(tester, () => controller!.isMapIdle);
      await verify(densityColor, 'resize to $dimensions');
    }

    await controller!.moveCamera(gpu.CameraUpdate.newLatLngZoom(overlap, 4));
    await _waitForMap(tester, () => controller!.isMapIdle);
    await replaceStyle(
      '{"version":8,"sources":{},"layers":['
          '{"id":"background","type":"background",'
          '"paint":{"background-color":"#e7edf3"}}]}',
      'remove heatmap',
    );
    await verify(backgroundColor, 'style without heatmap', tolerance: 8);
    await replaceStyle(style, 'restore heatmap');
    await verify(densityColor, 'restored density');

    final transparent = jsonDecode(style) as Map<String, dynamic>;
    for (final layer in transparent['layers'] as List<dynamic>) {
      if (layer['type'] == 'heatmap') {
        layer['paint']['heatmap-opacity'] = 0;
      }
    }
    await replaceStyle(jsonEncode(transparent), 'zero opacity');
    await verify(backgroundColor, 'zero opacity clears density', tolerance: 8);
    await replaceStyle(style, 'restore opacity');
    await verify(densityColor, 'restored opacity');

    final empty = jsonDecode(style) as Map<String, dynamic>;
    for (final source in (empty['sources'] as Map<String, dynamic>).values) {
      source['data']['features'] = <Object>[];
    }
    await replaceStyle(jsonEncode(empty), 'empty sources');
    await verify(backgroundColor, 'empty sources clear density', tolerance: 8);
    await replaceStyle(style, 'restore sources');
    await verify(densityColor, 'restored sources');

    final initialLayers =
        (jsonDecode(style) as Map<String, dynamic>)['layers'] as List<dynamic>;
    final densityLayer = initialLayers.singleWhere(
      (dynamic layer) => layer['id'] == 'density',
    );
    final properties = gpu.HeatmapLayerProperties.fromJson(
      densityLayer['paint'] as Map<String, dynamic>,
    );
    await controller!.removeLayer('density');
    await _waitForMap(tester, () => controller!.isMapIdle);
    await verify(backgroundColor, 'remove heatmap layer', tolerance: 8);
    await controller!.addHeatmapLayer(
      'density',
      'runtime-density',
      properties,
      belowLayerId: 'overlay-underlay',
    );
    await _waitForMap(tester, () => controller!.isMapIdle);
    await verify(densityColor, 'addHeatmapLayer renders density');
    await controller!.setLayerProperties(
      'runtime-density',
      properties.copyWith(const gpu.HeatmapLayerProperties(heatmapOpacity: 0)),
    );
    await _waitForMap(tester, () => controller!.isMapIdle);
    await verify(
      backgroundColor,
      'setLayerProperties clears opacity',
      tolerance: 8,
    );
    await controller!.setLayerProperties('runtime-density', properties);
    await _waitForMap(tester, () => controller!.isMapIdle);
    await verify(densityColor, 'setLayerProperties restores opacity');

    setVisualE2eRuntimeSceneId('text-symbol');
    final symbolResources =
        jsonDecode((await loadVisualScene()).styleJson) as Map<String, dynamic>;
    setVisualE2eRuntimeSceneId('heatmap');
    final strata = jsonDecode(style) as Map<String, dynamic>;
    strata['glyphs'] = symbolResources['glyphs'];
    strata['sources']['stratum-marker'] = {
      'type': 'geojson',
      'data': {
        'type': 'Feature',
        'properties': <String, Object>{},
        'geometry': {
          'type': 'Point',
          'coordinates': [0, 7],
        },
      },
    };
    final layers = strata['layers'] as List<dynamic>;
    layers.add({
      'id': 'stratum-marker',
      'type': 'symbol',
      'source': 'stratum-marker',
      'layout': {
        'text-field': 'STRATUM',
        'text-font': ['NotoCJK'],
        'text-size': 18,
        'text-allow-overlap': true,
      },
    });
    layers.add({
      'id': 'density-above-symbol',
      'type': 'heatmap',
      'source': 'density',
      'paint': {
        'heatmap-radius': 62,
        'heatmap-weight': ['get', 'weight'],
        'heatmap-intensity': 0.9,
        'heatmap-opacity': 0.5,
        'heatmap-color': [
          'interpolate',
          ['linear'],
          ['heatmap-density'],
          0,
          'rgba(255,0,255,0)',
          0.1,
          '#ff00ff',
          1,
          '#ff00ff',
        ],
      },
    });
    await replaceStyle(jsonEncode(strata), 'symbol-separated heatmaps');
    expect(
      controller!.getPlacedLabels().any(
        (label) => label.layer == 'stratum-marker' && label.textPlaced,
      ),
      isTrue,
      reason: 'A placed symbol must split the two GPU heatmap strata.',
    );
    await verify([252, 59, 158], 'density above a symbol stratum');
    await controller!.moveCamera(
      gpu.CameraUpdate.newLatLngZoom(const gpu.LatLng(8, 2), 4.4),
    );
    await _waitForMap(tester, () => controller!.isMapIdle);
    await verify([252, 59, 158], 'replayed symbol-separated density');
  });
}

Future<void> _logNativeHeatmaps(
  gpu.MapLibreMapController controller,
  String phase,
) async {
  final style =
      jsonDecode((await controller.getStyle())!) as Map<String, dynamic>;
  final paints = <Object>[
    for (final layer in style['layers'] as List<dynamic>)
      if (layer['type'] == 'heatmap')
        {'id': layer['id'], 'opacity': layer['paint']['heatmap-opacity']},
  ];
  final bridge = controller.bridge;
  final snapshot = bridge.supportsAsyncRendering
      ? bridge.acquireFrameSnapshot()
      : null;
  try {
    if (bridge.supportsAsyncRendering && snapshot == null) {
      debugPrint('VISUAL_E2E_HEATMAP|$phase|snapshot-unavailable|$paints');

      return;
    }
    final metadata = bridge.frameGetMetadata();
    final commands = <Object>[];
    if (metadata.commands != ffi.nullptr) {
      final bytes = metadata.commands.cast<ffi.Uint8>().asTypedList(
        metadata.commandCount * metadata.commandStride,
      );
      final data = ByteData.sublistView(bytes);
      for (var index = 0; index < metadata.commandCount; index++) {
        final offset = index * metadata.commandStride;
        final shader = data.getUint32(
          offset + DrawCommandAbi.shaderType,
          Endian.little,
        );
        commands.add({
          'shader': shader,
          'target': data.getUint32(
            offset + DrawCommandAbi.renderTargetId,
            Endian.little,
          ),
          if (shader == ShaderType.heatmapTexture)
            'opacity': data.getFloat32(
              offset + DrawCommandAbi.drawableUBO + 64,
              Endian.little,
            ),
        });
      }
    }
    debugPrint(
      'VISUAL_E2E_HEATMAP|$phase|native|'
      '${jsonEncode({'paint': paints, 'commands': commands})}',
    );
  } finally {
    snapshot?.release();
  }
}

Future<void> _writeFailureImage(
  WidgetTester tester,
  GlobalKey key,
  String phase,
) async {
  var root = Directory.current.absolute;
  while (!File('${root.path}/lib/maplibre_flutter_gpu.dart').existsSync()) {
    if (root.parent.path == root.path) return;
    root = root.parent;
  }
  final file = File(
    '${root.path}/build/heatmap-validation/lifecycle/'
    '${phase.replaceAll(RegExp('[^a-zA-Z0-9]+'), '-')}.png',
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await _pumpCapture(tester, boundary.toImage(pixelRatio: 2));
  try {
    final data = await _pumpCapture(
      tester,
      image.toByteData(format: ui.ImageByteFormat.png),
    );
    if (data == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List());
    debugPrint('VISUAL_E2E_HEATMAP|$phase|failure-image|${file.path}');
  } finally {
    image.dispose();
  }
}

Future<void> _waitForMap(
  WidgetTester tester,
  bool Function() ready, {
  String Function()? diagnosticState,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  var nextDiagnostic = DateTime.now().add(const Duration(seconds: 5));
  var settledFrames = 0;
  while (settledFrames < 5) {
    final state =
        'lifecycle=${WidgetsBinding.instance.lifecycleState} '
        '${diagnosticState?.call() ?? ''}';
    if (DateTime.now().isAfter(deadline)) {
      fail('heatmap did not become idle within 60 seconds. $state');
    }
    if (_diagnostics && DateTime.now().isAfter(nextDiagnostic)) {
      debugPrint('VISUAL_E2E_HEATMAP|wait|$state');
      nextDiagnostic = DateTime.now().add(const Duration(seconds: 5));
    }
    await tester.pump();
    final exception = tester.takeException();
    if (exception != null) {
      fail('Heatmap initialization or frame failed. $state $exception');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    settledFrames = ready() ? settledFrames + 1 : 0;
  }
  await tester.pump();
}

Future<List<double>> _sampleMap(
  WidgetTester tester,
  GlobalKey key,
  Offset location,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  if (_diagnostics) debugPrint('VISUAL_E2E_HEATMAP|readback|to-image');
  final image = await _pumpCapture(tester, boundary.toImage());
  try {
    if (_diagnostics) debugPrint('VISUAL_E2E_HEATMAP|readback|to-bytes');
    final bytes = await _pumpCapture(
      tester,
      image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(bytes, isNotNull);
    final total = [0.0, 0.0, 0.0];
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final x = location.dx.round() + dx;
        final y = location.dy.round() + dy;
        expect(x, inInclusiveRange(0, image.width - 1));
        expect(y, inInclusiveRange(0, image.height - 1));
        final index = (y * image.width + x) * 4;
        for (var channel = 0; channel < 3; channel++) {
          total[channel] += bytes!.getUint8(index + channel);
        }
      }
    }

    return [for (final channel in total) channel / 25];
  } finally {
    image.dispose();
  }
}

Future<T> _pumpCapture<T>(WidgetTester tester, Future<T> capture) async {
  var completed = false;
  T? result;
  Object? error;
  StackTrace? stackTrace;
  final observed = capture
      .then<void>(
        (value) => result = value,
        onError: (Object failure, StackTrace trace) {
          error = failure;
          stackTrace = trace;
        },
      )
      .whenComplete(() => completed = true);
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!completed) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Heatmap GPU image readback did not complete within 10 seconds. '
        'lifecycle=${WidgetsBinding.instance.lifecycleState}',
      );
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  await observed;
  if (error != null) Error.throwWithStackTrace(error!, stackTrace!);

  return result as T;
}
