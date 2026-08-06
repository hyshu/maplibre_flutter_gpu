import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';

void main() {
  // The C++ side is only reachable as text from Dart, so its half of the
  // contract stays a source assertion.
  test('native merges into a plain float2 vertex', () {
    final native = File('native/src/bridge_merge.cpp').readAsStringSync();

    expect(native, contains('struct MergedVertex'));
    expect(native, contains('float x;'));
    expect(native, contains('float y;'));
    expect(native, contains('std::vector<std::vector<MergedVertex>>'));
    expect(native, contains('merged.vertexStride = sizeof(MergedVertex)'));
  });

  test('only non-data-driven fill and background are eligible to merge', () {
    final native = File('native/src/bridge_merge.cpp').readAsStringSync();

    // Anything else `continue`s out of the grouping pass, and a merged command
    // has its flags reset to CrossTileMerged alone. Both facts are what let
    // the Dart side assume a bare float2 layout below.
    expect(native, contains('if (cmd.shaderType == ShaderType::Fill) {'));
    expect(
      native,
      contains(
        'if ((cmd.flags & DrawCommandFlags::FillDataDrivenMask) != 0) continue;',
      ),
    );
    expect(
      native,
      contains('} else if (cmd.shaderType != ShaderType::Background) {'),
    );
    expect(
      native,
      contains('merged.flags = DrawCommandFlags::CrossTileMerged;'),
    );
  });

  test('merged stride is a float2', () {
    const bytesPerFloat32 = 4;
    const componentsPerPosition = 2;
    expect(mergedVertexStride, componentsPerPosition * bytesPerFloat32);
  });

  test('merged commands need no vertex repacking', () {
    // The renderer skips `repackVertexDataForGpu` when the exported stride
    // already equals the stride the pipeline consumes. That skip is only
    // correct if the two agree for every shader that can carry a merged
    // buffer, with the flags a merged command actually arrives with.
    for (final shader in <int>[ShaderType.fill, ShaderType.background]) {
      expect(
        gpuVertexStride(shader, DrawCommandFlags.crossTileMerged),
        mergedVertexStride,
        reason: 'merged shader $shader would be repacked',
      );
    }
  });

  test('a data-driven fill does not share the merged layout', () {
    // Guards the eligibility rule from the other side: if native ever merged a
    // data-driven fill, its 28-byte layout would be read as a float2.
    expect(
      gpuVertexStride(
        ShaderType.fill,
        DrawCommandFlags.crossTileMerged | DrawCommandFlags.fillColorDataDriven,
      ),
      isNot(mergedVertexStride),
    );
  });
}
