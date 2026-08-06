import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_command_admission.dart';

/// A well-formed drawable command, so each test can vary one field.
DrawCommandAdmission _admit({
  int shader = ShaderType.fill,
  int stencilMode = StencilModeType.disabled,
  int vertexCount = 4,
  int indexCount = 6,
  int vertexDataAddress = 0x1000,
  int indexDataAddress = 0x2000,
  double drawableMatrixM00 = 1,
  double drawableMatrixM11 = 1,
}) => admitDrawCommand(
  shader: shader,
  stencilMode: stencilMode,
  vertexCount: vertexCount,
  indexCount: indexCount,
  vertexDataAddress: vertexDataAddress,
  indexDataAddress: indexDataAddress,
  drawableMatrixM00: drawableMatrixM00,
  drawableMatrixM11: drawableMatrixM11,
);

void main() {
  group('mid-frame stencil clear', () {
    // This is the case the renderer's visual baselines cannot cover: the
    // command writes no color, so dropping it changes no pixel in a
    // screenshot while breaking MapLibre's stencil-overflow handling.
    test('survives having no geometry at all', () {
      expect(
        _admit(
          shader: ShaderType.clippingMask,
          stencilMode: StencilModeType.clear,
          vertexCount: 0,
          indexCount: 0,
          vertexDataAddress: 0,
          indexDataAddress: 0,
          drawableMatrixM00: 0,
          drawableMatrixM11: 0,
        ),
        DrawCommandAdmission.controlCommand,
      );
    });

    test('is classified before the geometry rules, not after', () {
      // Same command with any other stencil mode is dropped, which is what
      // makes the ordering of the two checks observable.
      expect(
        _admit(
          shader: ShaderType.clippingMask,
          stencilMode: StencilModeType.clippingMask,
          vertexCount: 0,
          indexCount: 0,
          vertexDataAddress: 0,
          indexDataAddress: 0,
        ),
        DrawCommandAdmission.drop,
      );
    });

    test('is still dropped when its shader is unsupported', () {
      // The shader whitelist runs first, so an unknown shader cannot smuggle
      // itself in by claiming to be a clear.
      expect(
        _admit(shader: ShaderType.unknown, stencilMode: StencilModeType.clear),
        DrawCommandAdmission.drop,
      );
    });
  });

  group('shader whitelist', () {
    test('admits every shader the renderer has a pipeline for', () {
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
        ShaderType.line,
        ShaderType.lineSDF,
        ShaderType.lineGradient,
        ShaderType.linePattern,
      ]) {
        expect(
          _admit(shader: shader),
          DrawCommandAdmission.draw,
          reason: 'shader $shader should be renderable',
        );
      }
    });

    test('drops shaders this backend cannot render', () {
      expect(_admit(shader: ShaderType.unknown), DrawCommandAdmission.drop);
      expect(_admit(shader: 99), DrawCommandAdmission.drop);
    });
  });

  group('malformed geometry', () {
    test('drops a command missing vertices or indices', () {
      expect(_admit(vertexCount: 0), DrawCommandAdmission.drop);
      expect(_admit(indexCount: 0), DrawCommandAdmission.drop);
    });

    test('drops a command whose buffers are null', () {
      expect(_admit(vertexDataAddress: 0), DrawCommandAdmission.drop);
      expect(_admit(indexDataAddress: 0), DrawCommandAdmission.drop);
    });

    test('drops a drawable whose matrix diagonal is entirely zero', () {
      expect(
        _admit(drawableMatrixM00: 0, drawableMatrixM11: 0),
        DrawCommandAdmission.drop,
      );
    });

    test('keeps a drawable with only one zero on the diagonal', () {
      // A 90-degree rotation zeroes one diagonal entry. Requiring both to be
      // zero is what keeps rotated tiles from being discarded.
      expect(
        _admit(drawableMatrixM00: 0, drawableMatrixM11: 1),
        DrawCommandAdmission.draw,
      );
      expect(
        _admit(drawableMatrixM00: 1, drawableMatrixM11: 0),
        DrawCommandAdmission.draw,
      );
    });
  });
}
