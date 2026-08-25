import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/pipeline_key.dart';
import 'package:maplibre_flutter_gpu/src/gpu/pipeline_registry.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

RenderPipelineKey _key(int shader, [int flags = 0]) =>
    pipelineKeyFor(shader: shader, flags: flags);

void main() {
  test('every pipeline key has a spec', () {
    expect(
      MapPipelineRegistry.specifiedKeys.toSet(),
      RenderPipelineKey.values.toSet(),
    );
  });

  group('pipelineKeyFor', () {
    test('selects the data-driven twin only when a paint bit is set', () {
      expect(_key(ShaderType.fill), RenderPipelineKey.fill);
      expect(
        _key(ShaderType.fill, DrawCommandFlags.fillColorDataDriven),
        RenderPipelineKey.fillDataDriven,
      );
      expect(
        _key(ShaderType.fill, DrawCommandFlags.fillOpacityDataDriven),
        RenderPipelineKey.fillDataDriven,
      );
      expect(_key(ShaderType.line), RenderPipelineKey.line);
      expect(
        _key(ShaderType.line, DrawCommandFlags.lineWidthDataDriven),
        RenderPipelineKey.lineDataDriven,
      );
      expect(_key(ShaderType.circle), RenderPipelineKey.circle);
      expect(
        _key(ShaderType.circle, DrawCommandFlags.circleBlurDataDriven),
        RenderPipelineKey.circleDataDriven,
      );
      expect(
        _key(ShaderType.fillOutlineTriangulated),
        RenderPipelineKey.fillOutlineTriangulated,
      );
      expect(
        _key(
          ShaderType.fillOutlineTriangulated,
          DrawCommandFlags.fillOutlineColorDataDriven,
        ),
        RenderPipelineKey.fillOutlineTriangulatedDataDriven,
      );
      expect(_key(ShaderType.fillExtrusion), RenderPipelineKey.fillExtrusion);
      expect(
        _key(
          ShaderType.fillExtrusion,
          DrawCommandFlags.fillExtrusionDataDriven,
        ),
        RenderPipelineKey.fillExtrusionDataDriven,
      );
      expect(
        _key(
          ShaderType.fillExtrusion,
          DrawCommandFlags.fillExtrusionDataDriven |
              DrawCommandFlags.fillExtrusionGpuReady,
        ),
        RenderPipelineKey.fillExtrusionExpandedDataDriven,
      );
    });

    test('keeps each line variant on its own pipeline', () {
      expect(_key(ShaderType.lineSDF), RenderPipelineKey.lineSdf);
      expect(_key(ShaderType.lineGradient), RenderPipelineKey.lineGradient);
      expect(_key(ShaderType.linePattern), RenderPipelineKey.linePattern);
      expect(
        _key(ShaderType.lineSDF, DrawCommandFlags.lineColorDataDriven),
        RenderPipelineKey.lineSdfDataDriven,
      );
      expect(
        _key(ShaderType.lineGradient, DrawCommandFlags.lineColorDataDriven),
        RenderPipelineKey.lineGradientDataDriven,
      );
      expect(
        _key(ShaderType.linePattern, DrawCommandFlags.linePatternDataDriven),
        RenderPipelineKey.linePatternDataDriven,
      );
    });

    test('merged geometry outranks the shader it came from', () {
      expect(
        _key(ShaderType.fill, DrawCommandFlags.crossTileMerged),
        RenderPipelineKey.fillMerged,
      );
      expect(
        _key(ShaderType.background, DrawCommandFlags.crossTileMerged),
        RenderPipelineKey.fillMerged,
      );
      expect(_key(ShaderType.background), RenderPipelineKey.fill);
    });

    test('single-pipeline shaders ignore paint flags', () {
      expect(_key(ShaderType.fillOutline), RenderPipelineKey.fillOutline);
      expect(_key(ShaderType.raster), RenderPipelineKey.raster);
      expect(
        _key(ShaderType.backgroundPattern),
        RenderPipelineKey.backgroundPattern,
      );
      expect(_key(ShaderType.clippingMask), RenderPipelineKey.clippingMask);
      expect(
        _key(ShaderType.fillOutline, DrawCommandFlags.fillColorDataDriven),
        RenderPipelineKey.fillOutline,
      );
    });
  });

  group('depthPipelineKeyFor', () {
    test('only fill extrusion has a depth prepass pipeline', () {
      for (final shader in <int>[
        ShaderType.fill,
        ShaderType.line,
        ShaderType.circle,
        ShaderType.raster,
        ShaderType.clippingMask,
        ShaderType.backgroundPattern,
      ]) {
        expect(
          depthPipelineKeyFor(shader: shader, flags: 0),
          isNull,
          reason: 'shader $shader',
        );
      }
    });

    test('matches packed and expanded color pipelines', () {
      expect(
        depthPipelineKeyFor(shader: ShaderType.fillExtrusion, flags: 0),
        RenderPipelineKey.fillExtrusionDepth,
      );
      expect(
        depthPipelineKeyFor(
          shader: ShaderType.fillExtrusion,
          flags: DrawCommandFlags.fillExtrusionDataDriven,
        ),
        RenderPipelineKey.fillExtrusionDataDrivenDepth,
      );
      expect(
        depthPipelineKeyFor(
          shader: ShaderType.fillExtrusion,
          flags:
              DrawCommandFlags.fillExtrusionDataDriven |
              DrawCommandFlags.fillExtrusionGpuReady,
        ),
        RenderPipelineKey.fillExtrusionExpandedDataDrivenDepth,
      );
    });
  });
}
