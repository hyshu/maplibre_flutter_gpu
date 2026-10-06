import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

const _diagnostics = bool.fromEnvironment('HILLSHADE_DIAGNOSTICS');
const _properties = gpu.HillshadeLayerProperties(
  hillshadeExaggeration: 0.5,
  hillshadeIlluminationDirection: 270,
  hillshadeIlluminationAltitude: 45,
  hillshadeIlluminationAnchor: 'map',
  hillshadeAccentColor: 'rgba(0,0,0,0)',
  hillshadeShadowColor: '#000000',
  hillshadeHighlightColor: '#ffffff',
  hillshadeMethod: 'standard',
  visibility: 'visible',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'hillshade preserves DEM, lighting, and shared-source lifecycle',
    (tester) async {
      setVisualE2eRuntimeSceneId('hillshade');
      final style = (await loadVisualScene()).styleJson;
      final size = ValueNotifier(const Size(480, 400));
      final boundaryKey = GlobalKey();
      gpu.MapLibreMapController? controller;
      var styleLoads = 0;
      String? initializationError;
      final center = _tilePoint(128, 128);
      final west = _tilePoint(64, 96);
      final east = _tilePoint(192, 96);
      final flat = _tilePoint(128, 96);
      final south = _tilePoint(128, 192);

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
                      initialCameraPosition: gpu.CameraPosition(
                        target: center,
                        zoom: 12,
                      ),
                      compassEnabled: false,
                      logoEnabled: false,
                      attributionButtonEnabled: false,
                      scaleControlEnabled: false,
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

      Future<void> idle() => _waitForMap(
        tester,
        () => styleLoads > 0 && controller!.isMapIdle,
        () =>
            'styleLoads=$styleLoads initialized=${controller != null} '
            'error=$initializationError',
      );

      Future<void> verify(
        gpu.LatLng point,
        List<double> expected,
        String phase, {
        double tolerance = 12,
      }) async {
        final actual = await _sampleMap(
          tester,
          boundaryKey,
          controller!.toScreenOffset(point),
        );
        if (_diagnostics) debugPrint('VISUAL_E2E_HILLSHADE|$phase|$actual');
        if ([0, 1, 2].any(
          (channel) => (actual[channel] - expected[channel]).abs() > tolerance,
        )) {
          await _writeFailureImage(tester, boundaryKey, phase);
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

      Future<void> verifySlopes(String phase) async {
        // The 20 m/pixel ramp at z12 encodes a slope of approximately 0.98.
        // Standard shading blends black or white at sin(atan(0.625 * 0.98)).
        await verify(west, [195, 195, 195], '$phase west slope');
        await verify(east, [61, 61, 61], '$phase east slope');
        await verify(
          flat,
          [128, 128, 128],
          '$phase flat plateau',
          tolerance: 8,
        );
      }

      Future<void> paint(gpu.HillshadeLayerProperties changes) async {
        await controller!.setLayerProperties(
          'terrain',
          _properties.copyWith(changes),
        );
        await idle();
      }

      Future<void> replaceStyle(String replacement) async {
        final before = styleLoads;
        await controller!.setStyle(replacement);
        await _waitForMap(
          tester,
          () => styleLoads > before && controller!.isMapIdle,
          () => 'reload count=$styleLoads previous=$before',
        );
      }

      await idle();
      await verifySlopes('initial Mapbox DEM');

      await paint(
        const gpu.HillshadeLayerProperties(hillshadeIlluminationDirection: 90),
      );
      await verify(west, [61, 61, 61], 'reverse light west');
      await verify(east, [195, 195, 195], 'reverse light east');
      await paint(
        const gpu.HillshadeLayerProperties(hillshadeIlluminationDirection: 0),
      );
      await verify(south, [
        177,
        177,
        177,
      ], 'south ramp keeps vertical orientation');
      await verify(
        flat,
        [128, 128, 128],
        'north plateau stays flat',
        tolerance: 8,
      );

      for (final (method, bright, dark) in const [
        ('standard', 195.0, 61.0),
        ('basic', 255.0, 2.0),
        ('combined', 191.0, 65.0),
        ('igor', 191.0, 65.0),
      ]) {
        await paint(gpu.HillshadeLayerProperties(hillshadeMethod: method));
        await verify(west, [bright, bright, bright], '$method west slope');
        await verify(east, [dark, dark, dark], '$method east slope');
      }
      await paint(
        const gpu.HillshadeLayerProperties(
          hillshadeMethod: 'multidirectional',
          hillshadeIlluminationDirection: [270, 90, 270, 90],
          hillshadeIlluminationAltitude: [45, 45, 45, 45],
          hillshadeShadowColor: ['black', 'black', 'black', 'black'],
          hillshadeHighlightColor: ['red', 'blue', '#00ff00', 'yellow'],
        ),
      );
      await verify(west, [65, 65, 1], 'four lights west');
      await verify(east, [65, 65, 65], 'four lights east');

      await paint(
        const gpu.HillshadeLayerProperties(
          hillshadeIlluminationAnchor: 'viewport',
        ),
      );
      await verify(west, [195, 195, 195], 'viewport light before rotation');
      await controller!.moveCamera(gpu.CameraUpdate.bearingTo(180));
      await idle();
      await verify(west, [61, 61, 61], 'viewport light follows bearing');
      await paint(
        const gpu.HillshadeLayerProperties(hillshadeIlluminationAnchor: 'map'),
      );
      await verify(west, [195, 195, 195], 'map light ignores bearing');
      await controller!.moveCamera(gpu.CameraUpdate.bearingTo(0));
      await idle();

      await paint(const gpu.HillshadeLayerProperties(hillshadeExaggeration: 0));
      await verify(
        west,
        [128, 128, 128],
        'zero exaggeration clears terrain',
        tolerance: 8,
      );
      await paint(
        const gpu.HillshadeLayerProperties(hillshadeExaggeration: 0.5),
      );
      await verifySlopes('restored exaggeration');

      await controller!.removeLayer('terrain');
      await idle();
      await verify(west, [128, 128, 128], 'removed hillshade', tolerance: 8);
      await controller!.addHillshadeLayer('terrain', 'terrain', _properties);
      await idle();
      await verifySlopes('re-added hillshade');

      await controller!.addHillshadeLayer(
        'terrain',
        'terrain-overlay',
        _properties.copyWith(
          const gpu.HillshadeLayerProperties(
            hillshadeHighlightColor: '#ff0000',
            hillshadeShadowColor: '#ff0000',
          ),
        ),
      );
      await idle();
      await verify(west, [226, 93, 93], 'two layers share the DEM');
      await paint(const gpu.HillshadeLayerProperties(visibility: 'none'));
      await verify(west, [
        195,
        61,
        61,
      ], 'shared DEM survives first layer hidden');
      await controller!.removeLayer('terrain-overlay');
      await idle();
      await verify(west, [128, 128, 128], 'all hillshade hidden', tolerance: 8);
      await paint(const gpu.HillshadeLayerProperties(visibility: 'visible'));
      await verifySlopes('shared DEM restored');

      await replaceStyle(
        '{"version":8,"sources":{},"layers":['
        '{"id":"background","type":"background",'
        '"paint":{"background-color":"#808080"}}]}',
      );
      await verify(
        west,
        [128, 128, 128],
        'style without terrain',
        tolerance: 8,
      );
      await replaceStyle(style);
      await verifySlopes('reloaded terrain style');

      final mixed = jsonDecode(style) as Map<String, dynamic>;
      mixed['sources']['density'] = {
        'type': 'geojson',
        'data': {
          'type': 'Feature',
          'properties': <String, Object>{},
          'geometry': {
            'type': 'Point',
            'coordinates': [west.longitude, west.latitude],
          },
        },
      };
      (mixed['layers'] as List<dynamic>).add({
        'id': 'density',
        'type': 'heatmap',
        'source': 'density',
        'paint': {
          'heatmap-radius': 56,
          'heatmap-weight': 4,
          'heatmap-intensity': 1,
          'heatmap-opacity': 0.5,
          'heatmap-color': [
            'interpolate',
            ['linear'],
            ['heatmap-density'],
            0,
            'rgba(255,0,255,0)',
            0.01,
            '#ff00ff',
            1,
            '#ff00ff',
          ],
        },
      });
      await replaceStyle(jsonEncode(mixed));
      _verifyMixedPasses(controller!);
      await verify(west, [225, 97, 225], 'heatmap above hillshade');
      await verify(east, [61, 61, 61], 'hillshade outside heatmap');
      await replaceStyle(style);
      await verifySlopes('removed mixed heatmap');

      final terrarium = jsonDecode(style) as Map<String, dynamic>;
      terrarium['sources']['terrain']['encoding'] = 'terrarium';
      terrarium['sources']['terrain']['tiles'] = [
        (terrarium['sources']['terrain']['tiles'][0] as String).replaceFirst(
          '/dem/mapbox/',
          '/dem/terrarium/',
        ),
      ];
      await replaceStyle(jsonEncode(terrarium));
      await verifySlopes('Terrarium DEM');

      for (final dimensions in [const Size(400, 360), const Size(600, 440)]) {
        size.value = dimensions;
        await idle();
        await verifySlopes('resize $dimensions');
      }
      await controller!.moveCamera(
        gpu.CameraUpdate.newLatLngZoom(_tilePoint(136, 120), 12.2),
      );
      await idle();
      await verifySlopes('pan and overzoom');
    },
  );
}

void _verifyMixedPasses(gpu.MapLibreMapController controller) {
  final bridge = controller.bridge;
  final snapshot = bridge.supportsAsyncRendering
      ? bridge.acquireFrameSnapshot()
      : null;
  try {
    if (bridge.supportsAsyncRendering) expect(snapshot, isNotNull);
    final metadata = bridge.frameGetMetadata();
    expect(metadata.commands, isNot(ffi.nullptr));
    final bytes = metadata.commands.cast<ffi.Uint8>().asTypedList(
      metadata.commandCount * metadata.commandStride,
    );
    final data = ByteData.sublistView(bytes);
    final shaders = <int>{};
    final targetFormats = <int>{};
    for (var index = 0; index < metadata.commandCount; index++) {
      final offset = index * metadata.commandStride;
      final shader = data.getUint32(
        offset + DrawCommandAbi.shaderType,
        Endian.little,
      );
      shaders.add(shader);
      if (shader == ShaderType.renderTarget &&
          data.getUint32(
                offset + DrawCommandAbi.renderTargetId,
                Endian.little,
              ) !=
              0) {
        final flags = data.getUint32(
          offset + DrawCommandAbi.flags,
          Endian.little,
        );
        targetFormats.add(flags & DrawCommandFlags.renderTargetRgba8);
      }
    }
    expect(
      shaders,
      containsAll([
        ShaderType.heatmap,
        ShaderType.heatmapTexture,
        ShaderType.hillshadePrepare,
        ShaderType.hillshade,
      ]),
    );
    expect(targetFormats, {0, DrawCommandFlags.renderTargetRgba8});
  } finally {
    snapshot?.release();
  }
}

gpu.LatLng _tilePoint(double x, double y) {
  final longitude = (2048 + x / 256) / 4096 * 360 - 180;
  final mercator = math.pi * (1 - 2 * (2048 + y / 256) / 4096);
  final latitude =
      math.atan((math.exp(mercator) - math.exp(-mercator)) / 2) * 180 / math.pi;

  return gpu.LatLng(latitude, longitude);
}

Future<void> _waitForMap(
  WidgetTester tester,
  bool Function() ready,
  String Function() diagnosticState,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  var settledFrames = 0;
  while (settledFrames < 5) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Hillshade did not become idle within 60 seconds. ${diagnosticState()}',
      );
    }
    await tester.pump();
    final exception = tester.takeException();
    if (exception != null) fail('Hillshade frame failed. $exception');
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
  final image = await _pumpCapture(tester, boundary.toImage());
  try {
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
    '${root.path}/build/hillshade-validation/lifecycle/'
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
    debugPrint('VISUAL_E2E_HILLSHADE|$phase|failure-image|${file.path}');
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
      fail('Hillshade GPU image readback did not complete within 10 seconds.');
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  await observed;
  if (error != null) Error.throwWithStackTrace(error!, stackTrace!);

  return result as T;
}
