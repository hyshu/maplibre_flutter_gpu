import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

void main() {
  test('painter shares one native frame metadata snapshot with renderer', () {
    final painter = SourceFiles.gpuPainterOnly;
    final renderer = SourceFiles.renderer;
    final ffi = SourceFiles.ffi;
    final native = File('native/src/maplibre_bridge.cpp').readAsStringSync();

    expect(
      RegExp(r'bridge\.frameGetMetadata\(\)').allMatches(painter).length,
      1,
    );
    final preparedRangeCheck = painter.indexOf(
      'preparedFrame.hasCommandsInStratum(',
    );
    expect(preparedRangeCheck, greaterThanOrEqualTo(0));
    expect(
      preparedRangeCheck,
      lessThan(painter.indexOf('resources.resize(width, height)')),
      reason: 'empty transparent strata must skip texture allocation',
    );
    expect(painter, isNot(contains('frameHasCommandsInLayerRange(')));
    expect(painter, contains('frameMetadata: frameMetadata'));
    expect(renderer, contains('frameMetadata ?? bridge.frameGetMetadata()'));
    expect(renderer, isNot(contains('bridge.frameGetCommandCount()')));
    expect(renderer, isNot(contains('bridge.frameGetCommands()')));
    expect(renderer, isNot(contains('bridge.frameGetCommandStride()')));

    expect(ffi, contains('lookupFunction<FrameMetadataN, FrameMetadataD>'));
    expect(ffi, contains("'maplibre_frame_get_metadata'"));
    // Libraries predating the single-call accessor still resolve through the
    // per-field entry points.
    expect(ffi, contains('_frameGetMetadataPiecewise()'));
    expect(ffi, contains('commands: _frameGetCommands?.call() ?? nullptr'));
    expect(native, contains('maplibre_frame_get_metadata(void)'));
  });

  test('GPU callbacks receive map transform and callback-specific depth', () {
    final painter = SourceFiles.gpuPainterOnly;
    final renderer = SourceFiles.renderer;
    final map = SourceFiles.mapWidgetOnly;
    final ffi = SourceFiles.ffi;
    final native = File('native/src/maplibre_bridge.cpp').readAsStringSync();

    expect(ffi, contains("'maplibre_frame_get_map_transform'"));
    expect(ffi, contains('FrameMapTransform? frameGetMapTransform()'));
    expect(native, contains('maplibre_frame_get_map_transform(void)'));
    expect(
      native,
      contains(
        'static_cast<uint16_t>(0.1 * state.getCameraToCenterDistance())',
      ),
    );
    expect(native, contains('state.getProjMatrix(matrix, nearZ)'));
    expect(
      native,
      contains('const double originX = 0.5 * worldSize - state.getX()'),
    );
    expect(
      native,
      contains('const double originY = 0.5 * worldSize - state.getY()'),
    );
    expect(painter, contains('bridge.frameGetMapTransform()'));
    expect(
      painter,
      contains('gpuMapRenderCallback != null || gpuRenderCallback != null'),
    );
    expect(painter, contains('gpuMapRenderCallback: gpuMapRenderCallback'));
    expect(painter, contains(': .load'));
    expect(painter, contains('gpuOverlayDepthMode == .isolated'));
    expect(painter, contains('? .clear'));
    expect(painter, contains('hasDepthStencilAttachment:'));
    expect(renderer, contains('threeDimensionalRenderInsertionIndex'));
    expect(renderer, contains('threeDimensionalCallbackInLayerRange'));
    expect(
      renderer,
      contains('var attachmentInitialized = _sharedDepthStencilInitialized'),
    );
    expect(map, contains('singleGpuSurface: usesSingleGpuSurface'));
    expect(map, contains("key: const ValueKey<String>('gpu:callbacks')"));
    expect(renderer, contains('gpuMapRenderCallback error'));
  });

  test('symbol GPU topology uses the current projected label layers', () {
    final map = SourceFiles.mapWidgetOnly;
    final renderStart = map.indexOf('void renderGesture()');
    final renderEnd = map.indexOf('\n  @override', renderStart + 1);
    final render = map.substring(renderStart, renderEnd);

    expect(
      render.indexOf('_labels.cacheScreenPositions('),
      lessThan(render.indexOf('symbolGpuStratumSlots(')),
    );
    expect(render, contains('symbolGpuTopologyChanged'));
    expect(
      render,
      contains('nativeCommandLayerIndices: nextNativeCommandLayerIndices'),
    );
  });
}
