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

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';

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

  test('struct sizes match the FFI contract', () {
    // These are the sizes the Dart FFI readers assume; the C++ side pins them
    // with static_assert(sizeof(...) == N).
    expect(DrawCommandAbi.size, 400);
    expect(DrawCommandAbi.texFilter, 384);
    expect(DrawCommandAbi.subLayerIndex, 388);
    expect(DrawCommandAbi.stencilReference, 392);
    expect(DrawCommandAbi.stencilMode, 396);
    expect(LabelExportAbi.size, 488);
    expect(LabelExportAbi.crossTileID, 120);
    expect(LabelExportAbi.textOffsetX, 380);
    expect(LabelExportAbi.iconOffsetY, 392);
    expect(LabelExportAbi.textOpacity, 396);
    expect(LabelExportAbi.textFont, 416);
  });
}
