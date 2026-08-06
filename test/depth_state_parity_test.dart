import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';

void main() {
  test('resolved native depth flags remain independent of paint flags', () {
    const depthTest = 1 << 22;
    const depthWrite = 1 << 23;

    expect(drawCommandUsesDepth(0), isFalse);
    expect(drawCommandWritesDepth(0), isFalse);
    expect(drawCommandUsesDepth(depthTest), isTrue);
    expect(drawCommandWritesDepth(depthTest), isFalse);
    expect(drawCommandUsesDepth(depthTest | depthWrite), isTrue);
    expect(drawCommandWritesDepth(depthTest | depthWrite), isTrue);

    // The highest paint-property flag must not alias render state.
    const fillOutlineOpacity = 1 << 21;
    expect(drawCommandUsesDepth(fillOutlineOpacity), isFalse);
    expect(drawCommandWritesDepth(fillOutlineOpacity), isFalse);
  });

  test(
    'native resolves depth and depth-tested commands bypass x/y-only merge',
    () {
      final flags = File(
        'vendor/maplibre-native/include/mbgl/command_export/draw_command.hpp',
      ).readAsStringSync();
      final drawable = File(
        'vendor/maplibre-native/src/mbgl/command_export/drawable.cpp',
      ).readAsStringSync();
      final merge = File('native/src/bridge_merge.cpp').readAsStringSync();

      expect(flags, contains('DepthTest = 1u << 22'));
      expect(flags, contains('DepthWrite = 1u << 23'));
      expect(drawable, contains('parameters.depthModeFor3D()'));
      expect(drawable, contains('parameters.depthModeForSublayer'));
      expect(
        drawable,
        contains('depthMode.func != gfx::DepthFunctionType::Always'),
      );
      expect(
        drawable,
        contains('depthMode.mask == gfx::DepthMaskType::ReadWrite'),
      );
      expect(
        merge,
        contains('DrawCommandFlags::DepthTest | DrawCommandFlags::DepthWrite'),
      );
      expect(merge, contains('if ((cmd.flags & depthFlags) != 0) continue;'));
    },
  );

  test('renderer shares depth/stencil while preserving read-only depth', () {
    final renderer = SourceFiles.renderer;

    expect(renderer, contains('drawCommandUsesDepth(first.flags)'));
    expect(renderer, contains('drawCommandWritesDepth(first.flags)'));
    expect(renderer, contains('final mainDepthStencilTexture ='));
    expect(renderer, contains('gpu.RenderPass? activePass;'));
    expect(renderer, contains('activeDepthWrite != plan.depthWrite'));
    expect(renderer, contains('depthStencilTexture: mainDepthStencilTexture'));
    expect(renderer, contains('? prepareDepthStencilTexture(texture)'));
    expect(renderer, contains('depthStoreAction: gpu.StoreAction.store'));
    expect(renderer, contains('stencilStoreAction: gpu.StoreAction.store'));
    // Depth writes are enabled only when the plan asks for them, and never
    // disabled explicitly: Flutter GPU's default is already read-only depth,
    // and a pass that turned writes off would also clear the shared
    // attachment's stencil expectations for the passes that follow.
    expect(
      renderer,
      contains('if (depthWrite && depthStencilTexture != null)'),
    );
    expect(renderer, isNot(contains('setDepthWriteEnable(depthWrite)')));
  });
}
