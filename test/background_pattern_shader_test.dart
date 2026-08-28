import 'dart:convert';
import 'dart:io';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/frame/command_layout.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';
import 'package:maplibre_flutter_gpu/src/frame/gpu_state.dart';

import 'support/source_files.dart';

void main() {
  test('native exports background-pattern commands and their atlas', () {
    expect(ShaderType.backgroundPattern, 12);

    final header = File(
      'vendor/maplibre-native/include/mbgl/command_export/draw_command.hpp',
    ).readAsStringSync();
    final drawable = File(
      'vendor/maplibre-native/src/mbgl/command_export/drawable.cpp',
    ).readAsStringSync();
    final bridge = File('native/src/bridge_merge.cpp').readAsStringSync();

    expect(header, contains('BackgroundPattern = 12'));
    expect(
      drawable,
      contains(
        'if (name == "BackgroundPatternShader") return '
        'ShaderType::BackgroundPattern;',
      ),
    );
    expect(
      drawable,
      contains('case ShaderType::BackgroundPattern:\n            return 4;'),
    );
    expect(drawable, contains('texSlot = shaders::idBackgroundImageTexture;'));
    expect(drawable, contains('shaders::idBackgroundPropsUBO'));
    expect(bridge, contains('c.shaderType != ShaderType::BackgroundPattern;'));
    expect(
      bridge,
      isNot(contains('cmd.shaderType == ShaderType::BackgroundPattern')),
      reason: 'tile-relative pattern phases must never be cross-tile merged',
    );
  });

  test('background-pattern shaders preserve MapLibre phase and crossfade', () {
    final manifest = jsonDecode(
      File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['BackgroundPatternVertex'], {
      'type': 'vertex',
      'file': 'background_pattern.vert',
    });
    expect(manifest['BackgroundPatternFragment'], {
      'type': 'fragment',
      'file': 'background_pattern.frag',
    });

    final vertex = File('shaders/background_pattern.vert').readAsStringSync();
    final fragment = File('shaders/background_pattern.frag').readAsStringSync();
    expect(vertex, contains('uniform BackgroundPatternDrawableUBO'));
    expect(vertex, contains('uniform BackgroundPatternPropsUBO'));
    expect(vertex, contains('pixel_coord_upper'));
    expect(vertex, contains('pixel_coord_lower'));
    expect(vertex, contains('mod(pixel_coord_upper, pattern_size) * 256.0'));
    expect(vertex, contains('256.0 + pixel_coord_lower'));
    expect(vertex, contains('props.scale_a * props.pattern_size_a'));
    expect(vertex, contains('props.scale_b * props.pattern_size_b'));

    expect(fragment, contains('uniform sampler2D u_image'));
    expect(fragment, contains('vec2 atlas_size = vec2(drawable.atlas_width'));
    expect(fragment, contains('props.pattern_tl_a / atlas_size'));
    expect(fragment, contains('props.pattern_br_b / atlas_size'));
    expect(
      fragment,
      contains(
        'frag_color = mix(color_a, color_b, props.mix_value) * '
        'props.opacity;',
      ),
    );
  });

  test('renderer binds exact UBO sizes, atlas dimensions, and sampler', () {
    final renderer = SourceFiles.renderer;
    expect(
      renderer,
      contains('ShaderType.backgroundPattern => .backgroundPattern'),
    );
    expect(rendererUboLayoutForShader(ShaderType.backgroundPattern), (
      drawableBytes: 96,
      propsBytes: 64,
      tilePropsBytes: 0,
    ));
    expect(RendererUboAbi.backgroundPatternAtlasWidthOffset, 84);
    expect(RendererUboAbi.backgroundPatternAtlasHeightOffset, 88);
    // Both texture-backed quads must reject a missing image: without one they
    // draw a hole rather than degrading to an untextured shape.
    expect(shaderRequiresTextureData(ShaderType.backgroundPattern), isTrue);
    expect(shaderRequiresTextureData(ShaderType.raster), isTrue);
    expect(shaderRequiresUploadedTexture(ShaderType.backgroundPattern), isTrue);
    expect(shaderRequiresUploadedTexture(ShaderType.raster), isTrue);
    // The fragment stage binds the drawable UBO as well as props: that is
    // where the atlas dimensions ride along in MapLibre's padding. This is the
    // only pipeline that does so, which is what fragmentDrawable records.
    expect(
      renderer,
      contains(
        RegExp(
          r"\.backgroundPattern: \([^)]*"
          r"fragmentProps: 'BackgroundPatternPropsUBO',[^)]*"
          r'fragmentDrawable: true,',
          dotAll: true,
        ),
      ),
    );
    expect(renderer, contains('pass.bindUniform(fragmentDrawable, drawable);'));
    expect(renderer, contains('pass.bindTexture('));

    final sampler = patternAtlasSamplerOptions();
    expect(sampler.minFilter, gpu.MinMagFilter.linear);
    expect(sampler.magFilter, gpu.MinMagFilter.linear);
    expect(sampler.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(sampler.heightAddressMode, gpu.SamplerAddressMode.clampToEdge);
  });
}
