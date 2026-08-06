// Decides whether a native DrawCommand is drawn, replayed as a control
// command, or dropped.
//
// A stencil clear carries no geometry but must remain in command order. It is
// classified before geometry validation so it is not mistaken for a malformed
// draw command.
//
// Kept pure so those rules can be tested directly instead of through a live
// GPU frame.
import '../native/draw_command.dart';
import 'draw_flags.dart';

/// What the decode loop should do with one command.
enum DrawCommandAdmission {
  /// Not renderable by this backend, or malformed. Skip it.
  drop,

  /// Carries no geometry but must keep its position in the command order.
  controlCommand,

  /// A normal drawable command.
  draw,
}

/// Shader types this backend can render. Anything else is dropped before any
/// other field is read.
bool rendererSupportsShader(int shader) =>
    shader == ShaderType.fill ||
    shader == ShaderType.fillOutline ||
    shader == ShaderType.fillOutlineTriangulated ||
    shader == ShaderType.fillExtrusion ||
    shader == ShaderType.background ||
    shader == ShaderType.backgroundPattern ||
    shader == ShaderType.circle ||
    shader == ShaderType.raster ||
    shader == ShaderType.clippingMask ||
    isLineShader(shader);

/// Classifies one command from the fields the decode loop reads.
///
/// [drawableMatrixM00] and [drawableMatrixM11] are diagonal entries of the
/// drawable matrix. MapLibre leaves both at zero when the drawable's tile is
/// not placed.
DrawCommandAdmission admitDrawCommand({
  required int shader,
  required int stencilMode,
  required int vertexCount,
  required int indexCount,
  required int vertexDataAddress,
  required int indexDataAddress,
  required double drawableMatrixM00,
  required double drawableMatrixM11,
}) {
  if (!rendererSupportsShader(shader)) return DrawCommandAdmission.drop;

  // Checked before the geometry rules, which it would otherwise fail.
  if (stencilMode == StencilModeType.clear) {
    return DrawCommandAdmission.controlCommand;
  }

  if (vertexCount == 0 || indexCount == 0) return DrawCommandAdmission.drop;
  if (vertexDataAddress == 0 || indexDataAddress == 0) {
    return DrawCommandAdmission.drop;
  }
  if (drawableMatrixM00 == 0 && drawableMatrixM11 == 0) {
    return DrawCommandAdmission.drop;
  }
  return DrawCommandAdmission.draw;
}
