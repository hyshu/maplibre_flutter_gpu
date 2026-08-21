import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/frame/command_layout.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';

const _allShaders = <int>[
  ShaderType.fill,
  ShaderType.fillOutline,
  ShaderType.fillOutlineTriangulated,
  ShaderType.fillExtrusion,
  ShaderType.background,
  ShaderType.backgroundPattern,
  ShaderType.circle,
  ShaderType.raster,
  ShaderType.clippingMask,
  ShaderType.line,
  ShaderType.lineSDF,
  ShaderType.lineGradient,
  ShaderType.linePattern,
];

void main() {
  group('nativeVertexStride', () {
    test('matches the per-shader fixed layouts', () {
      int stride(int shader, [int flags = 0]) =>
          nativeVertexStride(shader: shader, flags: flags, merged: false);

      expect(stride(ShaderType.fill), 4);
      expect(stride(ShaderType.fillExtrusion), 12);
      expect(stride(ShaderType.circle), 4);
      expect(stride(ShaderType.fillOutlineTriangulated), 8);
      expect(stride(ShaderType.line), 8);
      expect(stride(ShaderType.lineSDF), 8);
      expect(stride(ShaderType.lineGradient), 8);
      expect(stride(ShaderType.linePattern), 8);
      expect(stride(ShaderType.raster), 8);
      expect(stride(ShaderType.background), 4);
      expect(stride(ShaderType.backgroundPattern), 4);
      expect(stride(ShaderType.fillOutline), 4);
      expect(stride(ShaderType.clippingMask), 4);
    });

    test('widens for the data-driven layouts', () {
      int stride(int shader, int flags) =>
          nativeVertexStride(shader: shader, flags: flags, merged: false);

      expect(stride(ShaderType.fill, DrawCommandFlags.fillColorDataDriven), 28);
      expect(
        stride(
          ShaderType.fillExtrusion,
          DrawCommandFlags.fillExtrusionDataDriven,
        ),
        44,
      );
      expect(
        stride(
          ShaderType.fillExtrusion,
          DrawCommandFlags.fillExtrusionDataDriven |
              DrawCommandFlags.fillExtrusionGpuReady,
        ),
        56,
      );
      expect(
        stride(ShaderType.circle, DrawCommandFlags.circleColorDataDriven),
        76,
      );
      expect(stride(ShaderType.line, DrawCommandFlags.lineColorDataDriven), 88);
      expect(
        stride(
          ShaderType.fillOutlineTriangulated,
          DrawCommandFlags.fillOutlineColorDataDriven,
        ),
        32,
      );
    });

    test('merged geometry overrides every shader layout', () {
      // Native rewrites merged batches into a bare float2 regardless of what
      // the shader's own vertices look like, so the merged flag must win even
      // against a data-driven layout.
      for (final shader in _allShaders) {
        expect(
          nativeVertexStride(
            shader: shader,
            flags:
                DrawCommandFlags.fillColorDataDriven |
                DrawCommandFlags.lineColorDataDriven,
            merged: true,
          ),
          mergedVertexStride,
          reason: 'shader $shader',
        );
      }
    });

    test('GPU-ready bridge layouts match the GPU stride directly', () {
      expect(
        nativeVertexStride(
          shader: ShaderType.fill,
          flags: DrawCommandFlags.crossTileMerged,
          merged: true,
        ),
        gpuVertexStride(ShaderType.fill, DrawCommandFlags.crossTileMerged),
      );
      const gpuReadyExtrusion =
          DrawCommandFlags.fillExtrusionDataDriven |
          DrawCommandFlags.fillExtrusionGpuReady;
      expect(
        nativeVertexStride(
          shader: ShaderType.fillExtrusion,
          flags: gpuReadyExtrusion,
          merged: false,
        ),
        gpuVertexStride(ShaderType.fillExtrusion, gpuReadyExtrusion),
      );
    });

    test('packed DD extrusion remains a valid repack source', () {
      const flags = DrawCommandFlags.fillExtrusionDataDriven;
      expect(
        nativeVertexStride(
          shader: ShaderType.fillExtrusion,
          flags: flags,
          merged: false,
        ),
        44,
      );
      expect(gpuVertexStride(ShaderType.fillExtrusion, flags), 56);
    });
  });

  group('texture requirements', () {
    test('a failed upload drops every texture-backed shader', () {
      for (final shader in <int>[
        ShaderType.lineSDF,
        ShaderType.linePattern,
        ShaderType.lineGradient,
        ShaderType.raster,
        ShaderType.backgroundPattern,
      ]) {
        expect(
          shaderRequiresUploadedTexture(shader),
          isTrue,
          reason: 'shader $shader',
        );
      }
    });

    test('a plain line survives a failed upload', () {
      expect(shaderRequiresUploadedTexture(ShaderType.line), isFalse);
      expect(shaderRequiresUploadedTexture(ShaderType.fill), isFalse);
    });

    test('only raster and pattern quads need texture bytes to exist', () {
      // The asymmetry is deliberate: a line variant that exports no texture is
      // simply an untextured line, while a raster quad without an image is a
      // hole. Pin it so the two rules are not accidentally merged.
      expect(shaderRequiresTextureData(ShaderType.raster), isTrue);
      expect(shaderRequiresTextureData(ShaderType.backgroundPattern), isTrue);
      expect(shaderRequiresTextureData(ShaderType.lineSDF), isFalse);
      expect(shaderRequiresTextureData(ShaderType.lineGradient), isFalse);
      expect(shaderRequiresTextureData(ShaderType.linePattern), isFalse);
    });

    test('the data rule is a subset of the upload rule', () {
      for (final shader in _allShaders) {
        if (shaderRequiresTextureData(shader)) {
          expect(
            shaderRequiresUploadedTexture(shader),
            isTrue,
            reason:
                'shader $shader needs texture bytes but would survive a '
                'failed upload',
          );
        }
      }
    });
  });

  group('commandNeedsDepthStencil', () {
    test('a plain 2D command needs neither aspect', () {
      expect(
        commandNeedsDepthStencil(
          shader: ShaderType.fill,
          flags: 0,
          stencilMode: StencilModeType.disabled,
        ),
        isFalse,
      );
    });

    test('fill extrusion always needs it, for the depth prepass', () {
      expect(
        commandNeedsDepthStencil(
          shader: ShaderType.fillExtrusion,
          flags: 0,
          stencilMode: StencilModeType.disabled,
        ),
        isTrue,
      );
    });

    test('a resolved depth test needs it whatever the shader', () {
      expect(
        commandNeedsDepthStencil(
          shader: ShaderType.fill,
          flags: DrawCommandFlags.depthTest,
          stencilMode: StencilModeType.disabled,
        ),
        isTrue,
      );
    });

    test('every stencil mode needs it, including the ordered clear', () {
      for (final mode in <int>[
        StencilModeType.clippingMask,
        StencilModeType.clippingTest,
        StencilModeType.fillExtrusion,
        StencilModeType.clear,
      ]) {
        expect(
          commandNeedsDepthStencil(
            shader: ShaderType.fill,
            flags: 0,
            stencilMode: mode,
          ),
          isTrue,
          reason: 'stencil mode $mode',
        );
      }
    });
  });

  group('frameNeedsMapGlobalUniform', () {
    test('is bound for lines and triangulated outlines only', () {
      expect(
        frameNeedsMapGlobalUniform(
          lineCommandCount: 0,
          hasTriangulatedOutline: false,
        ),
        isFalse,
      );
      expect(
        frameNeedsMapGlobalUniform(
          lineCommandCount: 1,
          hasTriangulatedOutline: false,
        ),
        isTrue,
      );
      expect(
        frameNeedsMapGlobalUniform(
          lineCommandCount: 0,
          hasTriangulatedOutline: true,
        ),
        isTrue,
      );
    });
  });
}
