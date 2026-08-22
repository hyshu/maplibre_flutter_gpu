// Maps each DrawCommand to a render pipeline key.
//
// The pass planner and binder both use the stored key. Keeping the mapping here
// ensures both stages use the same decision.
//
// A key identifies a pipeline without creating one, so this logic can be
// tested without a GPU context.
import '../native/draw_command.dart';
import 'draw_flags.dart';

/// Every render pipeline the map can draw with.
///
/// Each value identifies a shader pair and its uniform-slot layout.
/// `DataDriven` variants use vertex attributes for evaluated paint values.
/// `Depth` variants are used by the fill-extrusion depth prepass.
enum RenderPipelineKey {
  fill,
  fillDataDriven,
  fillMerged,
  fillOutline,
  fillOutlineTriangulated,
  fillOutlineTriangulatedDataDriven,
  fillExtrusion,
  fillExtrusionDataDriven,
  fillExtrusionPackedColorDataDriven,
  fillExtrusionDepth,
  fillExtrusionDataDrivenDepth,
  fillExtrusionPackedColorDataDrivenDepth,
  fillExtrusionExpandedDataDriven,
  fillExtrusionExpandedDataDrivenDepth,
  line,
  lineDataDriven,
  lineSdf,
  lineSdfDataDriven,
  lineGradient,
  lineGradientDataDriven,
  linePattern,
  linePatternDataDriven,
  circle,
  circleDataDriven,
  raster,
  backgroundPattern,
  clippingMask,
}

/// The pipeline a command's color pass draws with.
///
/// Cross-tile merged geometry uses screen-space positions and selects the
/// merged pipeline instead of the shader's original vertex layout.
RenderPipelineKey pipelineKeyFor({required int shader, required int flags}) =>
    switch (shader) {
      ShaderType.fillOutline => RenderPipelineKey.fillOutline,
      ShaderType.fillOutlineTriangulated =>
        fillOutlineUsesDataDrivenPipeline(flags)
            ? RenderPipelineKey.fillOutlineTriangulatedDataDriven
            : RenderPipelineKey.fillOutlineTriangulated,
      ShaderType.line =>
        lineUsesDataDrivenPipeline(flags)
            ? RenderPipelineKey.lineDataDriven
            : RenderPipelineKey.line,
      ShaderType.lineSDF =>
        lineUsesDataDrivenPipeline(flags)
            ? RenderPipelineKey.lineSdfDataDriven
            : RenderPipelineKey.lineSdf,
      ShaderType.lineGradient =>
        lineUsesDataDrivenPipeline(flags)
            ? RenderPipelineKey.lineGradientDataDriven
            : RenderPipelineKey.lineGradient,
      ShaderType.linePattern =>
        lineUsesDataDrivenPipeline(flags)
            ? RenderPipelineKey.linePatternDataDriven
            : RenderPipelineKey.linePattern,
      ShaderType.circle =>
        circleUsesDataDrivenPipeline(flags)
            ? RenderPipelineKey.circleDataDriven
            : RenderPipelineKey.circle,
      ShaderType.raster => RenderPipelineKey.raster,
      ShaderType.backgroundPattern => RenderPipelineKey.backgroundPattern,
      ShaderType.clippingMask => RenderPipelineKey.clippingMask,
      ShaderType.fillExtrusion =>
        fillExtrusionUsesPackedColorGpuLayout(flags)
            ? RenderPipelineKey.fillExtrusionPackedColorDataDriven
            : fillExtrusionUsesExpandedGpuLayout(flags)
            ? RenderPipelineKey.fillExtrusionExpandedDataDriven
            : fillExtrusionUsesDataDrivenPipeline(flags)
            ? RenderPipelineKey.fillExtrusionDataDriven
            : RenderPipelineKey.fillExtrusion,
      _ =>
        drawCommandIsCrossTileMerged(flags)
            ? RenderPipelineKey.fillMerged
            : shader == ShaderType.fill && fillUsesDataDrivenPipeline(flags)
            ? RenderPipelineKey.fillDataDriven
            : RenderPipelineKey.fill,
    };

/// Returns the candidate depth-prepass pipeline for a command.
///
/// Only fill extrusion has a depth-prepass pipeline. The planner separately
/// checks [fillExtrusionNeedsDepthPrepass] to decide whether to use it.
RenderPipelineKey? depthPipelineKeyFor({
  required int shader,
  required int flags,
}) => shader != ShaderType.fillExtrusion
    ? null
    : fillExtrusionUsesPackedColorGpuLayout(flags)
    ? RenderPipelineKey.fillExtrusionPackedColorDataDrivenDepth
    : fillExtrusionUsesExpandedGpuLayout(flags)
    ? RenderPipelineKey.fillExtrusionExpandedDataDrivenDepth
    : fillExtrusionUsesDataDrivenPipeline(flags)
    ? RenderPipelineKey.fillExtrusionDataDrivenDepth
    : RenderPipelineKey.fillExtrusionDepth;
