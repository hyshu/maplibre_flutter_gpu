import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/command_layout.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/gpu_state.dart';
import 'package:maplibre_flutter_gpu/src/frame/pipeline_key.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';
import 'package:maplibre_flutter_gpu/src/frame/uniform_packer.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

import 'support/compact_command.dart';

void main() {
  test(
    'hillshade passes use the raster quad layout and distinct pipelines',
    () {
      for (final (shader, pipeline) in const [
        (ShaderType.hillshadePrepare, RenderPipelineKey.hillshadePrepare),
        (ShaderType.hillshade, RenderPipelineKey.hillshade),
      ]) {
        expect(nativeVertexStride(shader: shader, flags: 0, merged: false), 8);
        expect(gpuVertexStride(shader, 0), 16);
        expect(pipelineKeyFor(shader: shader, flags: 0), pipeline);
        expect(depthPipelineKeyFor(shader: shader, flags: 0), isNull);
        for (final prefix in [0, 1]) {
          final source = Uint8List.sublistView(Uint8List(prefix + 16), prefix);
          final data = ByteData.sublistView(source);
          data.setInt16(0, -321, Endian.little);
          data.setInt16(2, 8192, Endian.little);
          data.setUint16(4, 0, Endian.little);
          data.setUint16(6, 8192, Endian.little);
          data.setInt16(8, 8192, Endian.little);
          data.setInt16(10, -765, Endian.little);
          data.setUint16(12, 8192, Endian.little);
          data.setUint16(14, 0, Endian.little);
          final packed = repackVertexDataForGpu(
            source,
            vertexCount: 2,
            sourceStride: 8,
            shader: shader,
            flags: 0,
          );
          expect(Float32List.view(packed.buffer), [
            -321,
            8192,
            0,
            8192,
            8192,
            -765,
            8192,
            0,
          ]);
        }
      }
    },
  );

  test('only the prepare pass uploads and samples the encoded DEM', () {
    expect(shaderRequiresUploadedTexture(ShaderType.hillshadePrepare), isTrue);
    expect(shaderRequiresTextureData(ShaderType.hillshadePrepare), isTrue);
    expect(shaderRequiresUploadedTexture(ShaderType.hillshade), isFalse);
    expect(shaderRequiresTextureData(ShaderType.hillshade), isFalse);
    for (final (shader, filter) in const [
      (ShaderType.hillshadePrepare, gpu.MinMagFilter.nearest),
      (ShaderType.hillshade, gpu.MinMagFilter.linear),
    ]) {
      final sampler = samplerOptionsFor(shader, TextureFilterType.linear);
      expect(sampler.minFilter, filter);
      expect(sampler.magFilter, filter);
      expect(sampler.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
      expect(sampler.heightAddressMode, gpu.SamplerAddressMode.clampToEdge);
    }
  });

  test('prepare packing preserves the padded DEM decoding and zoom fields', () {
    expect(rendererUboLayoutForShader(ShaderType.hillshadePrepare), (
      drawableBytes: 64,
      propsBytes: 0,
      tilePropsBytes: 32,
    ));
    for (final unpack in const [
      [6553.6, 25.6, 0.1, 10000.0],
      [256.0, 1.0, 1.0 / 256.0, 32768.0],
    ]) {
      final source = _command(tileBytes: 32);
      final data = source.payloadData;
      for (var i = 0; i < 8; i++) {
        data.setFloat32(
          source.tilePropsOffset + i * 4,
          [...unpack, 258.0, 258.0, 12.0, 14.0][i],
          Endian.little,
        );
      }
      final packed = _pack(source, ShaderType.hillshadePrepare);
      expect(
        packed.sublist(0, 64),
        source.payload.sublist(
          source.drawableOffset,
          source.drawableOffset + 64,
        ),
      );
      expect(
        packed.sublist(64, 96),
        source.payload.sublist(
          source.tilePropsOffset,
          source.tilePropsOffset + 32,
        ),
      );
      expect(packed.sublist(96), everyElement(0xab));
    }
  });

  test(
    'hillshade packing retains four lights, method integers and tile state',
    () {
      expect(rendererUboLayoutForShader(ShaderType.hillshade), (
        drawableBytes: 64,
        propsBytes: 176,
        tilePropsBytes: 32,
      ));
      final source = _command(propsBytes: 176, tileBytes: 32);
      final data = source.payloadData;
      for (var i = 0; i < 44; i++) {
        data.setFloat32(source.propsOffset + i * 4, i / 8, Endian.little);
      }
      data.setFloat32(source.tilePropsOffset, 45, Endian.little);
      data.setFloat32(source.tilePropsOffset + 4, 40, Endian.little);
      data.setFloat32(source.tilePropsOffset + 8, 0.7, Endian.little);
      data.setInt32(source.tilePropsOffset + 12, 3, Endian.little);
      data.setInt32(source.tilePropsOffset + 16, 4, Endian.little);
      final packed = _pack(source, ShaderType.hillshade);
      expect(
        packed.sublist(64, 240),
        source.payload.sublist(source.propsOffset, source.propsOffset + 176),
      );
      expect(
        packed.sublist(240, 272),
        source.payload.sublist(
          source.tilePropsOffset,
          source.tilePropsOffset + 32,
        ),
      );
      expect(packed.sublist(272), everyElement(0xab));
    },
  );

  test('hillshade packing zeroes absent light and tile values', () {
    final source = _command(propsBytes: 48, tileBytes: 12);
    source.payload.fillRange(source.propsOffset, source.propsOffset + 48, 7);
    source.payload.fillRange(
      source.tilePropsOffset,
      source.tilePropsOffset + 12,
      9,
    );
    final packed = _pack(source, ShaderType.hillshade);
    expect(packed.sublist(64, 112), everyElement(7));
    expect(packed.sublist(112, 240), everyElement(0));
    expect(packed.sublist(240, 252), everyElement(9));
    expect(packed.sublist(252, 272), everyElement(0));
    expect(packed.sublist(272), everyElement(0xab));
  });

  test(
    'hillshade bundle pairs DEM preparation with corrected texture orientation',
    () {
      final manifest = jsonDecode(
        File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final (key, path) in const [
        ('HillshadePrepareVertex', 'hillshade_prepare.vert'),
        ('HillshadePrepareFragment', 'hillshade_prepare.frag'),
        ('HillshadeVertex', 'hillshade.vert'),
        ('HillshadeFragment', 'hillshade.frag'),
      ]) {
        expect(manifest[key]['file'], path);
      }
      final prepare = File('shaders/hillshade_prepare.frag').readAsStringSync();
      expect(prepare, contains('data.a = -1.0;'));
      expect(prepare, contains('dot(data, tile_props.unpack)'));
      expect(prepare, contains('deriv / 8.0 + 0.5'));
      final vertex = File('shaders/hillshade.vert').readAsStringSync();
      expect(vertex, contains('v_pos.y = 1.0 - v_pos.y;'));
      final fragment = File('shaders/hillshade.frag').readAsStringSync();
      expect(
        fragment,
        contains('(pixel.rg * 8.0 - 4.0) / cos(radians(latitude))'),
      );
      expect(fragment, contains('vec4 shadows[4];'));
      expect(fragment, contains('vec4 highlights[4];'));
      for (final (method, number) in const [
        ('COMBINED', 1),
        ('IGOR', 2),
        ('MULTIDIRECTIONAL', 3),
        ('BASIC', 4),
      ]) {
        expect(fragment, contains('const int $method = $number;'));
        expect(fragment, contains('tile_props.method == $method'));
      }
      expect(fragment, contains('frag_color = standard_hillshade(deriv);'));
    },
  );
}

TestCommand _command({int propsBytes = 0, required int tileBytes}) {
  final command = TestCommand(
    drawableSize: 64,
    propsSize: propsBytes,
    tilePropsSize: tileBytes,
    sections: 0,
  );
  for (var i = 0; i < 16; i++) {
    command.payloadData.setFloat32(
      command.drawableOffset + i * 4,
      i + 0.5,
      Endian.little,
    );
  }

  return command;
}

Uint8List _pack(TestCommand source, int shader) {
  final layout = rendererUboLayoutForShader(shader);
  final propsOffset = layout.drawableBytes;
  final tileOffset = propsOffset + layout.propsBytes;
  final end = tileOffset + layout.tilePropsBytes;
  final output = Uint8List(end + 16)..fillRange(0, end + 16, 0xab);
  packCommandUniforms(
    payload: source.reader,
    destination: output,
    destinationData: ByteData.sublistView(output),
    shader: shader,
    flags: 0,
    drawableOffset: 0,
    drawableLength: layout.drawableBytes,
    propsOffset: propsOffset,
    propsLength: layout.propsBytes,
    tilePropsOffset: tileOffset,
    tilePropsLength: layout.tilePropsBytes,
    devicePixelRatio: 2,
    textureWidth: 258,
    textureHeight: 258,
  );

  return output;
}
