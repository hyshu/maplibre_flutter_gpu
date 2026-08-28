import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';
import 'package:maplibre_flutter_gpu/src/frame/uniform_packer.dart';

/// One native command, with whatever UBO bytes a test wants to hand it.
class _Command {
  new({
    required this.shader,
    this.flags = 0,
    List<int>? drawableUbo,
    List<int>? propsUbo,
    int? propsUboSize,
    List<int>? tilePropsUbo,
    int? tilePropsUboSize,
    this.cameraDistance = 0,
  }) : bytes = .new(DrawCommandAbi.size) {
    data = .sublistView(bytes);
    // An identity-ish matrix, so the drawable copy is recognizable.
    for (var i = 0; i < 16; i++) {
      data.setFloat32(
        DrawCommandAbi.drawableUBO + i * 4,
        i.toDouble(),
        Endian.little,
      );
    }
    if (drawableUbo != null) {
      bytes.setRange(
        DrawCommandAbi.drawableUBO,
        DrawCommandAbi.drawableUBO + drawableUbo.length,
        drawableUbo,
      );
    }
    if (propsUbo != null) {
      bytes.setRange(
        DrawCommandAbi.propsUBO,
        DrawCommandAbi.propsUBO + propsUbo.length,
        propsUbo,
      );
    }
    data.setUint32(
      DrawCommandAbi.propsUBOSize,
      propsUboSize ?? propsUbo?.length ?? 0,
      Endian.little,
    );
    if (tilePropsUbo != null) {
      bytes.setRange(
        DrawCommandAbi.tilePropsUBO,
        DrawCommandAbi.tilePropsUBO + tilePropsUbo.length,
        tilePropsUbo,
      );
    }
    data.setUint32(
      DrawCommandAbi.tilePropsUBOSize,
      tilePropsUboSize ?? tilePropsUbo?.length ?? 0,
      Endian.little,
    );
    data.setFloat32(
      DrawCommandAbi.cameraDistance,
      cameraDistance,
      Endian.little,
    );
  }

  final int shader;
  final int flags;
  final double cameraDistance;
  final Uint8List bytes;
  late final ByteData data;
}

/// Packs [command] into a zeroed buffer laid out the way the renderer lays one
/// out: drawable first, then evaluated props, then tile props.
({Uint8List bytes, ByteData data, int props, int tileProps}) _pack(
  _Command command, {
  double devicePixelRatio = 2,
  int textureWidth = 0,
  int textureHeight = 0,
}) {
  final layout = rendererUboLayoutForShader(command.shader);
  const drawableOffset = 0;
  final propsOffset = drawableOffset + layout.drawableBytes;
  final tilePropsOffset = propsOffset + layout.propsBytes;
  final destination = Uint8List(tilePropsOffset + layout.tilePropsBytes + 16);
  destination.fillRange(0, tilePropsOffset + layout.tilePropsBytes, 0xab);
  final destinationData = ByteData.sublistView(destination);

  packCommandUniforms(
    source: command.bytes,
    sourceData: command.data,
    commandOffset: 0,
    destination: destination,
    destinationData: destinationData,
    shader: command.shader,
    flags: command.flags,
    drawableOffset: drawableOffset,
    drawableLength: layout.drawableBytes,
    propsOffset: propsOffset,
    propsLength: layout.propsBytes,
    tilePropsOffset: tilePropsOffset,
    tilePropsLength: layout.tilePropsBytes,
    devicePixelRatio: devicePixelRatio,
    textureWidth: textureWidth,
    textureHeight: textureHeight,
  );

  return (
    bytes: destination,
    data: destinationData,
    props: propsOffset,
    tileProps: tilePropsOffset,
  );
}

void main() {
  test('every bound byte is initialized without a pre-clear', () {
    for (final shader in [
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
      final layout = rendererUboLayoutForShader(shader);
      final boundLength =
          layout.drawableBytes + layout.propsBytes + layout.tilePropsBytes;
      final packed = _pack(.new(shader: shader));
      expect(
        packed.bytes.sublist(0, boundLength),
        isNot(contains(0xab)),
        reason: 'shader $shader left stale bytes in a bound UBO',
      );
    }
  });

  group('drawable matrix', () {
    test('is copied verbatim for every shader', () {
      for (final shader in [
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
        final command = _Command(shader: shader);
        final packed = _pack(command, textureWidth: 64, textureHeight: 64);
        for (var i = 0; i < 16; i++) {
          expect(
            packed.data.getFloat32(i * 4, Endian.little),
            i.toDouble(),
            reason: 'shader $shader matrix element $i',
          );
        }
      }
    });

    test('is the only thing a clipping mask receives', () {
      // The mask writes no color, so anything beyond the matrix would be
      // uniform bytes nothing reads.
      final packed = _pack(
        .new(shader: ShaderType.clippingMask, propsUbo: .filled(48, 0xab)),
      );
      for (
        var i = RendererUboAbi.drawableMatrixBytes;
        i < packed.bytes.length;
        i++
      ) {
        expect(packed.bytes[i], 0, reason: 'byte $i should be untouched');
      }
    });
  });

  group('fill family evaluated props', () {
    test('repacks background opacity into the fill layout', () {
      // Background stores opacity at byte 16 (it has no outline color), fill
      // at 32. Both must arrive at the fill layout's offset.
      final props = Uint8List(48);
      final propsData = ByteData.sublistView(props);
      propsData.setFloat32(0, 0.25, Endian.little); // color.r
      propsData.setFloat32(
        RendererUboAbi.backgroundOpacityOffset,
        0.5,
        Endian.little,
      );

      final packed = _pack(
        .new(shader: ShaderType.background, propsUbo: props, propsUboSize: 20),
      );

      expect(
        packed.data.getFloat32(
          packed.props + RendererUboAbi.fillColorOffset,
          Endian.little,
        ),
        0.25,
      );
      expect(
        packed.data.getFloat32(
          packed.props + RendererUboAbi.fillOpacityOffset,
          Endian.little,
        ),
        0.5,
      );
    });

    test('keeps a real zero opacity from the style', () {
      final props = Uint8List(48);
      ByteData.sublistView(props)
          .setFloat32(RendererUboAbi.fillOpacityOffset, 0, Endian.little);

      final packed = _pack(
        .new(shader: ShaderType.fill, propsUbo: props, propsUboSize: 48),
      );

      expect(
        packed.data.getFloat32(
          packed.props + RendererUboAbi.fillOpacityOffset,
          Endian.little,
        ),
        0,
      );
    });

    test('falls back to opaque white when the props UBO is too short', () {
      // Distinguishes "the style said zero" from "the field was not exported".
      final packed = _pack(
        .new(shader: ShaderType.fill, propsUbo: [], propsUboSize: 0),
      );

      for (var component = 0; component < 4; component++) {
        expect(
          packed.data.getFloat32(
            packed.props +
                RendererUboAbi.fillColorOffset +
                component * RendererUboAbi.float32Bytes,
            Endian.little,
          ),
          1.0,
          reason: 'color component $component',
        );
      }
      expect(
        packed.data.getFloat32(
          packed.props + RendererUboAbi.fillOpacityOffset,
          Endian.little,
        ),
        1.0,
      );
    });

    test('carries the data-driven mask in fill drawable padding', () {
      final packed = _pack(
        .new(
          shader: ShaderType.fill,
          flags:
              DrawCommandFlags.fillColorDataDriven |
              DrawCommandFlags.fillOpacityDataDriven,
        ),
      );

      expect(
        packed.data.getUint32(
          RendererUboAbi.fillDataDrivenMaskOffset,
          Endian.little,
        ),
        0x3,
      );
    });

    test('leaves the mask carrier alone for a non-data-driven fill', () {
      final packed = _pack(.new(shader: ShaderType.fill));
      expect(
        packed.data.getUint32(
          RendererUboAbi.fillDataDrivenMaskOffset,
          Endian.little,
        ),
        0,
      );
    });
  });

  group('triangulated fill outline', () {
    test('carries the device pixel ratio in drawable padding', () {
      final packed = _pack(
        .new(shader: ShaderType.fillOutlineTriangulated),
        devicePixelRatio: 3,
      );

      expect(
        packed.data.getFloat32(
          RendererUboAbi.fillOutlineDevicePixelRatioOffset,
          Endian.little,
        ),
        3,
      );
    });

    test('reinterprets the props fade field as its data-driven mask', () {
      final packed = _pack(
        .new(
          shader: ShaderType.fillOutlineTriangulated,
          flags: DrawCommandFlags.fillOutlineColorDataDriven,
        ),
      );

      expect(
        packed.data.getUint32(
          packed.props + RendererUboAbi.fillOutlineDataDrivenMaskOffset,
          Endian.little,
        ),
        0x1,
      );
    });
  });

  group('circle', () {
    test('patches camera distance and device pixel ratio into padding', () {
      final packed = _pack(
        .new(shader: ShaderType.circle, cameraDistance: 12.5),
        devicePixelRatio: 2.5,
      );

      expect(
        packed.data.getFloat32(
          RendererUboAbi.circleCameraDistanceOffset,
          Endian.little,
        ),
        12.5,
      );
      expect(
        packed.data.getFloat32(
          RendererUboAbi.circleDevicePixelRatioOffset,
          Endian.little,
        ),
        2.5,
      );
    });

    test('carries the seven-bit mask in props padding', () {
      final packed = _pack(
        .new(
          shader: ShaderType.circle,
          flags: DrawCommandFlags.circleDataDrivenMask,
        ),
      );

      expect(
        packed.data.getUint32(
          packed.props + RendererUboAbi.circleDataDrivenMaskOffset,
          Endian.little,
        ),
        0x7f,
      );
    });
  });

  group('line family', () {
    test('patches the device pixel ratio at the per-variant offset', () {
      // Plain and gradient lines read byte 92; SDF's larger drawable moves it
      // to 120. Writing the wrong one silently mis-scales every line.
      for (final shader in [ShaderType.line, ShaderType.lineGradient]) {
        final packed = _pack(.new(shader: shader), devicePixelRatio: 4);
        expect(
          packed.data.getFloat32(
            RendererUboAbi.lineDevicePixelRatioOffset,
            Endian.little,
          ),
          4,
          reason: 'shader $shader',
        );
      }

      final sdf = _pack(.new(shader: ShaderType.lineSDF), devicePixelRatio: 4);
      expect(
        sdf.data.getFloat32(
          RendererUboAbi.lineSdfDevicePixelRatioOffset,
          Endian.little,
        ),
        4,
      );
    });

    test('defaults opacity and width only when the props UBO omits them', () {
      final short = _pack(
        .new(shader: ShaderType.line, propsUbo: [], propsUboSize: 0),
      );
      expect(
        short.data.getFloat32(
          short.props + RendererUboAbi.lineOpacityOffset,
          Endian.little,
        ),
        1.0,
      );
      expect(
        short.data.getFloat32(
          short.props + RendererUboAbi.lineWidthOffset,
          Endian.little,
        ),
        1.0,
      );

      // A style that really sets zero width must survive.
      final props = Uint8List(48);
      final full = _pack(
        .new(shader: ShaderType.line, propsUbo: props, propsUboSize: 48),
      );
      expect(
        full.data.getFloat32(
          full.props + RendererUboAbi.lineWidthOffset,
          Endian.little,
        ),
        0,
      );
    });

    test('carries the eight-bit mask in the props expression field', () {
      final packed = _pack(
        .new(
          shader: ShaderType.line,
          flags: DrawCommandFlags.lineDataDrivenMask,
        ),
      );

      expect(
        packed.data.getUint32(
          packed.props + RendererUboAbi.lineDataDrivenMaskOffset,
          Endian.little,
        ),
        0xff,
      );
    });

    test('copies tile props for the variants that have them', () {
      final tileProps = Uint8List(16);
      ByteData.sublistView(tileProps).setFloat32(0, 7.5, Endian.little);

      final packed = _pack(
        .new(
          shader: ShaderType.lineSDF,
          tilePropsUbo: tileProps,
          tilePropsUboSize: 16,
        ),
      );

      expect(packed.data.getFloat32(packed.tileProps, Endian.little), 7.5);
    });
  });

  group('fill extrusion', () {
    test('carries the color mask in drawable padding', () {
      final packed = _pack(
        .new(
          shader: ShaderType.fillExtrusion,
          flags:
              DrawCommandFlags.fillExtrusionDataDriven |
              DrawCommandFlags.fillExtrusionColorDataDriven,
        ),
      );

      expect(
        packed.data.getUint32(
          RendererUboAbi.fillExtrusionDataDrivenMaskOffset,
          Endian.little,
        ),
        0x1,
      );
    });

    test('copies its evaluated props verbatim', () {
      final props = Uint8List(80);
      ByteData.sublistView(props).setFloat32(
        RendererUboAbi.fillExtrusionOpacityOffset,
        0.75,
        Endian.little,
      );

      final packed = _pack(
        .new(
          shader: ShaderType.fillExtrusion,
          propsUbo: props,
          propsUboSize: 80,
        ),
      );

      expect(
        packed.data.getFloat32(
          packed.props + RendererUboAbi.fillExtrusionOpacityOffset,
          Endian.little,
        ),
        0.75,
      );
    });
  });

  group('background pattern', () {
    test('writes the atlas size into native drawable padding', () {
      // MapLibre leaves bytes 84/88 unused; the Flutter fragment shader reads
      // the atlas dimensions from them instead of a global paint UBO.
      final packed = _pack(
        .new(shader: ShaderType.backgroundPattern),
        textureWidth: 512,
        textureHeight: 256,
      );

      expect(
        packed.data.getFloat32(
          RendererUboAbi.backgroundPatternAtlasWidthOffset,
          Endian.little,
        ),
        512,
      );
      expect(
        packed.data.getFloat32(
          RendererUboAbi.backgroundPatternAtlasHeightOffset,
          Endian.little,
        ),
        256,
      );
    });
  });

  group('raster', () {
    test('copies evaluated props and nothing else past the matrix', () {
      final props = Uint8List(64);
      ByteData.sublistView(props).setFloat32(0, 1.5, Endian.little);

      final packed = _pack(
        .new(shader: ShaderType.raster, propsUbo: props, propsUboSize: 64),
      );

      expect(packed.data.getFloat32(packed.props, Endian.little), 1.5);
      // RasterDrawableUBO is only the matrix.
      expect(
        packed.bytes.sublist(RendererUboAbi.drawableMatrixBytes, packed.props),
        everyElement(0),
      );
    });
  });

  group('props copy length', () {
    test('never reads past the exported size', () {
      // A short export must not pull neighbouring command bytes into the UBO.
      final props = Uint8List(48);
      for (var i = 0; i < props.length; i++) {
        props[i] = 0xff;
      }
      final packed = _pack(
        .new(shader: ShaderType.circle, propsUbo: props, propsUboSize: 8),
      );

      for (var i = 8; i < 64; i++) {
        expect(
          packed.bytes[packed.props + i],
          anyOf(0, isNot(0xff)),
          reason: 'byte $i beyond the exported props size',
        );
      }
    });
  });
}
