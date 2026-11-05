import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/native/command_payload.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

const _diagnostics = bool.fromEnvironment('HILLSHADE_DIAGNOSTICS');
final _cacheRegressionsEnabled =
    Platform.isAndroid &&
    const bool.fromEnvironment(
      'MAPLIBRE_CACHE_HILLSHADE_PREPARATION',
      defaultValue: true,
    );
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
      var paintedSequence = -1;
      var captureMixedPasses = false;
      _MixedPassSnapshot? mixedPasses;
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
                      onFrame: (frame) {
                        if (captureMixedPasses) {
                          mixedPasses = _copyMixedPasses(
                            controller!,
                            frame.sequence,
                          );
                        }
                      },
                      gpuMapRenderCallback: _cacheRegressionsEnabled
                          ? (context) => paintedSequence = context.frameSequence
                          : null,
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

      if (_cacheRegressionsEnabled) {
        final sequenceBeforePressure = controller!.frameState!.sequence;
        WidgetsBinding.instance.handleMemoryPressure();
        await controller!.moveCamera(gpu.CameraUpdate.bearingTo(90));
        await _waitForMap(
          tester,
          () =>
              controller!.isMapIdle &&
              controller!.frameState!.sequence > sequenceBeforePressure &&
              (controller!.frameState!.camera.bearing - 90).abs() < 1e-6 &&
              paintedSequence > sequenceBeforePressure,
          () =>
              'memory pressure frame=${controller!.frameState} '
              'painted=$paintedSequence previous=$sequenceBeforePressure',
        );
        // Rotated sample positions reject an unchanged retained map image.
        await verifySlopes('memory pressure with rotated camera');
        await controller!.moveCamera(gpu.CameraUpdate.bearingTo(0));
        await idle();
        await verifySlopes('memory pressure restored camera');
      }

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
      final beforeMixedSequence = controller!.frameState!.sequence;
      captureMixedPasses = true;
      await replaceStyle(jsonEncode(mixed));
      captureMixedPasses = false;
      expect(mixedPasses, isNotNull);
      expect(mixedPasses!.sequence, greaterThan(beforeMixedSequence));
      _verifyMixedPasses(mixedPasses!);
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

  testWidgets('hillshade preparation follows delayed DEM neighbor backfill', (
    tester,
  ) async {
    final server = await _DelayedDemServer.start(tester);
    final boundaryKey = GlobalKey();
    final preparations = _WestPreparationObserver();
    gpu.MapLibreMapController? controller;
    var styleLoads = 0;
    var paintedSequence = -1;
    String? initializationError;
    addTearDown(() async {
      server.releaseNeighbor();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await server.close();
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2),
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 320,
                height: 300,
                child: gpu.MapLibreMap(
                  styleString: server.style('held'),
                  initialCameraPosition: gpu.CameraPosition(
                    target: _tilePoint(0, 128),
                    zoom: 12,
                  ),
                  compassEnabled: false,
                  logoEnabled: false,
                  attributionButtonEnabled: false,
                  scaleControlEnabled: false,
                  loadingBuilder: null,
                  errorBuilder: (context, error) {
                    initializationError = error;

                    return Text(error);
                  },
                  onMapCreated: (value) => controller = value,
                  onStyleLoadedCallback: () => styleLoads++,
                  onFrame: (frame) =>
                      preparations.capture(controller!, frame.sequence),
                  gpuMapRenderCallback: (context) =>
                      paintedSequence = context.frameSequence,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _waitForMap(
      tester,
      () =>
          styleLoads > 0 &&
          controller?.frameState != null &&
          server.neighborRequested,
      () =>
          'neighbor requested=${server.neighborRequested} '
          'styles=$styleLoads error=$initializationError',
    );
    final isolated = await _waitForWestPreparation(
      tester,
      controller!,
      preparations,
      (input) => input.rightBorderGreen == 80,
    );
    final isolatedSequence = isolated.sequence;
    await _waitForMap(
      tester,
      () => paintedSequence >= isolatedSequence,
      () => 'isolated frame=$isolatedSequence painted=$paintedSequence',
    );
    final edge = controller!.toScreenOffset(_tilePoint(0, 128));
    final texelWidth =
        edge.dx - controller!.toScreenOffset(_tilePoint(-8, 128)).dx;
    final crop = Rect.fromLTRB(
      (edge.dx - texelWidth).ceilToDouble(),
      (edge.dy - 24).ceilToDouble(),
      (edge.dx - 2).floorToDouble(),
      (edge.dy + 24).floorToDouble(),
    );
    final before = await _captureOpaqueCrop(tester, boundaryKey, crop);
    final beforeSequence = controller!.frameState!.sequence;

    server.releaseNeighbor();
    final updated = await _waitForWestPreparation(
      tester,
      controller!,
      preparations,
      (input) =>
          input.targetId != isolated.targetId &&
          input.textureId != isolated.textureId &&
          input.rightBorderGreen == 90,
    );
    expect(updated.interior, orderedEquals(isolated.interior));
    await _waitForMap(
      tester,
      () =>
          controller!.isMapIdle &&
          controller!.frameState!.sequence > beforeSequence &&
          paintedSequence > beforeSequence &&
          paintedSequence >= updated.sequence,
      () =>
          'neighbor frame=${controller!.frameState} '
          'painted=$paintedSequence previous=$beforeSequence',
    );
    final after = await _captureOpaqueCrop(tester, boundaryKey, crop);
    final changed = _changedRgbPixels(before, after, tolerance: 2);
    if (changed == 0) {
      await _writeFailureImage(tester, boundaryKey, 'neighbor backfill');
    }
    expect(
      changed,
      greaterThan(after.length ~/ 4 ~/ 4),
      reason: 'The west border must visibly respond to the eastern DEM.',
    );

    // A distinct intervening frame prevents retained terrain becoming the oracle.
    final emptyLoads = styleLoads;
    final emptySequence = controller!.frameState!.sequence;
    await controller!.setStyle(
      '{"version":8,"sources":{},"layers":[{"id":"background",'
      '"type":"background","paint":{"background-color":"#203040"}}]}',
    );
    await _waitForMap(
      tester,
      () =>
          styleLoads > emptyLoads &&
          controller!.isMapIdle &&
          controller!.frameState!.sequence > emptySequence &&
          paintedSequence > emptySequence,
      () =>
          'empty styles=$styleLoads frame=${controller!.frameState} '
          'painted=$paintedSequence previous=$emptySequence',
    );
    final cleared = await _captureOpaqueCrop(tester, boundaryKey, crop);
    for (var offset = 0; offset < cleared.length; offset += 4) {
      for (var channel = 0; channel < 3; channel++) {
        expect(cleared[offset + channel], closeTo([32, 48, 64][channel], 1));
      }
    }

    final previousLoads = styleLoads;
    final previousSequence = controller!.frameState!.sequence;
    await controller!.setStyle(server.style('fresh'));
    await _waitForMap(
      tester,
      () =>
          styleLoads > previousLoads &&
          controller!.isMapIdle &&
          controller!.frameState!.sequence > previousSequence &&
          paintedSequence > previousSequence,
      () =>
          'fresh styles=$styleLoads frame=${controller!.frameState} '
          'painted=$paintedSequence previous=$previousSequence',
    );
    final fresh = await _waitForWestPreparation(
      tester,
      controller!,
      preparations,
      (input) =>
          input.targetId != updated.targetId &&
          input.textureId != updated.textureId &&
          input.rightBorderGreen == 90,
    );
    expect(fresh.pixels, orderedEquals(updated.pixels));
    await _waitForMap(
      tester,
      () => paintedSequence >= fresh.sequence,
      () => 'fresh adopted=${fresh.sequence} painted=$paintedSequence',
    );
    final baseline = await _captureOpaqueCrop(tester, boundaryKey, crop);
    expect(
      _changedRgbPixels(after, baseline, tolerance: 2),
      0,
      reason: 'Backfilled output must match a fresh preparation.',
    );
    expect(tester.takeException(), isNull);
  }, skip: !_cacheRegressionsEnabled);
}

final class _MixedPassSnapshot {
  _MixedPassSnapshot(this.sequence, this.shaders, this.targetFormats);

  final int sequence;
  final Set<int> shaders;
  final Set<int> targetFormats;
}

/// Copies command identities during onFrame without consuming another snapshot.
_MixedPassSnapshot? _copyMixedPasses(
  gpu.MapLibreMapController controller,
  int sequence,
) {
  final metadata = controller.bridge.frameGetMetadata();
  if (metadata.commands == ffi.nullptr) return null;
  final bytes = metadata.commands.cast<ffi.Uint8>().asTypedList(
    metadata.commandCount * metadata.commandStride,
  );
  final data = ByteData.sublistView(bytes);
  final payload = CommandPayloadReader(
    metadata.payload == ffi.nullptr
        ? Uint8List(0)
        : metadata.payload.cast<ffi.Uint8>().asTypedList(metadata.payloadSize),
  );
  final shaders = <int>{};
  final targetFormats = <int>{};
  for (var index = 0; index < metadata.commandCount; index++) {
    final offset = index * metadata.commandStride;
    expectSync(payload.read(data, offset), isTrue);
    final shader = data.getUint32(
      offset + DrawCommandAbi.shaderType,
      Endian.little,
    );
    shaders.add(shader);
    if (shader == ShaderType.renderTarget && payload.renderTargetId != 0) {
      final flags = data.getUint32(
        offset + DrawCommandAbi.flags,
        Endian.little,
      );
      targetFormats.add(flags & DrawCommandFlags.renderTargetRgba8);
    }
  }
  return _MixedPassSnapshot(sequence, shaders, targetFormats);
}

void _verifyMixedPasses(_MixedPassSnapshot snapshot) {
  expect(
    snapshot.shaders,
    containsAll([
      ShaderType.heatmap,
      ShaderType.heatmapTexture,
      ShaderType.hillshadePrepare,
      ShaderType.hillshade,
    ]),
  );
  expect(snapshot.targetFormats, {0, DrawCommandFlags.renderTargetRgba8});
}

final class _DelayedDemServer {
  _DelayedDemServer(this._server, this._west, this._east);

  final HttpServer _server;
  final Uint8List _west;
  final Uint8List _east;
  final _neighbor = Completer<void>();
  final _handlers = <Future<void>>{};
  final _errors = <({Object error, StackTrace stack})>[];
  late final StreamSubscription<HttpRequest> _requests;
  var neighborRequested = false;
  var _closed = false;

  static Future<_DelayedDemServer> start(WidgetTester tester) async {
    final west = await _demPng(tester, 80);
    final east = await _demPng(tester, 90);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _DelayedDemServer(server, west, east);
    fixture._requests = server.listen(fixture._accept);

    return fixture;
  }

  void _accept(HttpRequest request) {
    late final Future<void> handler;
    handler = _serve(request)
        .catchError((Object error, StackTrace stack) {
          _errors.add((error: error, stack: stack));
        })
        .whenComplete(() => _handlers.remove(handler));
    _handlers.add(handler);
  }

  Future<void> _serve(HttpRequest request) async {
    try {
      final match = RegExp(r'^/(held|fresh)/12/(\d+)/(\d+)\.png$')
          .firstMatch(request.uri.path);
      final x = match == null ? null : int.tryParse(match.group(2)!);
      final y = match == null ? null : int.tryParse(match.group(3)!);
      if (x == null || y == null || x >= 4096 || y >= 4096) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();

        return;
      }
      final eastern = x >= 2048;
      if (eastern && match!.group(1) == 'held') {
        neighborRequested = true;
        await _neighbor.future;
      }
      if (_closed) return;
      final bytes = eastern ? _east : _west;
      request.response.headers
        ..contentType = ContentType('image', 'png')
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    } on SocketException {
      // Style replacement and teardown can cancel an in-flight tile request.
    }
  }

  void releaseNeighbor() {
    if (!_neighbor.isCompleted) _neighbor.complete();
  }

  Future<void> close() async {
    _closed = true;
    releaseNeighbor();
    try {
      await _server.close(force: true).timeout(const Duration(seconds: 5));
      await _requests.cancel().timeout(const Duration(seconds: 5));
      await Future.wait(_handlers.toList()).timeout(const Duration(seconds: 5));
    } finally {
      expect(_errors, isEmpty, reason: 'Unexpected DEM server failures.');
    }
  }

  String style(String namespace) => jsonEncode({
    'version': 8,
    'transition': {'duration': 0, 'delay': 0},
    'sources': {
      'dem': {
        'type': 'raster-dem',
        'tiles': [
          'http://127.0.0.1:${_server.port}/$namespace/{z}/{x}/{y}.png',
        ],
        'tileSize': 256,
        'minzoom': 12,
        'maxzoom': 12,
        'encoding': 'mapbox',
      },
    },
    'layers': [
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': '#808080'},
      },
      {
        'id': 'terrain',
        'type': 'hillshade',
        'source': 'dem',
        'paint': {
          'hillshade-exaggeration': 0.5,
          'hillshade-illumination-direction': 270,
          'hillshade-illumination-altitude': 45,
          'hillshade-illumination-anchor': 'map',
          'hillshade-accent-color': 'rgba(0,0,0,0)',
          'hillshade-shadow-color': '#000000',
          'hillshade-highlight-color': '#ffffff',
          'hillshade-method': 'standard',
        },
      },
    ],
  });
}

Future<Uint8List> _demPng(WidgetTester tester, int green) async {
  final rgba = Uint8List(32 * 32 * 4);
  for (var offset = 0; offset < rgba.length; offset += 4) {
    rgba[offset] = 1;
    rgba[offset + 1] = green;
    rgba[offset + 3] = 255;
  }
  final decoded = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    32,
    32,
    ui.PixelFormat.rgba8888,
    decoded.complete,
  );
  final image = await _pumpCapture(tester, decoded.future);
  try {
    final png = await _pumpCapture(
      tester,
      image.toByteData(format: ui.ImageByteFormat.png),
    );
    expect(png, isNotNull);

    return Uint8List.fromList(
      png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
}

final class _WestPreparation {
  _WestPreparation(this.sequence, this.targetId, this.textureId, this.pixels);

  final int sequence;
  final int targetId;
  final int textureId;
  final Uint8List pixels;

  int get rightBorderGreen => pixels[(34 * 17 + 33) * 4 + 1];

  Uint8List get interior => Uint8List.fromList([
    for (var y = 1; y <= 32; y++)
      for (var x = 1; x <= 32; x++)
        for (var channel = 0; channel < 4; channel++)
          pixels[(y * 34 + x) * 4 + channel],
  ]);

  bool sameInput(_WestPreparation? other) =>
      other != null &&
      targetId == other.targetId &&
      textureId == other.textureId &&
      listEquals(pixels, other.pixels);
}

final class _WestPreparationObserver {
  _WestPreparation? latest;
  var stableSnapshots = 0;

  void capture(gpu.MapLibreMapController controller, int sequence) {
    final input = _copyWestPreparation(controller, sequence);
    if (input == null) {
      latest = null;
      stableSnapshots = 0;

      return;
    }
    stableSnapshots = input.sameInput(latest) ? stableSnapshots + 1 : 1;
    latest = input;
  }
}

/// Called synchronously from onFrame while the widget pins the native snapshot.
_WestPreparation? _copyWestPreparation(
  gpu.MapLibreMapController controller,
  int sequence,
) {
  final metadata = controller.bridge.frameGetMetadata();
  if (metadata.commands == ffi.nullptr) return null;
  final commands = ByteData.sublistView(
    metadata.commands.cast<ffi.Uint8>().asTypedList(
      metadata.commandCount * metadata.commandStride,
    ),
  );
  final payload = CommandPayloadReader(
    metadata.payload == ffi.nullptr
        ? Uint8List(0)
        : metadata.payload.cast<ffi.Uint8>().asTypedList(metadata.payloadSize),
  );
  for (var index = 0; index < metadata.commandCount; index++) {
    final offset = index * metadata.commandStride;
    if (commands.getUint32(offset + DrawCommandAbi.shaderType, Endian.little) !=
        ShaderType.hillshadePrepare) {
      continue;
    }
    expectSync(payload.read(commands, offset), isTrue);
    expectSync(payload.textureWidth, 34);
    expectSync(payload.textureHeight, 34);
    expectSync(payload.textureChannels, 4);
    expectSync(payload.textureAddress, isNot(0));
    final pixels = ffi.Pointer<ffi.Uint8>.fromAddress(payload.textureAddress)
        .asTypedList(34 * 34 * 4);
    if (pixels[(34 + 1) * 4 + 1] != 80) continue;
    expectSync(payload.renderTargetId, isNot(0));
    expectSync(payload.textureId, isNot(0));

    // Only owned bytes and scalar identities outlive the native lease.
    return _WestPreparation(
      sequence,
      payload.renderTargetId,
      payload.textureId,
      Uint8List.fromList(pixels),
    );
  }
  return null;
}

Future<_WestPreparation> _waitForWestPreparation(
  WidgetTester tester,
  gpu.MapLibreMapController controller,
  _WestPreparationObserver observer,
  bool Function(_WestPreparation) ready,
) async {
  String diagnostic() =>
      'west target=${observer.latest?.targetId} '
      'input=${observer.latest?.textureId} '
      'rightBorder=${observer.latest?.rightBorderGreen} '
      'sequence=${observer.latest?.sequence} stable=${observer.stableSnapshots}';
  await _waitForMap(
    tester,
    () => observer.latest != null && ready(observer.latest!),
    diagnostic,
  );
  final firstSequence = observer.latest!.sequence;
  // An idle map may otherwise stop after publishing its first matching frame.
  final accepted = await controller.moveCamera(
    gpu.CameraUpdate.newCameraPosition(controller.frameState!.camera),
  );
  expect(accepted, isTrue);
  await _waitForMap(
    tester,
    () =>
        observer.latest != null &&
        observer.latest!.sequence > firstSequence &&
        observer.stableSnapshots >= 2 &&
        ready(observer.latest!),
    diagnostic,
  );

  return observer.latest!;
}

Future<Uint8List> _captureOpaqueCrop(
  WidgetTester tester,
  GlobalKey key,
  Rect crop,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await _pumpCapture(tester, boundary.toImage());
  try {
    expect(crop.left, greaterThanOrEqualTo(0));
    expect(crop.top, greaterThanOrEqualTo(0));
    expect(crop.right, lessThanOrEqualTo(image.width));
    expect(crop.bottom, lessThanOrEqualTo(image.height));
    expect(crop.width, greaterThan(0));
    final data = await _pumpCapture(
      tester,
      image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(data, isNotNull);
    final pixels = Uint8List(crop.width.toInt() * crop.height.toInt() * 4);
    var destination = 0;
    for (var y = crop.top.toInt(); y < crop.bottom; y++) {
      for (var x = crop.left.toInt(); x < crop.right; x++) {
        final source = (y * image.width + x) * 4;
        expect(data!.getUint8(source + 3), 255);
        for (var channel = 0; channel < 4; channel++) {
          pixels[destination++] = data.getUint8(source + channel);
        }
      }
    }
    return pixels;
  } finally {
    image.dispose();
  }
}

int _changedRgbPixels(Uint8List before, Uint8List after, {int tolerance = 0}) {
  expect(after.length, before.length);
  var changed = 0;
  for (var offset = 0; offset < before.length; offset += 4) {
    if ([0, 1, 2].any(
      (channel) =>
          (before[offset + channel] - after[offset + channel]).abs() >
          tolerance,
    )) {
      changed++;
    }
  }
  return changed;
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
        'Hillshade did not reach the expected frame state within 60 seconds. '
        '${diagnosticState()}',
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
