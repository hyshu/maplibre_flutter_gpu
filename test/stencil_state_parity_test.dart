import 'dart:convert';
import 'dart:io';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/frame/gpu_state.dart';

void _expectStencilConfig(
  int mode, {
  required gpu.CompareFunction compare,
  required gpu.StencilOperation pass,
  required int readMask,
  required int writeMask,
}) {
  final config = stencilConfigFor(mode);
  expect(config.compareFunction, compare);
  expect(config.stencilFailureOperation, gpu.StencilOperation.keep);
  expect(config.depthFailureOperation, gpu.StencilOperation.keep);
  expect(config.depthStencilPassOperation, pass);
  expect(config.readMask, readMask);
  expect(config.writeMask, writeMask);
}

void main() {
  test('Dart and native stencil enums share the extended DrawCommand ABI', () {
    expect(ShaderType.clippingMask, 11);
    expect(StencilModeType.disabled, 0);
    expect(StencilModeType.clippingMask, 1);
    expect(StencilModeType.clippingTest, 2);
    expect(StencilModeType.fillExtrusion, 3);
    expect(StencilModeType.clear, 4);

    expect(DrawCommandAbi.size, 400);
    expect(DrawCommandAbi.stencilReference, 392);
    expect(DrawCommandAbi.stencilMode, 396);

    final header = File(
      'vendor/maplibre-native/include/mbgl/command_export/draw_command.hpp',
    ).readAsStringSync();
    expect(header, contains('ClippingMask = 11'));
    expect(header, contains('Disabled = 0'));
    expect(header, contains('ClippingMask = 1'));
    expect(header, contains('ClippingTest = 2'));
    expect(header, contains('FillExtrusion = 3'));
    expect(header, contains('Clear = 4'));
    expect(header, contains('static_assert(sizeof(DrawCommand) == 400'));
    expect(
      header,
      contains('COMMAND_EXPORT_ABI_OFFSET(DrawCommand, stencilReference, 392)'),
    );
    expect(
      header,
      contains('COMMAND_EXPORT_ABI_OFFSET(DrawCommand, stencilMode, 396)'),
    );
  });

  test('Flutter GPU stencil configs exactly match MapLibre modes', () {
    _expectStencilConfig(
      StencilModeType.disabled,
      compare: gpu.CompareFunction.always,
      pass: gpu.StencilOperation.keep,
      readMask: 0xff,
      writeMask: 0x00,
    );
    _expectStencilConfig(
      StencilModeType.clippingMask,
      compare: gpu.CompareFunction.always,
      pass: gpu.StencilOperation.setToReferenceValue,
      readMask: 0xff,
      writeMask: 0xff,
    );
    _expectStencilConfig(
      StencilModeType.clippingTest,
      compare: gpu.CompareFunction.equal,
      pass: gpu.StencilOperation.setToReferenceValue,
      readMask: 0xff,
      writeMask: 0x00,
    );
    _expectStencilConfig(
      StencilModeType.fillExtrusion,
      compare: gpu.CompareFunction.notEqual,
      pass: gpu.StencilOperation.setToReferenceValue,
      readMask: 0xff,
      writeMask: 0xff,
    );
    expect(() => stencilConfigFor(StencilModeType.clear), throwsStateError);
  });

  test('clipping-mask shader is declared and writes transparent color', () {
    final manifest = jsonDecode(
      File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['ClippingMaskVertex'], {
      'type': 'vertex',
      'file': 'clipping_mask.vert',
    });
    expect(manifest['ClippingMaskFragment'], {
      'type': 'fragment',
      'file': 'clipping_mask.frag',
    });

    final vertex = File('shaders/clipping_mask.vert').readAsStringSync();
    final fragment = File('shaders/clipping_mask.frag').readAsStringSync();
    final renderer = SourceFiles.renderer;
    expect(vertex, contains('layout(location = 0) in vec2 a_pos;'));
    expect(vertex, contains('uniform ClippingMaskDrawableUBO'));
    expect(
      vertex,
      contains('gl_Position = drawable.matrix * vec4(a_pos, 0.0, 1.0);'),
    );
    expect(fragment, contains('frag_color = vec4(0.0);'));
    expect(
      renderer,
      contains(
        RegExp(
          r"RenderPipelineKey\.clippingMask: \(\s*vertex: 'ClippingMaskVertex',"
          r"\s*fragment: 'ClippingMaskFragment',",
        ),
      ),
    );
    expect(
      renderer,
      contains('ShaderType.clippingMask => RenderPipelineKey.clippingMask'),
    );
    // The mask writes stencil only, so it declares no props UBO and the binder
    // must therefore bind none.
    expect(
      renderer,
      contains(
        RegExp(
          r"drawable: 'ClippingMaskDrawableUBO',\s*vertexProps: null,"
          r'\s*fragmentProps: null,',
        ),
      ),
    );
  });

  test('zero-geometry stencil clear survives command validation', () {
    final renderer = SourceFiles.renderer;
    // The decode loop classifies through admitDrawCommand rather than
    // re-deriving the rules inline, so the clear's exemption from the geometry
    // checks is stated once. That exemption itself is asserted against
    // admitDrawCommand in test/draw_command_admission_test.dart.
    final admit = renderer.indexOf('admitDrawCommand(');
    final controlBranch = renderer.indexOf(
      'if (admission == DrawCommandAdmission.controlCommand)',
      admit,
    );
    final decodeEnd = renderer.indexOf(
      'final vertexStride = nativeVertexStride(',
      controlBranch,
    );
    expect(admit, greaterThanOrEqualTo(0));
    expect(controlBranch, greaterThan(admit));
    expect(decodeEnd, greaterThan(controlBranch));
    // Dropping happens before the control branch, so a clear cannot be
    // rejected by a rule meant for drawable geometry.
    expect(
      renderer.substring(admit, controlBranch),
      contains('if (admission == DrawCommandAdmission.drop) return null;'),
    );
    final clearBlock = renderer.substring(controlBranch, decodeEnd);
    // The branch must yield an entry, not fall through to the stride and
    // buffer resolution below it; the caller is what appends it to the frame.
    expect(clearBlock, contains('_acquireDrawEntry('));
    expect(clearBlock, contains('stencilMode'));
    expect(clearBlock, contains('null'));

    final paint = File(
      'vendor/maplibre-native/src/mbgl/renderer/paint_parameters.cpp',
    ).readAsStringSync();
    final nativeClearStart = paint.indexOf(
      '#elif MLN_RENDER_BACKEND_COMMAND_EXPORT',
      paint.indexOf('void PaintParameters::clearStencil()'),
    );
    final nativeClearEnd = paint.indexOf('#endif', nativeClearStart);
    expect(nativeClearStart, greaterThanOrEqualTo(0));
    expect(nativeClearEnd, greaterThan(nativeClearStart));
    final nativeClear = paint.substring(nativeClearStart, nativeClearEnd);
    expect(nativeClear, contains('getFrameData().addCommand'));
    expect(nativeClear, contains('nullptr'));
    expect(nativeClear, contains('StencilModeType::Clear'));
    expect(nativeClear, contains('command.stencilReference = 0'));
  });

  test(
    'bridge preserves masks and excludes all stencil commands from merge',
    () {
      final bridge = File('native/src/bridge_merge.cpp').readAsStringSync();
      expect(bridge, contains('c.shaderType != ShaderType::ClippingMask'));
      expect(
        bridge,
        contains('if (cmd.stencilMode != StencilModeType::Disabled) continue;'),
      );
      expect(bridge, contains('const bool hasOrderedStencil = std::any_of'));
      final orderedReturn = bridge.indexOf('if (hasOrderedStencil) return;');
      final sort = bridge.indexOf('std::stable_sort', orderedReturn);
      expect(orderedReturn, greaterThanOrEqualTo(0));
      expect(sort, greaterThan(orderedReturn));
      final stencilBarrier = bridge.indexOf(
        'if (cmd.stencilMode != StencilModeType::Disabled) continue;',
      );
      final groupInsert = bridge.indexOf('groups[key] = {ci};', stencilBarrier);
      expect(stencilBarrier, greaterThanOrEqualTo(0));
      expect(groupInsert, greaterThan(stencilBarrier));
    },
  );

  test('every depth/stencil pass stores both attachment aspects', () {
    final executor = SourceFiles.passExecutorOnly;
    final targetStart = executor.indexOf('gpu.RenderTarget renderTarget(');
    final overlayStart = executor.indexOf('gpu.RenderPass beginOverlayPass(');
    final clearStart = executor.indexOf('void clearStencilPass(', overlayStart);
    expect(targetStart, greaterThanOrEqualTo(0));
    expect(overlayStart, greaterThanOrEqualTo(0));
    expect(clearStart, greaterThan(overlayStart));

    final target = executor.substring(targetStart, overlayStart);
    expect(target, contains('depthLoadAction: clearDepth'));
    expect(target, contains('depthStoreAction: gpu.StoreAction.store'));
    expect(target, contains('stencilLoadAction: clearStencil'));
    expect(target, contains('stencilStoreAction: gpu.StoreAction.store'));

    final clearFrameStart = executor.indexOf(
      'void clearFramePass(',
      clearStart,
    );
    expect(clearFrameStart, greaterThan(clearStart));
    final clear = executor.substring(clearStart, clearFrameStart);
    expect(clear, contains('clearDepth: !attachmentInitialized'));
    expect(clear, contains('clearStencil: true'));
  });

  test('render target descriptors are renderer-owned and reused', () {
    final executor = SourceFiles.passExecutorOnly;
    final renderer = SourceFiles.renderer;

    expect(
      RegExp(r'gpu\.RenderTarget\(').allMatches(executor).length,
      2,
      reason: 'only the color-only and depth descriptor trees are allocated',
    );
    expect(executor, contains('return _colorOnlyTarget!;'));
    expect(executor, contains('return _depthTarget!;'));
    expect(renderer, contains('final FramePassExecutor _passes'));
    expect(renderer, contains('_passes.renderTarget('));
    expect(renderer, contains('_passes.releaseResources();'));
  });

  test('single-submit is retained except on Metal backends', () {
    final executor = SourceFiles.passExecutorOnly;
    final renderer = File('lib/src/gpu/renderer.dart').readAsStringSync();
    final painter = SourceFiles.gpuPainterOnly;

    expect(executor, isNot(contains('createCommandBuffer()')));
    expect(executor, isNot(contains('commandBuffer.submit()')));
    expect(renderer, contains('bool submitEachRenderPass = false'));
    expect(renderer, contains('if (submitEachRenderPass && hasRecordedPass)'));
    expect(
      renderer,
      contains('currentCommandBuffer = gpu.gpuContext.createCommandBuffer()'),
    );
    expect(renderer, contains('currentCommandBuffer.submit()'));
    expect(renderer, contains('required gpu.CommandBuffer commandBuffer'));
    expect(painter, contains('commandBuffer: commandBuffer'));
    expect(painter, contains('defaultTargetPlatform == TargetPlatform.iOS'));
    expect(painter, contains('defaultTargetPlatform == TargetPlatform.macOS'));
    expect(painter, contains('submitEachRenderPass: submitEachRenderPass'));
    expect(RegExp(r'commandBuffer\.submit\(\)').allMatches(painter).length, 1);
  });

  test('first draw pass absorbs the frame clear', () {
    final painter = SourceFiles.gpuPainterOnly;
    final renderer = SourceFiles.renderer;
    final executor = SourceFiles.passExecutorOnly;

    final prepare = painter.indexOf('gpuRenderer.prepareDepthStencilTexture(');
    final render = painter.indexOf('gpuRenderer.renderFrame(', prepare);
    expect(prepare, greaterThanOrEqualTo(0));
    expect(render, greaterThan(prepare));
    expect(
      painter.substring(prepare, render),
      isNot(contains('createRenderPass(')),
    );
    expect(painter.substring(render), contains('frameClearColor:'));
    expect(
      painter.substring(render),
      contains('initialDepthStencilTexture: depthStencilTexture'),
    );
    expect(painter, contains('on DepthStencilAttachmentError catch (error)'));
    expect(painter, contains('gpuRenderer.disableDepthStencil(error.cause)'));
    expect(painter, contains('if (depthStencilTexture == null) rethrow;'));

    expect(renderer, contains('var colorInitialized = false;'));
    expect(renderer, contains('gpu.RenderPass? activePass;'));
    expect(
      renderer,
      contains('activePass == null || activeDepthWrite != plan.depthWrite'),
    );
    expect(renderer, contains('clearColor: !colorInitialized'));
    expect(renderer, contains('clearDepth: initializeDepthStencil'));
    expect(renderer, contains('clearStencil: initializeDepthStencil'));
    expect(renderer, contains('if (!colorInitialized)'));
    expect(renderer, contains('_passes.clearFramePass('));

    expect(executor, contains('final colorLoadAction = clearColor'));
    expect(executor, contains('loadAction: colorLoadAction'));
    expect(executor, contains('? gpu.LoadAction.clear'));
    expect(executor, contains(': gpu.LoadAction.load'));
    expect(executor, contains('int drawRun('));
    expect(executor, contains('pass.clearBindings();'));
    expect(executor, contains('pass.bindPipeline(pipeline.pipeline);'));
    expect(executor, contains('gpu.CompareFunction.always'));
    expect(executor, contains('gpu.CullMode.none'));

    expect(renderer, contains('prepareDepthStencilTexture('));
    expect(renderer, contains('void disableDepthStencil(Object error)'));
    expect(
      renderer,
      contains(
        'initialDepthStencilTexture ?? prepareDepthStencilTexture(texture)',
      ),
    );
  });

  test('fill-extrusion depth and color passes use distinct stencil state', () {
    final renderer = SourceFiles.renderer;
    final prepassStart = renderer.indexOf(
      'if (mainDepthStencilTexture != null && needsDepthPrepass)',
    );
    final colorStart = renderer.indexOf(
      'var colorCursor = cursor;',
      prepassStart,
    );
    final colorEnd = renderer.indexOf('cursor = layerEnd;', colorStart);
    expect(prepassStart, greaterThanOrEqualTo(0));
    expect(colorStart, greaterThan(prepassStart));
    expect(colorEnd, greaterThan(colorStart));

    final prepass = renderer.substring(prepassStart, colorStart);
    expect(prepass, contains('stencilMode: StencilModeType.disabled'));

    final colorPass = renderer.substring(colorStart, colorEnd);
    expect(colorPass, contains('final stencilMode = colorFirst.stencilMode'));
    expect(colorPass, contains('stencilMode: stencilMode'));
  });

  test('fill and line fragments no longer emulate tile-extent clipping', () {
    for (final name in const [
      'fill.frag',
      'fill_dd.frag',
      'fill_outline.frag',
      'fill_outline_triangulated.frag',
      'fill_outline_triangulated_dd.frag',
      'line.frag',
      'line_dd.frag',
      'line_sdf.frag',
      'line_sdf_dd.frag',
      'line_gradient.frag',
      'line_gradient_dd.frag',
      'line_pattern.frag',
      'line_pattern_dd.frag',
    ]) {
      final source = File('shaders/$name').readAsStringSync();
      expect(source, isNot(contains('discard')), reason: name);
      expect(source, isNot(contains('v_pos.x < 0.0')), reason: name);
      expect(source, isNot(contains('v_pos.y > 8192.0')), reason: name);
    }
  });

  test('native reuses tile masks and shares one 3D reference per layer', () {
    final group = File(
      'vendor/maplibre-native/src/mbgl/command_export/tile_layer_group.cpp',
    ).readAsStringSync();
    final paint = File(
      'vendor/maplibre-native/src/mbgl/renderer/paint_parameters.cpp',
    ).readAsStringSync();
    final drawable = File(
      'vendor/maplibre-native/src/mbgl/command_export/drawable.cpp',
    ).readAsStringSync();
    final maskFunctionStart = paint.indexOf(
      'bool PaintParameters::renderTileClippingMasks',
    );
    final maskFunctionEnd = paint.indexOf(
      'gfx::StencilMode PaintParameters::stencilModeForClipping',
      maskFunctionStart,
    );
    expect(maskFunctionStart, greaterThanOrEqualTo(0));
    expect(maskFunctionEnd, greaterThan(maskFunctionStart));
    final maskFunction = paint.substring(maskFunctionStart, maskFunctionEnd);

    expect(paint, contains('constexpr std::array<ClippingMaskVertex, 4>'));
    expect(paint, contains('constexpr std::array<uint16_t, 6>'));
    expect(
      paint,
      contains('addCommand(command_export::ShaderType::ClippingMask'),
    );
    expect(
      paint,
      contains(
        'command.stencilMode = command_export::StencilModeType::ClippingMask',
      ),
    );
    expect(
      paint,
      contains('command.stencilReference = static_cast<uint32_t>(stencilID)'),
    );
    expect(paint, contains('std::memcpy(command.drawableUBO, matrix.data()'));
    expect(
      maskFunction,
      contains('tileIDsCovered(renderTiles, tileClippingMaskIDs)'),
    );
    expect(
      maskFunction,
      contains('emitClippingMaskCommand(*this, tileID, stencilID)'),
    );
    expect(group, contains('parameters.renderTileClippingMasks(stencilTiles)'));
    expect(group, isNot(contains('emitClippingMaskCommand')));
    expect(
      RegExp(r'parameters\.stencilModeFor3D\(\)').allMatches(group).length,
      1,
    );
    expect(
      group,
      contains('stencilReference3D = parameters.stencilModeFor3D().ref'),
    );
    expect(group, contains('setStencilReferenceFor3D('));

    expect(drawable, contains('stencilReferenceFor3D'));
    expect(drawable, contains('StencilModeType::FillExtrusion'));
    expect(drawable, contains('StencilModeType::ClippingTest'));
    expect(drawable, contains('cmd.stencilReference = stencilReference'));
    expect(drawable, contains('cmd.stencilMode = stencilMode'));
  });
}
