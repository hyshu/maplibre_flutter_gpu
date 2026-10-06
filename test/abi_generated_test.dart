// Guards the FFI ABI single-source-of-truth pipeline:
//
//   C++ COMMAND_EXPORT_ABI_OFFSET locks  →  tool/gen_abi.dart  →  abi_generated.dart
//
// If someone changes a DrawCommand / LabelExport field on the C++ side and
// forgets to regenerate, `dart run tool/gen_abi.dart` would produce output
// that differs from the committed file — this test fails and tells them to
// regenerate. Combined with the compiler-verified offsetof asserts, the
// Dart-side offsets can never silently drift from the C++ structs.

import 'dart:io';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/signatures.dart';

import '../tool/gen_abi.dart' as gen;

void main() {
  test('abi_generated.dart is in sync with the C++ ABI locks', () {
    final committed = File('lib/src/native/abi_generated.dart')
        .readAsStringSync();
    final regenerated = gen.generateAbiDart();
    expect(
      regenerated,
      committed,
      reason:
          'lib/src/native/abi_generated.dart is stale. '
          'Run: dart run tool/gen_abi.dart',
    );
  });

  test('frame metadata extends the stable prefix with an aligned arena', () {
    expect(sizeOf<NativeFrameMetadata>(), 56);
    final metadata = calloc<NativeFrameMetadata>();
    addTearDown(() => calloc.free(metadata));
    metadata.ref
      ..commands = Pointer.fromAddress(0x1122334455)
      ..commandCount = 7
      ..commandStride = DrawCommandAbi.size
      ..hasClearColor = 1
      ..payload = Pointer.fromAddress(0x6677889900)
      ..payloadSize = 1234;
    final bytes = ByteData.sublistView(metadata.cast<Uint8>().asTypedList(56));
    expect(bytes.getUint64(0, .little), 0x1122334455);
    expect(bytes.getUint32(8, .little), 7);
    expect(bytes.getUint32(12, .little), 64);
    expect(bytes.getUint32(32, .little), 1);
    expect(bytes.getUint64(40, .little), 0x6677889900);
    expect(bytes.getUint32(48, .little), 1234);
  });

  test('struct sizes match the FFI contract', () {
    // These are the sizes the Dart FFI readers assume; the C++ side pins them
    // with static_assert(sizeof(...) == N).
    expect(DrawCommandAbi.size, 64);
    expect(DrawCommandAbi.subLayerIndex, 52);
    expect(DrawCommandAbi.payloadOffset, 56);
    expect(DrawCommandAbi.payloadSize, 60);
    expect(CommandPayloadHeaderAbi.size, 8);
    expect(CommandTextureAbi.size, 32);
    expect(CommandTextureAbi.filter, 28);
    expect(CommandStencilAbi.size, 8);
    expect(CommandStencilAbi.reference, 0);
    expect(CommandStencilAbi.mode, 4);
    expect(CommandRenderTargetAbi.size, 12);
    expect(CommandRenderTargetAbi.id, 0);
    expect(CommandRenderTargetAbi.width, 4);
    expect(CommandRenderTargetAbi.height, 8);
    expect(LabelExportAbi.size, 352);
    expect(LabelExportAbi.crossTileID, 120);
    expect(LabelExportAbi.textOffset, 124);
    expect(LabelExportAbi.textFontsOffset, 148);
    expect(LabelExportAbi.textSectionsOffset, 156);
    expect(LabelExportAbi.textPathOffset, 164);
    expect(LabelExportAbi.textOffsetX, 180);
    expect(LabelExportAbi.iconOffsetY, 192);
    expect(LabelExportAbi.textOpacity, 196);
    expect(LabelExportAbi.layerIndex, 308);
    expect(LabelExportAbi.renderGroup, 320);
    expect(LabelExportAbi.renderOrder, 324);
    expect(LabelExportAbi.logicalTextOffset, 328);
    expect(LabelExportAbi.logicalTextLength, 332);
    expect(LabelExportAbi.visualTextSectionsOffset, 336);
    expect(LabelExportAbi.visualTextSectionCount, 340);
    expect(LabelExportAbi.tileWrap, 344);
    expect(LabelStaticExportAbi.size, 200);
    expect(LabelStaticExportAbi.crossTileID, 64);
    expect(LabelStaticExportAbi.textOffset, 68);
    expect(LabelStaticExportAbi.layerIndex, 168);
    expect(LabelStaticExportAbi.logicalTextOffset, 184);
    expect(LabelStaticExportAbi.visualTextSectionCount, 196);
    expect(LabelDynamicExportAbi.size, 152);
    expect(LabelDynamicExportAbi.flags, 48);
    expect(LabelDynamicExportAbi.textPathOffset, 56);
    expect(LabelDynamicExportAbi.textTransformXX, 108);
    expect(LabelDynamicExportAbi.renderOrder, 140);
    expect(LabelDynamicExportAbi.staticIndex, 144);
    expect(LabelDynamicExportAbi.tileWrap, 148);
    expect(LabelStringRefExportAbi.size, 8);
    expect(LabelTextSectionExportAbi.size, 48);
    expect(LabelPathPointExportAbi.size, 8);
  });
}
