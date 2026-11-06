import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/pipeline_key.dart';
import 'package:maplibre_flutter_gpu/src/frame/tile_batch.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';
import 'package:maplibre_flutter_gpu/src/frame/uniform_packer.dart';
import 'package:maplibre_flutter_gpu/src/gpu/command_decoder.dart';
import 'package:maplibre_flutter_gpu/src/gpu/draw_entry.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/command_payload.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

import 'support/compact_command.dart';

const _members = 3;
const _lineDrawable = RendererUboAbi.lineDrawableBytes;

/// A batched line command whose payload holds [_members] drawables, each
/// with a distinct matrix diagonal, followed by the member table.
TestCommand _batchedLine() {
  const table = _members * RendererUboAbi.tileBatchTableEntryBytes;
  final command = TestCommand(
    drawableSize: _members * _lineDrawable + table,
    propsSize: RendererUboAbi.linePropsBytes,
    sections: CommandPayloadSections.stencil,
  );
  command.data
    ..setUint32(DrawCommandAbi.shaderType, ShaderType.line, .little)
    ..setUint32(DrawCommandAbi.flags, DrawCommandFlags.tileBatched, .little);
  for (var member = 0; member < _members; member++) {
    final base = command.drawableOffset + member * _lineDrawable;
    // Identity-like matrix with a member-specific scale on the diagonal.
    for (var diagonal = 0; diagonal < 4; diagonal++) {
      command.payloadData.setFloat32(
        base + diagonal * 20,
        member + 1.0,
        .little,
      );
    }
    // u_ratio is the first float after the matrix.
    command.payloadData.setFloat32(base + 64, 10.0 * (member + 1), .little);
  }
  final tableOffset = command.drawableOffset + _members * _lineDrawable;
  for (var member = 0; member < _members; member++) {
    command.payloadData
      ..setUint32(
        tableOffset + member * RendererUboAbi.tileBatchTableEntryBytes,
        member * 100,
        .little,
      )
      ..setUint32(
        tableOffset + member * RendererUboAbi.tileBatchTableEntryBytes + 4,
        member + 7,
        .little,
      );
  }

  return command;
}

DrawEntry _entry(TestCommand command, {int flags = 0, int shader = 0}) =>
    DrawEntry(
      0,
      shader,
      DrawModeType.triangles,
      flags,
      0,
      0,
      0,
      null,
      null,
      null,
      TextureFilterType.linear,
      0,
      StencilModeType.disabled,
    );

void main() {
  test('member count follows the payload size and the batch flag', () {
    expect(
      tileBatchMemberCount(
        shader: ShaderType.line,
        flags: 0,
        drawableSize: _lineDrawable,
      ),
      0,
    );
    expect(
      tileBatchMemberCount(
        shader: ShaderType.line,
        flags: DrawCommandFlags.tileBatched,
        drawableSize:
            _members *
            (_lineDrawable + RendererUboAbi.tileBatchTableEntryBytes),
      ),
      _members,
    );
    expect(
      tileBatchMemberCount(
        shader: ShaderType.line,
        flags: DrawCommandFlags.tileBatched,
        drawableSize: _lineDrawable + 3,
      ),
      0,
    );
    expect(
      tileBatchMemberCount(
        shader: ShaderType.fill,
        flags: DrawCommandFlags.tileBatched,
        drawableSize:
            (RendererUboAbi.tileBatchMembers + 1) *
            (RendererUboAbi.fillDrawableBytes +
                RendererUboAbi.tileBatchTableEntryBytes),
      ),
      0,
    );
  });

  test('batched entries reserve every member and a batch range', () {
    final entry = _entry(
      TestCommand(),
      flags: DrawCommandFlags.tileBatched,
      shader: ShaderType.lineSDF,
    );
    final next = assignUniformRanges(entry, 0, 16);
    expect(
      entry.drawableUniformLength,
      RendererUboAbi.tileBatchMembers * RendererUboAbi.lineSdfDrawableBytes,
    );
    expect(entry.propsUniformLength, RendererUboAbi.linePropsBytes);
    expect(
      entry.tilePropsUniformLength,
      RendererUboAbi.tileBatchMembers * RendererUboAbi.lineSdfTilePropsBytes,
    );
    expect(entry.batchUniformLength, RendererUboAbi.tileBatchBytes);
    expect(
      entry.batchUniformOffset,
      greaterThanOrEqualTo(
        entry.tilePropsUniformOffset + entry.tilePropsUniformLength,
      ),
    );
    expect(next, entry.batchUniformOffset + RendererUboAbi.tileBatchBytes);

    final single = _entry(TestCommand(), shader: ShaderType.lineSDF);
    assignUniformRanges(single, 0, 16);
    expect(single.drawableUniformLength, RendererUboAbi.lineSdfDrawableBytes);
    expect(single.batchUniformLength, 0);
  });

  test('batched pipelines replace their per-tile variants', () {
    expect(
      pipelineKeyFor(
        shader: ShaderType.line,
        flags: DrawCommandFlags.tileBatched,
      ),
      RenderPipelineKey.lineBatched,
    );
    expect(
      pipelineKeyFor(
        shader: ShaderType.line,
        flags:
            DrawCommandFlags.tileBatched | DrawCommandFlags.lineColorDataDriven,
      ),
      RenderPipelineKey.lineDataDrivenBatched,
    );
    expect(
      pipelineKeyFor(
        shader: ShaderType.fill,
        flags: DrawCommandFlags.tileBatched,
      ),
      RenderPipelineKey.fillBatched,
    );
    expect(
      pipelineKeyFor(
        shader: ShaderType.circle,
        flags:
            DrawCommandFlags.tileBatched |
            DrawCommandFlags.circleColorDataDriven,
      ),
      RenderPipelineKey.circleDataDrivenBatched,
    );
    // Shaders without a batched variant keep their per-tile pipeline.
    expect(
      pipelineKeyFor(
        shader: ShaderType.raster,
        flags: DrawCommandFlags.tileBatched,
      ),
      RenderPipelineKey.raster,
    );
  });

  test('batched uniforms carry every member and the member table', () {
    final command = _batchedLine();
    final entry = _entry(
      command,
      flags: DrawCommandFlags.tileBatched,
      shader: ShaderType.line,
    );
    final total = assignUniformRanges(entry, 0, 16);
    final destination = Uint8List(total);
    final destinationData = ByteData.sublistView(destination);
    packTileBatchUniforms(
      payload: command.reader,
      destination: destination,
      destinationData: destinationData,
      shader: ShaderType.line,
      flags: DrawCommandFlags.tileBatched,
      memberCount: _members,
      drawableOffset: entry.drawableUniformOffset,
      drawableLength: entry.drawableUniformLength,
      propsOffset: entry.propsUniformOffset,
      propsLength: entry.propsUniformLength,
      tilePropsOffset: entry.tilePropsUniformOffset,
      tilePropsLength: entry.tilePropsUniformLength,
      batchOffset: entry.batchUniformOffset,
      devicePixelRatio: 2,
      textureWidth: 0,
      textureHeight: 0,
      maskWidth: 640,
      maskHeight: 480,
    );
    for (var member = 0; member < _members; member++) {
      final base = entry.drawableUniformOffset + member * _lineDrawable;
      // The x scale survives the depth range conversion untouched.
      expect(destinationData.getFloat32(base, .little), member + 1.0);
      expect(
        destinationData.getFloat32(base + 64, .little),
        10.0 * (member + 1),
      );
      // Line drawables receive the device pixel ratio in their last float.
      expect(destinationData.getFloat32(base + 92, .little), 2.0);
    }
    final batch = entry.batchUniformOffset;
    expect(
      destinationData.getFloat32(
        batch + RendererUboAbi.tileBatchMaskWidthOffset,
        .little,
      ),
      640,
    );
    expect(
      destinationData.getFloat32(
        batch + RendererUboAbi.tileBatchMaskHeightOffset,
        .little,
      ),
      480,
    );
    expect(
      destinationData.getFloat32(
        batch + RendererUboAbi.tileBatchMemberCountOffset,
        .little,
      ),
      _members,
    );
    for (var member = 0; member < _members; member++) {
      expect(
        destinationData.getFloat32(
          batch + RendererUboAbi.tileBatchStartsOffset + member * 4,
          .little,
        ),
        member * 100,
      );
      expect(
        destinationData.getFloat32(
          batch + RendererUboAbi.tileBatchIdsOffset + member * 4,
          .little,
        ),
        member + 7,
      );
    }
    // Members beyond the count stay zero.
    expect(
      destinationData.getFloat32(
        batch + RendererUboAbi.tileBatchStartsOffset + _members * 4,
        .little,
      ),
      0,
    );
  });

  test('clipping masks pack their clip reference for the tile mask pass', () {
    final command = TestCommand(
      drawableSize: RendererUboAbi.clippingMaskDrawableBytes,
      propsSize: 0,
      sections: CommandPayloadSections.stencil,
    );
    command.data.setUint32(
      DrawCommandAbi.shaderType,
      ShaderType.clippingMask,
      .little,
    );
    command.payloadData.setUint32(
      command.stencilOffset + CommandStencilAbi.reference,
      9,
      .little,
    );
    expect(command.reader.read(command.data, 0), isTrue);
    final entry = _entry(command, shader: ShaderType.clippingMask);
    final total = assignUniformRanges(entry, 0, 16);
    expect(entry.propsUniformLength, RendererUboAbi.tileMaskIdBytes);
    final destination = Uint8List(total);
    final destinationData = ByteData.sublistView(destination);
    packCommandUniforms(
      payload: command.reader,
      destination: destination,
      destinationData: destinationData,
      shader: ShaderType.clippingMask,
      flags: 0,
      drawableOffset: entry.drawableUniformOffset,
      drawableLength: entry.drawableUniformLength,
      propsOffset: entry.propsUniformOffset,
      propsLength: entry.propsUniformLength,
      tilePropsOffset: 0,
      tilePropsLength: 0,
      devicePixelRatio: 1,
      textureWidth: 0,
      textureHeight: 0,
    );
    expect(destinationData.getFloat32(entry.propsUniformOffset, .little), 9);
  });
}
