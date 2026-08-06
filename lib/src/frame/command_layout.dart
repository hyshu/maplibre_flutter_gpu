// Layout and resource decisions for commands in a native DrawCommand buffer.
//
// These rules determine the vertex size, texture requirements, and whether a
// frame needs a depth/stencil attachment. Each rule is a pure function of ABI
// fields and can be tested without a live GPU frame.
//
// The rules are not bundled into a decoded-command object. Creating one object
// per command would add allocation to the render path.
import '../native/draw_command.dart';
import 'draw_flags.dart';

/// Bytes per vertex as exported by the native side, before the renderer
/// repacks packed integer attributes into floats.
///
/// The renderer compares this against `DrawCommand.vertexStride` and drops the
/// command when they disagree, so a wrong value here silently removes geometry
/// instead of drawing it incorrectly. See [gpuVertexStride] for the stride the
/// Flutter GPU pipeline consumes after repacking.
int nativeVertexStride({
  required int shader,
  required int flags,
  required bool merged,
}) {
  // Merged buffers are rewritten natively into a bare float2, whatever the
  // shader's own layout would be.
  if (merged) return mergedVertexStride;

  return switch (shader) {
    ShaderType.fillExtrusion => fillExtrusionVertexStride(flags),
    ShaderType.fill => fillVertexStride(flags),
    ShaderType.circle => circleVertexStride(flags),
    ShaderType.fillOutlineTriangulated => fillOutlineVertexStride(flags),
    ShaderType.line ||
    ShaderType.lineSDF ||
    ShaderType.lineGradient ||
    ShaderType.linePattern => lineVertexStride(flags),
    // Raster quads carry a position and a texture coordinate pair.
    ShaderType.raster => 8,
    // Background, background-pattern, basic fill-outline, and clipping masks
    // all draw from a bare position.
    _ => 4,
  };
}

/// Whether a command cannot be drawn once its texture upload has failed.
///
/// Applies when the command carries texture bytes. A line variant without its
/// dash atlas or gradient ramp would sample garbage, and a raster or pattern
/// quad would have nothing to show at all.
bool shaderRequiresUploadedTexture(int shader) =>
    shader == ShaderType.lineSDF ||
    shader == ShaderType.linePattern ||
    shader == ShaderType.lineGradient ||
    shader == ShaderType.raster ||
    shader == ShaderType.backgroundPattern;

/// Whether a command cannot be drawn when it carries no texture bytes at all.
///
/// Narrower than [shaderRequiresUploadedTexture] on purpose. A line variant
/// that exports no texture can still render untextured. A raster or pattern
/// quad without an image has nothing to draw, so it is dropped.
bool shaderRequiresTextureData(int shader) =>
    shader == ShaderType.raster || shader == ShaderType.backgroundPattern;

/// Whether this command forces the frame to allocate a depth/stencil target.
///
/// Fill extrusion needs depth for its prepass, any command MapLibre resolved to
/// a depth test needs it too. Every stencil mode also needs the stencil aspect,
/// including the ordered clear.
bool commandNeedsDepthStencil({
  required int shader,
  required int flags,
  required int stencilMode,
}) =>
    shader == ShaderType.fillExtrusion ||
    drawCommandUsesDepth(flags) ||
    stencilMode != StencilModeType.disabled;

/// Whether the frame must bind `GlobalPaintParamsUBO`.
///
/// The line family and triangulated fill outlines read viewport-space values
/// from it. Frames without those commands do not need the uniform.
bool frameNeedsMapGlobalUniform({
  required int lineCommandCount,
  required bool hasTriangulatedOutline,
}) => lineCommandCount > 0 || hasTriangulatedOutline;
