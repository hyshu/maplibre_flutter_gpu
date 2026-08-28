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
  fillExtrusionDepth,
  fillExtrusionDataDrivenDepth,
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
      ShaderType.fillOutline => .fillOutline,
      ShaderType.fillOutlineTriangulated =>
        fillOutlineUsesDataDrivenPipeline(flags)
            ? .fillOutlineTriangulatedDataDriven
            : .fillOutlineTriangulated,
      ShaderType.line =>
        lineUsesDataDrivenPipeline(flags) ? .lineDataDriven : .line,
      ShaderType.lineSDF =>
        lineUsesDataDrivenPipeline(flags) ? .lineSdfDataDriven : .lineSdf,
      ShaderType.lineGradient =>
        lineUsesDataDrivenPipeline(flags)
            ? .lineGradientDataDriven
            : .lineGradient,
      ShaderType.linePattern =>
        lineUsesDataDrivenPipeline(flags)
            ? .linePatternDataDriven
            : .linePattern,
      ShaderType.circle =>
        circleUsesDataDrivenPipeline(flags) ? .circleDataDriven : .circle,
      ShaderType.raster => .raster,
      ShaderType.backgroundPattern => .backgroundPattern,
      ShaderType.clippingMask => .clippingMask,
      ShaderType.fillExtrusion =>
        fillExtrusionUsesExpandedGpuLayout(flags)
            ? .fillExtrusionExpandedDataDriven
            : fillExtrusionUsesDataDrivenPipeline(flags)
            ? .fillExtrusionDataDriven
            : .fillExtrusion,
      _ =>
        drawCommandIsCrossTileMerged(flags)
            ? .fillMerged
            : shader == ShaderType.fill && fillUsesDataDrivenPipeline(flags)
            ? .fillDataDriven
            : .fill,
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
    : fillExtrusionUsesExpandedGpuLayout(flags)
    ? .fillExtrusionExpandedDataDrivenDepth
    : fillExtrusionUsesDataDrivenPipeline(flags)
    ? .fillExtrusionDataDrivenDepth
    : .fillExtrusionDepth;
