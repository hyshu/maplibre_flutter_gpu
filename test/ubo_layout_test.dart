import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';

void main() {
  test('every supported shader has the exact native UBO layout', () {
    const expected = {
      ShaderType.fill: (drawableBytes: 80, propsBytes: 48, tilePropsBytes: 0),
      ShaderType.fillOutline: (
        drawableBytes: 80,
        propsBytes: 48,
        tilePropsBytes: 0,
      ),
      ShaderType.line: (drawableBytes: 96, propsBytes: 48, tilePropsBytes: 0),
      ShaderType.background: (
        drawableBytes: 80,
        propsBytes: 48,
        tilePropsBytes: 0,
      ),
      ShaderType.fillExtrusion: (
        drawableBytes: 112,
        propsBytes: 80,
        tilePropsBytes: 0,
      ),
      ShaderType.lineSDF: (
        drawableBytes: 128,
        propsBytes: 48,
        tilePropsBytes: 16,
      ),
      ShaderType.lineGradient: (
        drawableBytes: 96,
        propsBytes: 48,
        tilePropsBytes: 0,
      ),
      ShaderType.linePattern: (
        drawableBytes: 96,
        propsBytes: 48,
        tilePropsBytes: 64,
      ),
      ShaderType.circle: (
        drawableBytes: 112,
        propsBytes: 64,
        tilePropsBytes: 0,
      ),
      ShaderType.raster: (drawableBytes: 64, propsBytes: 64, tilePropsBytes: 0),
      ShaderType.fillOutlineTriangulated: (
        drawableBytes: 80,
        propsBytes: 48,
        tilePropsBytes: 0,
      ),
      ShaderType.clippingMask: (
        drawableBytes: 64,
        propsBytes: 0,
        tilePropsBytes: 0,
      ),
      ShaderType.backgroundPattern: (
        drawableBytes: 96,
        propsBytes: 64,
        tilePropsBytes: 0,
      ),
    };

    for (final entry in expected.entries) {
      expect(
        rendererUboLayoutForShader(entry.key),
        entry.value,
        reason: 'shader ${entry.key}',
      );
    }
    expect(
      () => rendererUboLayoutForShader(ShaderType.unknown),
      throwsArgumentError,
    );
    expect(() => rendererUboLayoutForShader(-1), throwsArgumentError);
  });

  test('renderer UBO ABI offsets retain their exact byte values', () {
    expect(RendererUboAbi.noUniformBytes, 0);
    expect(RendererUboAbi.float32Bytes, 4);
    expect(RendererUboAbi.vec4Bytes, 16);
    expect(RendererUboAbi.fillColorComponentCount, 4);
    expect(RendererUboAbi.minimumUniformByteAlignment, 16);
    expect(RendererUboAbi.minimumUniformAllocationBytes, 16);

    expect(RendererUboAbi.drawableMatrixBytes, 64);
    expect(RendererUboAbi.drawableMatrixM11Offset, 20);
    expect(RendererUboAbi.backgroundPatternAtlasWidthOffset, 84);
    expect(RendererUboAbi.backgroundPatternAtlasHeightOffset, 88);
    expect(RendererUboAbi.circleCameraDistanceOffset, 100);
    expect(RendererUboAbi.circleDevicePixelRatioOffset, 104);
    expect(RendererUboAbi.circleDataDrivenMaskOffset, 60);
    expect(RendererUboAbi.fillExtrusionDataDrivenMaskOffset, 108);
    expect(RendererUboAbi.fillExtrusionOpacityOffset, 60);
    expect(RendererUboAbi.lineDevicePixelRatioOffset, 92);
    expect(RendererUboAbi.lineSdfDevicePixelRatioOffset, 120);
    expect(RendererUboAbi.lineDataDrivenMaskOffset, 40);
    expect(RendererUboAbi.lineOpacityOffset, 20);
    expect(RendererUboAbi.lineWidthOffset, 32);
    expect(RendererUboAbi.fillDataDrivenMaskOffset, 72);
    expect(RendererUboAbi.fillOutlineDevicePixelRatioOffset, 68);
    expect(RendererUboAbi.backgroundOpacityOffset, 16);
    expect(RendererUboAbi.fillColorOffset, 0);
    expect(RendererUboAbi.fillOutlineColorOffset, 16);
    expect(RendererUboAbi.fillOpacityOffset, 32);
    expect(RendererUboAbi.fillOutlineDataDrivenMaskOffset, 36);

    expect(RendererUboAbi.mapGlobalBytes, 16);
    expect(RendererUboAbi.mapGlobalUnitsXOffset, 0);
    expect(RendererUboAbi.mapGlobalUnitsYOffset, 4);
    expect(RendererUboAbi.mapGlobalWorldWidthOffset, 8);
    expect(RendererUboAbi.mapGlobalWorldHeightOffset, 12);
  });

  test('float field boundaries preserve real zero opacity and width', () {
    expect(
      rendererUboContainsFloat32(23, RendererUboAbi.lineOpacityOffset),
      isFalse,
    );
    expect(
      rendererUboContainsFloat32(24, RendererUboAbi.lineOpacityOffset),
      isTrue,
    );
    expect(
      rendererUboContainsFloat32(35, RendererUboAbi.lineWidthOffset),
      isFalse,
    );
    expect(
      rendererUboContainsFloat32(36, RendererUboAbi.lineWidthOffset),
      isTrue,
    );
    expect(
      rendererUboContainsFloat32(19, RendererUboAbi.backgroundOpacityOffset),
      isFalse,
    );
    expect(
      rendererUboContainsFloat32(20, RendererUboAbi.backgroundOpacityOffset),
      isTrue,
    );
    expect(
      rendererUboContainsFloat32(35, RendererUboAbi.fillOpacityOffset),
      isFalse,
    );
    expect(
      rendererUboContainsFloat32(36, RendererUboAbi.fillOpacityOffset),
      isTrue,
    );
  });

  group('layoutFrameUniforms', () {
    test('places the map-global UBO after the per-draw ranges', () {
      final layout = layoutFrameUniforms(
        drawableCursor: 200,
        alignment: 64,
        hasMapGlobal: true,
      );
      expect(layout.mapGlobalOffset, 256);
      expect(layout.totalBytes, 320);
    });

    test('a frame without line or outline draws allocates no map global', () {
      final layout = layoutFrameUniforms(
        drawableCursor: 200,
        alignment: 64,
        hasMapGlobal: false,
      );
      expect(layout.mapGlobalOffset, 0);
      expect(layout.totalBytes, 256);
    });

    test('an empty frame still allocates the backend minimum', () {
      final layout = layoutFrameUniforms(
        drawableCursor: 0,
        alignment: 16,
        hasMapGlobal: false,
      );
      expect(layout.mapGlobalOffset, 0);
      expect(layout.totalBytes, RendererUboAbi.minimumUniformAllocationBytes);
    });

    test('an already aligned cursor places the map global without padding', () {
      final layout = layoutFrameUniforms(
        drawableCursor: 256,
        alignment: 64,
        hasMapGlobal: true,
      );
      expect(layout.mapGlobalOffset, 256);
      // The block itself is still rounded up: the backend binds the whole
      // allocation, not just the bytes written into it.
      expect(layout.totalBytes, 320);
    });
  });
}
