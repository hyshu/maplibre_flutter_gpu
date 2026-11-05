import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/command_payload.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

final _enabled =
    Platform.isAndroid &&
    const bool.fromEnvironment('MAPLIBRE_TEST_STABLE_HILLSHADE_GEOMETRY');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'hillshade full-tile geometry survives camera updates and resize',
    (tester) async {
      setVisualE2eRuntimeSceneId('hillshade');
      final style = (await loadVisualScene()).styleJson;
      final dimensions = ValueNotifier(const Size(240, 200));
      gpu.MapLibreMapController? controller;
      _GeometryFrame? latest;
      var loaded = false;
      var paintedSequence = -1;
      String? initializationError;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        dimensions.dispose();
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
                valueListenable: dimensions,
                builder: (context, size, _) => SizedBox.fromSize(
                  size: size,
                  child: gpu.MapLibreMap(
                    styleString: style,
                    initialCameraPosition: const gpu.CameraPosition(
                      target: gpu.LatLng(-0.04394530819135123, 0.0439453125),
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
                    onStyleLoadedCallback: () => loaded = true,
                    onFrame: (frame) =>
                        latest = _copyGeometryFrame(controller!, frame),
                    gpuMapRenderCallback: (context) =>
                        paintedSequence = context.frameSequence,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      Future<_GeometryFrame> settle({
        int after = -1,
        double bearing = 0,
      }) async {
        await _waitForFrame(
          tester,
          () =>
              loaded &&
              latest != null &&
              latest!.geometry.isNotEmpty &&
              latest!.frame.sequence > after &&
              latest!.frame.logicalSize == dimensions.value &&
              (latest!.frame.camera.bearing - bearing).abs() < 1e-6 &&
              paintedSequence >= latest!.frame.sequence &&
              controller!.isMapIdle,
          () =>
              'frame=${latest?.frame} painted=$paintedSequence '
              'draws=${latest?.geometry.length} error=$initializationError',
        );
        expect(latest!.geometry, hasLength(1));

        return latest!;
      }

      var current = await settle();
      // The centered viewport stays inside one canonical tile during rotation.
      // Two updates settle the drawable's initial builder-owned geometry.
      for (var update = 0; update < 2; update++) {
        final sequence = current.frame.sequence;
        expect(
          await controller!.moveCamera(
            gpu.CameraUpdate.newCameraPosition(current.frame.camera),
          ),
          isTrue,
        );
        current = await settle(after: sequence);
      }
      final baseline = current.geometry.single;
      expect(baseline.bufferId, isNot(0));
      expect(baseline.bufferVersion, greaterThan(0));
      expect(
        baseline.vertices,
        orderedEquals(
          _littleEndianWords(const [
            0,
            0,
            0,
            0,
            8192,
            0,
            8192,
            0,
            0,
            8192,
            0,
            8192,
            8192,
            8192,
            8192,
            8192,
          ]),
        ),
      );
      expect(
        baseline.indices,
        orderedEquals(_littleEndianWords(const [0, 1, 2, 1, 2, 3])),
      );

      for (var update = 0; update < 3; update++) {
        final sequence = current.frame.sequence;
        expect(
          await controller!.moveCamera(
            gpu.CameraUpdate.newCameraPosition(current.frame.camera),
          ),
          isTrue,
        );
        current = await settle(after: sequence);
        _expectStableGeometry(
          baseline,
          current.geometry.single,
          'repeat $update',
        );
      }

      final beforeRotation = current.frame.sequence;
      expect(
        await controller!.moveCamera(gpu.CameraUpdate.bearingTo(45)),
        isTrue,
      );
      current = await settle(after: beforeRotation, bearing: 45);
      final rotated = current.geometry.single;
      _expectStableGeometry(baseline, rotated, 'rotation');
      expect(
        listEquals(rotated.drawable, baseline.drawable),
        isFalse,
        reason: 'The camera matrix must follow the new bearing.',
      );

      final beforeResize = current.frame.sequence;
      dimensions.value = const Size(280, 220);
      current = await settle(after: beforeResize, bearing: 45);
      final resized = current.geometry.single;
      _expectStableGeometry(baseline, resized, 'resize');
      expect(
        listEquals(resized.drawable, rotated.drawable),
        isFalse,
        reason: 'The camera matrix must follow the new viewport.',
      );
    },
    skip: !_enabled,
  );
}

final class _GeometryFrame {
  _GeometryFrame(this.frame, this.geometry);

  final gpu.MapFrameState frame;
  final List<_CompositeGeometry> geometry;
}

final class _CompositeGeometry {
  _CompositeGeometry({
    required this.bufferId,
    required this.bufferVersion,
    required this.vertexAddress,
    required this.indexAddress,
    required this.vertices,
    required this.indices,
    required this.drawable,
  });

  final int bufferId;
  final int bufferVersion;
  final int vertexAddress;
  final int indexAddress;
  final Uint8List vertices;
  final Uint8List indices;
  final Uint8List drawable;
}

/// Copies borrowed geometry only while onFrame holds the widget's native lease.
_GeometryFrame _copyGeometryFrame(
  gpu.MapLibreMapController controller,
  gpu.MapFrameState frame,
) {
  final geometry = <_CompositeGeometry>[];
  final metadata = controller.bridge.frameGetMetadata();
  if (metadata.commands == ffi.nullptr) return _GeometryFrame(frame, geometry);
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
    int uint32(int field) => commands.getUint32(offset + field, Endian.little);
    if (uint32(DrawCommandAbi.shaderType) != ShaderType.hillshade) continue;
    expectSync(payload.read(commands, offset), isTrue);
    expectSync(uint32(DrawCommandAbi.vertexCount), 4);
    expectSync(uint32(DrawCommandAbi.vertexStride), 8);
    expectSync(uint32(DrawCommandAbi.indexCount), 6);
    expectSync(payload.drawableSize, 64);
    final vertexAddress = commands.getUint64(
      offset + DrawCommandAbi.vertexData,
      Endian.little,
    );
    final indexAddress = commands.getUint64(
      offset + DrawCommandAbi.indexData,
      Endian.little,
    );
    expectSync(vertexAddress, isNot(0));
    expectSync(indexAddress, isNot(0));
    geometry.add(
      _CompositeGeometry(
        bufferId: uint32(DrawCommandAbi.bufferId),
        bufferVersion: uint32(DrawCommandAbi.bufferVersion),
        vertexAddress: vertexAddress,
        indexAddress: indexAddress,
        vertices: Uint8List.fromList(
          ffi.Pointer<ffi.Uint8>.fromAddress(vertexAddress).asTypedList(32),
        ),
        indices: Uint8List.fromList(
          ffi.Pointer<ffi.Uint8>.fromAddress(indexAddress).asTypedList(12),
        ),
        drawable: Uint8List.fromList(
          Uint8List.sublistView(
            payload.bytes,
            payload.drawableOffset,
            payload.drawableOffset + payload.drawableSize,
          ),
        ),
      ),
    );
  }
  return _GeometryFrame(frame, geometry);
}

void _expectStableGeometry(
  _CompositeGeometry before,
  _CompositeGeometry after,
  String phase,
) {
  expect(after.bufferId, before.bufferId, reason: '$phase buffer identity');
  expect(after.bufferVersion, before.bufferVersion, reason: '$phase revision');
  expect(after.vertexAddress, before.vertexAddress, reason: '$phase vertices');
  expect(after.indexAddress, before.indexAddress, reason: '$phase indices');
  expect(after.vertices, orderedEquals(before.vertices), reason: phase);
  expect(after.indices, orderedEquals(before.indices), reason: phase);
  debugPrint(
    'HILLSHADE_GEOMETRY|$phase|buffer=${after.bufferId} '
    'version=${after.bufferVersion} vertices=${after.vertexAddress} '
    'indices=${after.indexAddress}',
  );
}

Uint8List _littleEndianWords(List<int> words) {
  final data = ByteData(words.length * 2);
  for (var index = 0; index < words.length; index++) {
    data.setUint16(index * 2, words[index], Endian.little);
  }
  return data.buffer.asUint8List();
}

Future<void> _waitForFrame(
  WidgetTester tester,
  bool Function() ready,
  String Function() diagnostic,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  var settled = 0;
  while (settled < 5) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Hillshade geometry did not settle. ${diagnostic()}');
    }
    await tester.pump();
    final exception = tester.takeException();
    if (exception != null) fail('Hillshade frame failed. $exception');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    settled = ready() ? settled + 1 : 0;
  }
}
