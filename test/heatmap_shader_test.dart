import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/command_layout.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/pipeline_key.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';
import 'package:maplibre_flutter_gpu/src/frame/uniform_packer.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

import 'support/compact_command.dart';

void main() {
  test('heatmap paint flags preserve independent weight and radius masks', () {
    const unrelated =
        DrawCommandFlags.fillExtrusionGpuReady |
        DrawCommandFlags.lineGpuReady |
        DrawCommandFlags.circleRadiusDataDriven;
    for (final (flags, mask) in const [
      (0, 0),
      (DrawCommandFlags.heatmapWeightDataDriven, 1),
      (DrawCommandFlags.heatmapRadiusDataDriven, 2),
      (DrawCommandFlags.heatmapDataDrivenMask, 3),
    ]) {
      expect(heatmapDataDrivenMask(flags | unrelated), mask);
      expect(heatmapUsesDataDrivenPipeline(flags | unrelated), mask != 0);
      expect(
        nativeVertexStride(
          shader: ShaderType.heatmap,
          flags: flags | unrelated,
          merged: false,
        ),
        mask == 0 ? 4 : 20,
      );
      expect(gpuVertexStride(ShaderType.heatmap, flags), mask == 0 ? 8 : 24);
      expect(
        pipelineKeyFor(shader: ShaderType.heatmap, flags: flags | unrelated),
        mask == 0
            ? RenderPipelineKey.heatmap
            : RenderPipelineKey.heatmapDataDriven,
      );
    }
  });

  test('heatmap repacking keeps signed centers and both paint stops', () {
    for (final prefix in [0, 1]) {
      final storage = Uint8List(prefix + 40);
      final source = Uint8List.sublistView(storage, prefix);
      final data = ByteData.sublistView(source);
      for (var vertex = 0; vertex < 2; vertex++) {
        data.setInt16(vertex * 20, -101 + vertex, Endian.little);
        data.setInt16(vertex * 20 + 2, 16001 + vertex, Endian.little);
        for (var attribute = 0; attribute < 4; attribute++) {
          data.setFloat32(
            vertex * 20 + 4 + attribute * 4,
            vertex * 10 + attribute + 0.25,
            Endian.little,
          );
        }
      }
      final result = repackVertexDataForGpu(
        source,
        vertexCount: 2,
        sourceStride: 20,
        shader: ShaderType.heatmap,
        flags: DrawCommandFlags.heatmapRadiusDataDriven,
      );
      expect(Float32List.view(result.buffer), [
        -101,
        16001,
        0.25,
        1.25,
        2.25,
        3.25,
        -100,
        16002,
        10.25,
        11.25,
        12.25,
        13.25,
      ]);
    }
  });

  test(
    'heatmap packing retains geometry, zero paint, and the selected mask',
    () {
      for (final flags in [
        0,
        DrawCommandFlags.heatmapWeightDataDriven,
        DrawCommandFlags.heatmapRadiusDataDriven,
        DrawCommandFlags.heatmapDataDrivenMask,
      ]) {
        final source = TestCommand(
          drawableSize: 80,
          propsSize: 16,
          sections: 0,
        );
        final data = source.payloadData;
        data.setFloat32(source.drawableOffset + 64, 8, Endian.little);
        data.setFloat32(source.drawableOffset + 68, 0.25, Endian.little);
        data.setFloat32(source.drawableOffset + 72, 0.75, Endian.little);
        data.setFloat32(source.propsOffset + 4, 24, Endian.little);
        data.setUint32(source.propsOffset + 12, 0xffffffff, Endian.little);
        final output = _pack(source, ShaderType.heatmap, flags);
        final packed = ByteData.sublistView(output);
        expect(packed.getFloat32(64, Endian.little), 8);
        expect(packed.getFloat32(68, Endian.little), 0.25);
        expect(packed.getFloat32(72, Endian.little), 0.75);
        expect(packed.getFloat32(80, Endian.little), 0);
        expect(packed.getFloat32(84, Endian.little), 24);
        expect(packed.getFloat32(88, Endian.little), 0);
        expect(
          packed.getUint32(92, Endian.little),
          heatmapDataDrivenMask(flags),
        );
        expect(output.sublist(96), everyElement(0xab));
      }
    },
  );

  test(
    'heatmap composition preserves opacity without writing absent props',
    () {
      final source = TestCommand(drawableSize: 80, propsSize: 16, sections: 0);
      final data = source.payloadData;
      data.setFloat32(source.drawableOffset + 64, 0.375, Endian.little);
      final output = _pack(source, ShaderType.heatmapTexture, 0);
      expect(ByteData.sublistView(output).getFloat32(64, Endian.little), 0.375);
      expect(output.sublist(80), everyElement(0xab));
      expect(shaderRequiresUploadedTexture(ShaderType.heatmapTexture), isTrue);
      expect(shaderRequiresTextureData(ShaderType.heatmapTexture), isTrue);
      expect(
        frameNeedsMapGlobalUniform(
          lineCommandCount: 0,
          hasTriangulatedOutline: false,
          hasHeatmapTexture: true,
        ),
        isTrue,
      );
    },
  );

  test('heatmap shaders keep Gaussian accumulation separate from color', () {
    final manifest = jsonDecode(
      File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final (key, path) in const [
      ('HeatmapVertex', 'heatmap.vert'),
      ('HeatmapDDVertex', 'heatmap_dd.vert'),
      ('HeatmapFragment', 'heatmap.frag'),
      ('HeatmapTextureVertex', 'heatmap_texture.vert'),
      ('HeatmapTextureFragment', 'heatmap_texture.frag'),
    ]) {
      expect(manifest[key]['file'], path);
    }
    for (final name in ['heatmap.vert', 'heatmap_dd.vert']) {
      final vertex = File('shaders/$name').readAsStringSync();
      expect(vertex, contains('sqrt(max(-2.0 * log(ZERO / amplitude), 0.0))'));
      expect(vertex, contains('floor(a_pos * 0.5)'));
    }
    final fragment = File('shaders/heatmap.frag').readAsStringSync();
    expect(fragment, contains('-4.5 * dot(v_extrude, v_extrude)'));
    expect(fragment, contains('v_weight * props.intensity * GAUSS_COEF'));
    final composite = File('shaders/heatmap_texture.frag').readAsStringSync();
    expect(composite, contains('texture(u_image, v_pos).r'));
    expect(composite, contains('texture(u_color_ramp, vec2(density, 0.5))'));
    expect(composite, contains('frag_color = color * props.opacity;'));
  });
}

Uint8List _pack(TestCommand source, int shader, int flags) {
  final layout = rendererUboLayoutForShader(shader);
  final propsOffset = layout.drawableBytes;
  final end = propsOffset + layout.propsBytes;
  final output = Uint8List(end + 16)..fillRange(0, end + 16, 0xab);
  packCommandUniforms(
    payload: source.reader,
    destination: output,
    destinationData: ByteData.sublistView(output),
    shader: shader,
    flags: flags,
    drawableOffset: 0,
    drawableLength: layout.drawableBytes,
    propsOffset: propsOffset,
    propsLength: layout.propsBytes,
    tilePropsOffset: end,
    tilePropsLength: 0,
    devicePixelRatio: 2,
    textureWidth: 256,
    textureHeight: 1,
  );

  return output;
}
