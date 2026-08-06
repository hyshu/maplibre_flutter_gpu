import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';

void main() {
  // Each bit is a contract with command_export::DrawCommand::Flags. A wrong
  // value here does not fail to compile and does not throw — it silently
  // selects the wrong pipeline or vertex stride. Pin every one.
  test('flag bits match the native DrawCommand ABI', () {
    expect(DrawCommandFlags.crossTileMerged, 1 << 0);
    expect(DrawCommandFlags.fillExtrusionDataDriven, 1 << 1);
    expect(DrawCommandFlags.fillColorDataDriven, 1 << 2);
    expect(DrawCommandFlags.fillOpacityDataDriven, 1 << 3);
    expect(DrawCommandFlags.fillExtrusionColorDataDriven, 1 << 4);
    expect(DrawCommandFlags.circleColorDataDriven, 1 << 5);
    expect(DrawCommandFlags.circleRadiusDataDriven, 1 << 6);
    expect(DrawCommandFlags.circleBlurDataDriven, 1 << 7);
    expect(DrawCommandFlags.circleOpacityDataDriven, 1 << 8);
    expect(DrawCommandFlags.circleStrokeColorDataDriven, 1 << 9);
    expect(DrawCommandFlags.circleStrokeWidthDataDriven, 1 << 10);
    expect(DrawCommandFlags.circleStrokeOpacityDataDriven, 1 << 11);
    expect(DrawCommandFlags.lineColorDataDriven, 1 << 12);
    expect(DrawCommandFlags.lineBlurDataDriven, 1 << 13);
    expect(DrawCommandFlags.lineOpacityDataDriven, 1 << 14);
    expect(DrawCommandFlags.lineGapWidthDataDriven, 1 << 15);
    expect(DrawCommandFlags.lineOffsetDataDriven, 1 << 16);
    expect(DrawCommandFlags.lineWidthDataDriven, 1 << 17);
    expect(DrawCommandFlags.lineFloorWidthDataDriven, 1 << 18);
    expect(DrawCommandFlags.linePatternDataDriven, 1 << 19);
    expect(DrawCommandFlags.fillOutlineColorDataDriven, 1 << 20);
    expect(DrawCommandFlags.fillOutlineOpacityDataDriven, 1 << 21);
    expect(DrawCommandFlags.depthTest, 1 << 22);
    expect(DrawCommandFlags.depthWrite, 1 << 23);
  });

  test('group masks cover exactly their group members', () {
    expect(DrawCommandFlags.fillDataDrivenMask, 0x00000c);
    expect(DrawCommandFlags.fillOutlineDataDrivenMask, 0x300000);
    expect(DrawCommandFlags.circleDataDrivenMask, 0x000fe0);
    expect(DrawCommandFlags.lineDataDrivenMask, 0x0ff000);
  });

  test('each shift is the lowest bit of its group mask', () {
    // The helpers shift a masked group down to a shader-facing mask starting
    // at bit 0. If a shift and its mask disagree, the shader receives a
    // correctly-sized but wrongly-positioned mask.
    for (final group in <({int mask, int shift, String name})>[
      (
        mask: DrawCommandFlags.fillDataDrivenMask,
        shift: DrawCommandFlags.fillDataDrivenShift,
        name: 'fill',
      ),
      (
        mask: DrawCommandFlags.fillOutlineDataDrivenMask,
        shift: DrawCommandFlags.fillOutlineDataDrivenShift,
        name: 'fillOutline',
      ),
      (
        mask: DrawCommandFlags.circleDataDrivenMask,
        shift: DrawCommandFlags.circleDataDrivenShift,
        name: 'circle',
      ),
      (
        mask: DrawCommandFlags.lineDataDrivenMask,
        shift: DrawCommandFlags.lineDataDrivenShift,
        name: 'line',
      ),
      (
        mask: DrawCommandFlags.fillExtrusionColorDataDriven,
        shift: DrawCommandFlags.fillExtrusionColorDataDrivenShift,
        name: 'fillExtrusionColor',
      ),
    ]) {
      expect(
        group.mask.toRadixString(2).length - group.shift,
        group.mask >> group.shift == 0
            ? 0
            : (group.mask >> group.shift).toRadixString(2).length,
        reason: '${group.name} shift does not align its mask to bit 0',
      );
      expect(
        (group.mask >> group.shift) & 1,
        1,
        reason: '${group.name} shift leaves a gap below its lowest bit',
      );
    }
  });

  test('masks shift down to contiguous shader-facing values', () {
    expect(fillDataDrivenMask(DrawCommandFlags.fillDataDrivenMask), 0x3);
    expect(
      fillOutlineDataDrivenMask(DrawCommandFlags.fillOutlineDataDrivenMask),
      0x3,
    );
    expect(circleDataDrivenMask(DrawCommandFlags.circleDataDrivenMask), 0x7f);
    expect(lineDataDrivenMask(DrawCommandFlags.lineDataDrivenMask), 0xff);
    expect(
      fillExtrusionDataDrivenMask(
        DrawCommandFlags.fillExtrusionColorDataDriven,
      ),
      0x1,
    );
  });

  test('a group predicate ignores every bit outside its group', () {
    const everythingElse =
        DrawCommandFlags.crossTileMerged |
        DrawCommandFlags.depthTest |
        DrawCommandFlags.depthWrite;
    expect(fillUsesDataDrivenPipeline(everythingElse), isFalse);
    expect(fillOutlineUsesDataDrivenPipeline(everythingElse), isFalse);
    expect(circleUsesDataDrivenPipeline(everythingElse), isFalse);
    expect(lineUsesDataDrivenPipeline(everythingElse), isFalse);
    expect(fillExtrusionUsesDataDrivenPipeline(everythingElse), isFalse);
    expect(drawCommandIsCrossTileMerged(everythingElse), isTrue);
    expect(drawCommandUsesDepth(everythingElse), isTrue);
    expect(drawCommandWritesDepth(everythingElse), isTrue);
  });

  test('native vertex strides are pinned per shader and layout', () {
    expect(fillVertexStride(0), 4);
    expect(fillVertexStride(DrawCommandFlags.fillColorDataDriven), 28);
    expect(fillOutlineVertexStride(0), 8);
    expect(
      fillOutlineVertexStride(DrawCommandFlags.fillOutlineColorDataDriven),
      32,
    );
    expect(fillExtrusionVertexStride(0), 12);
    expect(
      fillExtrusionVertexStride(DrawCommandFlags.fillExtrusionDataDriven),
      44,
    );
    expect(circleVertexStride(0), 4);
    expect(circleVertexStride(DrawCommandFlags.circleColorDataDriven), 76);
    expect(lineVertexStride(0), 8);
    expect(lineVertexStride(DrawCommandFlags.lineColorDataDriven), 88);
  });

  test('line family membership matches the four line shaders', () {
    for (final shader in <int>[
      ShaderType.line,
      ShaderType.lineSDF,
      ShaderType.lineGradient,
      ShaderType.linePattern,
    ]) {
      expect(isLineShader(shader), isTrue, reason: 'shader $shader');
    }
    for (final shader in <int>[
      ShaderType.fill,
      ShaderType.fillOutline,
      ShaderType.fillOutlineTriangulated,
      ShaderType.fillExtrusion,
      ShaderType.background,
      ShaderType.backgroundPattern,
      ShaderType.circle,
      ShaderType.raster,
      ShaderType.clippingMask,
      ShaderType.unknown,
    ]) {
      expect(isLineShader(shader), isFalse, reason: 'shader $shader');
    }
  });

  test('depth prepass is skipped only for fully opaque extrusions', () {
    expect(fillExtrusionNeedsDepthPrepass(1.0), isFalse);
    expect(fillExtrusionNeedsDepthPrepass(1.5), isFalse);
    expect(fillExtrusionNeedsDepthPrepass(0.999), isTrue);
    expect(fillExtrusionNeedsDepthPrepass(0.0), isTrue);
    expect(fillExtrusionNeedsDepthPrepass(double.nan), isTrue);
  });
}
