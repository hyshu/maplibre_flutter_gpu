import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color, TextDirection;

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/labels/label_data.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/label_export_decoder.dart';

class _Export {
  _Export() : bytes = Uint8List(LabelExportAbi.size) {
    data = ByteData.sublistView(bytes);
  }

  final Uint8List bytes;
  late final ByteData data;

  void f64(int offset, double value) =>
      data.setFloat64(offset, value, Endian.little);
  void f32(int offset, double value) =>
      data.setFloat32(offset, value, Endian.little);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  void i32(int offset, int value) =>
      data.setInt32(offset, value, Endian.little);

  void string(_Blob blob, int offsetField, int lengthField, String value) {
    final ref = blob.string(value);
    u32(offsetField, ref.offset);
    u32(lengthField, ref.length);
  }
}

class _SplitExport {
  _SplitExport(int size) : bytes = Uint8List(size) {
    data = ByteData.sublistView(bytes);
  }

  final Uint8List bytes;
  late final ByteData data;

  void f64(int offset, double value) =>
      data.setFloat64(offset, value, Endian.little);
  void f32(int offset, double value) =>
      data.setFloat32(offset, value, Endian.little);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  void i32(int offset, int value) =>
      data.setInt32(offset, value, Endian.little);

  void string(_Blob blob, int offsetField, int lengthField, String value) {
    final ref = blob.string(value);
    u32(offsetField, ref.offset);
    u32(lengthField, ref.length);
  }
}

class _Blob {
  final List<int> _bytes = <int>[];

  ({int offset, int length}) string(String value) {
    final encoded = utf8.encode(value);
    final offset = _bytes.length;
    _bytes.addAll(encoded);

    return (offset: offset, length: encoded.length);
  }

  int fonts(List<String> fonts) {
    final refs = fonts.map(string).toList(growable: false);
    _align(4);
    final offset = _bytes.length;
    final records = Uint8List(refs.length * LabelStringRefExportAbi.size);
    final data = ByteData.sublistView(records);
    for (var index = 0; index < refs.length; index++) {
      final record = index * LabelStringRefExportAbi.size;
      data
        ..setUint32(
          record + LabelStringRefExportAbi.offset,
          refs[index].offset,
          Endian.little,
        )
        ..setUint32(
          record + LabelStringRefExportAbi.length,
          refs[index].length,
          Endian.little,
        );
    }
    _bytes.addAll(records);

    return offset;
  }

  int section({
    required int start,
    required int end,
    required List<String> fonts,
    String? image,
  }) {
    final fontsOffset = this.fonts(fonts);
    final imageRef = image == null ? null : string(image);
    _align(4);
    final offset = _bytes.length;
    final record = Uint8List(LabelTextSectionExportAbi.size);
    final data = ByteData.sublistView(record);
    data
      ..setUint32(LabelTextSectionExportAbi.start, start, Endian.little)
      ..setUint32(LabelTextSectionExportAbi.end, end, Endian.little)
      ..setFloat32(LabelTextSectionExportAbi.fontScale, 1.5, Endian.little)
      ..setUint32(
        LabelTextSectionExportAbi.flags,
        1 | (image == null ? 0 : 2),
        Endian.little,
      )
      ..setFloat32(LabelTextSectionExportAbi.colorR, 0.25, Endian.little)
      ..setFloat32(LabelTextSectionExportAbi.colorG, 0.125, Endian.little)
      ..setFloat32(LabelTextSectionExportAbi.colorB, 0, Endian.little)
      ..setFloat32(LabelTextSectionExportAbi.colorA, 0.5, Endian.little)
      ..setUint32(
        LabelTextSectionExportAbi.fontsOffset,
        fontsOffset,
        Endian.little,
      )
      ..setUint32(
        LabelTextSectionExportAbi.fontCount,
        fonts.length,
        Endian.little,
      );
    if (imageRef != null) {
      data
        ..setUint32(
          LabelTextSectionExportAbi.imageOffset,
          imageRef.offset,
          Endian.little,
        )
        ..setUint32(
          LabelTextSectionExportAbi.imageLength,
          imageRef.length,
          Endian.little,
        );
    }
    _bytes.addAll(record);

    return offset;
  }

  int path(List<(double, double)> points) {
    _align(4);
    final offset = _bytes.length;
    final records = Uint8List(points.length * LabelPathPointExportAbi.size);
    final data = ByteData.sublistView(records);
    for (var index = 0; index < points.length; index++) {
      final record = index * LabelPathPointExportAbi.size;
      data
        ..setFloat32(
          record + LabelPathPointExportAbi.x,
          points[index].$1,
          Endian.little,
        )
        ..setFloat32(
          record + LabelPathPointExportAbi.y,
          points[index].$2,
          Endian.little,
        );
    }
    _bytes.addAll(records);

    return offset;
  }

  Uint8List build() => Uint8List.fromList(_bytes);

  void _align(int alignment) {
    while (_bytes.length % alignment != 0) {
      _bytes.add(0);
    }
  }
}

Uint8List _records(List<_Export> exports) {
  final bytes = Uint8List(exports.length * LabelExportAbi.size);
  for (var index = 0; index < exports.length; index++) {
    bytes.setRange(
      index * LabelExportAbi.size,
      (index + 1) * LabelExportAbi.size,
      exports[index].bytes,
    );
  }

  return bytes;
}

List<LabelData> _decode(List<_Export> exports, _Blob blob) =>
    decodeLabelExports(
      bytes: _records(exports),
      blob: blob.build(),
      count: exports.length,
      stride: LabelExportAbi.size,
    );

List<Object?> _labelSignature(LabelData data) => <Object?>[
  data.crossTileId,
  data.lat,
  data.lon,
  data.iconLat,
  data.iconLon,
  data.fontSize,
  data.textR,
  data.textG,
  data.textB,
  data.textA,
  data.haloR,
  data.haloG,
  data.haloB,
  data.haloA,
  data.haloWidth,
  data.textOpacity,
  data.haloBlur,
  data.letterSpacing,
  data.lineHeight,
  data.maxWidth,
  data.textFont,
  data.textFonts,
  for (final section in data.textSections)
    <Object?>[
      section.start,
      section.end,
      section.fontScale,
      section.fonts,
      section.color?.toARGB32(),
      section.imageId,
    ],
  for (final section in data.visualTextSections)
    <Object?>[
      section.start,
      section.end,
      section.fontScale,
      section.fonts,
      section.color?.toARGB32(),
      section.imageId,
    ],
  data.textPath.map((point) => (point.x, point.y)).toList(),
  data.iconPath.map((point) => (point.x, point.y)).toList(),
  data.textW,
  data.textH,
  data.iconW,
  data.iconH,
  data.iconScale,
  data.iconOpacity,
  data.iconR,
  data.iconG,
  data.iconB,
  data.iconA,
  data.iconHaloR,
  data.iconHaloG,
  data.iconHaloB,
  data.iconHaloA,
  data.iconHaloWidth,
  data.iconHaloBlur,
  data.iconFitWidth,
  data.iconFitHeight,
  data.textOffsetX,
  data.textOffsetY,
  data.iconOffsetX,
  data.iconOffsetY,
  data.textPlaced,
  data.iconPlaced,
  data.alongLine,
  data.iconAlongLine,
  data.angle,
  data.iconAngle,
  data.textRotation,
  data.iconRotation,
  data.textTranslateX,
  data.textTranslateY,
  data.iconTranslateX,
  data.iconTranslateY,
  data.textTransform.xx,
  data.textTransform.xy,
  data.textTransform.yx,
  data.textTransform.yy,
  data.iconTransform.xx,
  data.iconTransform.xy,
  data.iconTransform.yx,
  data.iconTransform.yy,
  data.textJustify,
  data.vertical,
  data.iconSdf,
  data.textPitchWithMap,
  data.textRotationWithMap,
  data.iconPitchWithMap,
  data.iconRotationWithMap,
  data.textKeepUpright,
  data.iconKeepUpright,
  data.text,
  data.visualText,
  data.textDirection,
  data.layer,
  data.layerIndex,
  data.renderGroup,
  data.renderOrder,
  data.icon,
];

({_SplitExport statik, _SplitExport dynamic}) _splitRecord(_Export full) {
  final statik = _SplitExport(LabelStaticExportAbi.size);
  final dynamic = _SplitExport(LabelDynamicExportAbi.size);
  const staticFields = <(int, int)>[
    (LabelExportAbi.fontSize, LabelStaticExportAbi.fontSize),
    (LabelExportAbi.textR, LabelStaticExportAbi.textR),
    (LabelExportAbi.textG, LabelStaticExportAbi.textG),
    (LabelExportAbi.textB, LabelStaticExportAbi.textB),
    (LabelExportAbi.textA, LabelStaticExportAbi.textA),
    (LabelExportAbi.haloR, LabelStaticExportAbi.haloR),
    (LabelExportAbi.haloG, LabelStaticExportAbi.haloG),
    (LabelExportAbi.haloB, LabelStaticExportAbi.haloB),
    (LabelExportAbi.haloA, LabelStaticExportAbi.haloA),
    (LabelExportAbi.haloWidth, LabelStaticExportAbi.haloWidth),
    (LabelExportAbi.iconSize, LabelStaticExportAbi.iconSize),
    (LabelExportAbi.iconOpacity, LabelStaticExportAbi.iconOpacity),
    (LabelExportAbi.iconR, LabelStaticExportAbi.iconR),
    (LabelExportAbi.iconG, LabelStaticExportAbi.iconG),
    (LabelExportAbi.iconB, LabelStaticExportAbi.iconB),
    (LabelExportAbi.iconA, LabelStaticExportAbi.iconA),
    (LabelExportAbi.crossTileID, LabelStaticExportAbi.crossTileID),
    (LabelExportAbi.textOffset, LabelStaticExportAbi.textOffset),
    (LabelExportAbi.textLength, LabelStaticExportAbi.textLength),
    (LabelExportAbi.layerOffset, LabelStaticExportAbi.layerOffset),
    (LabelExportAbi.layerLength, LabelStaticExportAbi.layerLength),
    (LabelExportAbi.iconOffset, LabelStaticExportAbi.iconOffset),
    (LabelExportAbi.iconLength, LabelStaticExportAbi.iconLength),
    (LabelExportAbi.textFontsOffset, LabelStaticExportAbi.textFontsOffset),
    (LabelExportAbi.textFontCount, LabelStaticExportAbi.textFontCount),
    (
      LabelExportAbi.textSectionsOffset,
      LabelStaticExportAbi.textSectionsOffset,
    ),
    (LabelExportAbi.textSectionCount, LabelStaticExportAbi.textSectionCount),
    (LabelExportAbi.textOpacity, LabelStaticExportAbi.textOpacity),
    (LabelExportAbi.haloBlur, LabelStaticExportAbi.haloBlur),
    (LabelExportAbi.letterSpacing, LabelStaticExportAbi.letterSpacing),
    (LabelExportAbi.lineHeight, LabelStaticExportAbi.lineHeight),
    (LabelExportAbi.maxWidth, LabelStaticExportAbi.maxWidth),
    (LabelExportAbi.textRotation, LabelStaticExportAbi.textRotation),
    (LabelExportAbi.iconRotation, LabelStaticExportAbi.iconRotation),
    (LabelExportAbi.iconHaloR, LabelStaticExportAbi.iconHaloR),
    (LabelExportAbi.iconHaloG, LabelStaticExportAbi.iconHaloG),
    (LabelExportAbi.iconHaloB, LabelStaticExportAbi.iconHaloB),
    (LabelExportAbi.iconHaloA, LabelStaticExportAbi.iconHaloA),
    (LabelExportAbi.iconHaloWidth, LabelStaticExportAbi.iconHaloWidth),
    (LabelExportAbi.iconHaloBlur, LabelStaticExportAbi.iconHaloBlur),
    (LabelExportAbi.iconFitWidth, LabelStaticExportAbi.iconFitWidth),
    (LabelExportAbi.iconFitHeight, LabelStaticExportAbi.iconFitHeight),
    (LabelExportAbi.layerIndex, LabelStaticExportAbi.layerIndex),
    (LabelExportAbi.styleFlags, LabelStaticExportAbi.styleFlags),
    (LabelExportAbi.textJustify, LabelStaticExportAbi.textJustify),
    (LabelExportAbi.renderGroup, LabelStaticExportAbi.renderGroup),
    (LabelExportAbi.logicalTextOffset, LabelStaticExportAbi.logicalTextOffset),
    (LabelExportAbi.logicalTextLength, LabelStaticExportAbi.logicalTextLength),
    (
      LabelExportAbi.visualTextSectionsOffset,
      LabelStaticExportAbi.visualTextSectionsOffset,
    ),
    (
      LabelExportAbi.visualTextSectionCount,
      LabelStaticExportAbi.visualTextSectionCount,
    ),
  ];
  const dynamicFields = <(int, int)>[
    (LabelExportAbi.textW, LabelDynamicExportAbi.textW),
    (LabelExportAbi.textH, LabelDynamicExportAbi.textH),
    (LabelExportAbi.iconW, LabelDynamicExportAbi.iconW),
    (LabelExportAbi.iconH, LabelDynamicExportAbi.iconH),
    (LabelExportAbi.flags, LabelDynamicExportAbi.flags),
    (LabelExportAbi.textAngle, LabelDynamicExportAbi.textAngle),
    (LabelExportAbi.textPathOffset, LabelDynamicExportAbi.textPathOffset),
    (LabelExportAbi.textPathCount, LabelDynamicExportAbi.textPathCount),
    (LabelExportAbi.iconPathOffset, LabelDynamicExportAbi.iconPathOffset),
    (LabelExportAbi.iconPathCount, LabelDynamicExportAbi.iconPathCount),
    (LabelExportAbi.textOffsetX, LabelDynamicExportAbi.textOffsetX),
    (LabelExportAbi.textOffsetY, LabelDynamicExportAbi.textOffsetY),
    (LabelExportAbi.iconOffsetX, LabelDynamicExportAbi.iconOffsetX),
    (LabelExportAbi.iconOffsetY, LabelDynamicExportAbi.iconOffsetY),
    (LabelExportAbi.iconAngle, LabelDynamicExportAbi.iconAngle),
    (LabelExportAbi.textTranslateX, LabelDynamicExportAbi.textTranslateX),
    (LabelExportAbi.textTranslateY, LabelDynamicExportAbi.textTranslateY),
    (LabelExportAbi.iconTranslateX, LabelDynamicExportAbi.iconTranslateX),
    (LabelExportAbi.iconTranslateY, LabelDynamicExportAbi.iconTranslateY),
    (LabelExportAbi.textTransformXX, LabelDynamicExportAbi.textTransformXX),
    (LabelExportAbi.textTransformXY, LabelDynamicExportAbi.textTransformXY),
    (LabelExportAbi.textTransformYX, LabelDynamicExportAbi.textTransformYX),
    (LabelExportAbi.textTransformYY, LabelDynamicExportAbi.textTransformYY),
    (LabelExportAbi.iconTransformXX, LabelDynamicExportAbi.iconTransformXX),
    (LabelExportAbi.iconTransformXY, LabelDynamicExportAbi.iconTransformXY),
    (LabelExportAbi.iconTransformYX, LabelDynamicExportAbi.iconTransformYX),
    (LabelExportAbi.iconTransformYY, LabelDynamicExportAbi.iconTransformYY),
    (LabelExportAbi.renderOrder, LabelDynamicExportAbi.renderOrder),
  ];
  for (final (source, target) in staticFields) {
    statik.bytes.setRange(target, target + 4, full.bytes, source);
  }
  for (final (source, target) in dynamicFields) {
    dynamic.bytes.setRange(target, target + 4, full.bytes, source);
  }
  for (final (source, target) in <(int, int)>[
    (LabelExportAbi.lat, LabelDynamicExportAbi.lat),
    (LabelExportAbi.lon, LabelDynamicExportAbi.lon),
    (LabelExportAbi.iconLat, LabelDynamicExportAbi.iconLat),
    (LabelExportAbi.iconLon, LabelDynamicExportAbi.iconLon),
  ]) {
    dynamic.bytes.setRange(target, target + 8, full.bytes, source);
  }

  return (statik: statik, dynamic: dynamic);
}

void main() {
  test('decodes each record at its own stride', () {
    final first = _Export()..f64(LabelExportAbi.lat, 35.5);
    final second = _Export()..f64(LabelExportAbi.lat, 12.25);

    final labels = _decode(<_Export>[first, second], _Blob());

    expect(labels, hasLength(2));
    expect(labels[0].lat, 35.5);
    expect(labels[1].lat, 12.25);
  });

  test('rejects invalid framing', () {
    expect(
      decodeLabelExports(
        bytes: _Export().bytes,
        blob: Uint8List(0),
        count: 1,
        stride: LabelExportAbi.size - 4,
      ),
      isEmpty,
    );
    expect(
      decodeLabelExports(
        bytes: _Export().bytes,
        blob: Uint8List(0),
        count: 2,
        stride: LabelExportAbi.size,
      ),
      isEmpty,
    );
  });

  test('keeps text and icon anchors and offsets separate', () {
    final export = _Export()
      ..f64(LabelExportAbi.lat, 35.68)
      ..f64(LabelExportAbi.lon, 139.76)
      ..f64(LabelExportAbi.iconLat, 35.10)
      ..f64(LabelExportAbi.iconLon, 139.10)
      ..f32(LabelExportAbi.textOffsetX, 1)
      ..f32(LabelExportAbi.textOffsetY, 2)
      ..f32(LabelExportAbi.iconOffsetX, 3)
      ..f32(LabelExportAbi.iconOffsetY, 4);

    final label = _decode(<_Export>[export], _Blob()).single;

    expect((label.lat, label.lon), (35.68, 139.76));
    expect((label.iconLat, label.iconLon), (35.10, 139.10));
    expect((label.textOffsetX, label.textOffsetY), (1, 2));
    expect((label.iconOffsetX, label.iconOffsetY), (3, 4));
  });

  test('decodes every scalar paint, layout, and transform field', () {
    final export = _Export()
      ..f64(LabelExportAbi.lat, 1.25)
      ..f64(LabelExportAbi.lon, 2.5)
      ..f64(LabelExportAbi.iconLat, 3.75)
      ..f64(LabelExportAbi.iconLon, 4.5)
      ..f32(LabelExportAbi.fontSize, 12)
      ..f32(LabelExportAbi.textR, 0.125)
      ..f32(LabelExportAbi.textG, 0.25)
      ..f32(LabelExportAbi.textB, 0.5)
      ..f32(LabelExportAbi.textA, 0.75)
      ..f32(LabelExportAbi.haloR, 0.25)
      ..f32(LabelExportAbi.haloG, 0.5)
      ..f32(LabelExportAbi.haloB, 0.75)
      ..f32(LabelExportAbi.haloA, 1)
      ..f32(LabelExportAbi.haloWidth, 2)
      ..f32(LabelExportAbi.textW, 30)
      ..f32(LabelExportAbi.textH, 14)
      ..f32(LabelExportAbi.iconW, 20)
      ..f32(LabelExportAbi.iconH, 18)
      ..f32(LabelExportAbi.iconSize, 1.5)
      ..f32(LabelExportAbi.iconOpacity, 0.5)
      ..f32(LabelExportAbi.iconR, 0.125)
      ..f32(LabelExportAbi.iconG, 0.25)
      ..f32(LabelExportAbi.iconB, 0.375)
      ..f32(LabelExportAbi.iconA, 0.5)
      ..f32(LabelExportAbi.textAngle, -0.5)
      ..f32(LabelExportAbi.textOffsetX, 5)
      ..f32(LabelExportAbi.textOffsetY, -6)
      ..f32(LabelExportAbi.iconOffsetX, 7)
      ..f32(LabelExportAbi.iconOffsetY, -8)
      ..f32(LabelExportAbi.textOpacity, 0.75)
      ..f32(LabelExportAbi.haloBlur, 1.25)
      ..f32(LabelExportAbi.letterSpacing, 0.125)
      ..f32(LabelExportAbi.lineHeight, 1.5)
      ..f32(LabelExportAbi.maxWidth, 9)
      ..f32(LabelExportAbi.iconAngle, 0.75)
      ..f32(LabelExportAbi.textRotation, 0.25)
      ..f32(LabelExportAbi.iconRotation, -0.25)
      ..f32(LabelExportAbi.textTranslateX, 10)
      ..f32(LabelExportAbi.textTranslateY, -11)
      ..f32(LabelExportAbi.iconTranslateX, 12)
      ..f32(LabelExportAbi.iconTranslateY, -13)
      ..f32(LabelExportAbi.iconHaloR, 0.125)
      ..f32(LabelExportAbi.iconHaloG, 0.25)
      ..f32(LabelExportAbi.iconHaloB, 0.375)
      ..f32(LabelExportAbi.iconHaloA, 0.5)
      ..f32(LabelExportAbi.iconHaloWidth, 3)
      ..f32(LabelExportAbi.iconHaloBlur, 4)
      ..f32(LabelExportAbi.iconFitWidth, 40)
      ..f32(LabelExportAbi.iconFitHeight, 24)
      ..f32(LabelExportAbi.textTransformXX, 1)
      ..f32(LabelExportAbi.textTransformXY, 2)
      ..f32(LabelExportAbi.textTransformYX, 3)
      ..f32(LabelExportAbi.textTransformYY, 4)
      ..f32(LabelExportAbi.iconTransformXX, 5)
      ..f32(LabelExportAbi.iconTransformXY, 6)
      ..f32(LabelExportAbi.iconTransformYX, 7)
      ..f32(LabelExportAbi.iconTransformYY, 8)
      ..i32(LabelExportAbi.layerIndex, 19)
      ..u32(LabelExportAbi.renderGroup, 23)
      ..u32(LabelExportAbi.renderOrder, 29);

    final label = _decode(<_Export>[export], _Blob()).single;

    expect(
      (label.lat, label.lon, label.iconLat, label.iconLon),
      (1.25, 2.5, 3.75, 4.5),
    );
    expect(label.fontSize, 12);
    expect(
      (label.textR, label.textG, label.textB, label.textA),
      (0.125, 0.25, 0.5, 0.75),
    );
    expect(
      (label.haloR, label.haloG, label.haloB, label.haloA),
      (0.25, 0.5, 0.75, 1),
    );
    expect((label.haloWidth, label.textW, label.textH), (2, 30, 14));
    expect((label.iconW, label.iconH, label.iconScale), (20, 18, 1.5));
    expect(label.iconOpacity, 0.5);
    expect(
      (label.iconR, label.iconG, label.iconB, label.iconA),
      (0.125, 0.25, 0.375, 0.5),
    );
    expect((label.angle, label.iconAngle), (-0.5, 0.75));
    expect(
      (
        label.textOffsetX,
        label.textOffsetY,
        label.iconOffsetX,
        label.iconOffsetY,
      ),
      (5, -6, 7, -8),
    );
    expect(
      (
        label.textOpacity,
        label.haloBlur,
        label.letterSpacing,
        label.lineHeight,
        label.maxWidth,
      ),
      (0.75, 1.25, 0.125, 1.5, 9),
    );
    expect((label.textRotation, label.iconRotation), (0.25, -0.25));
    expect(
      (
        label.textTranslateX,
        label.textTranslateY,
        label.iconTranslateX,
        label.iconTranslateY,
      ),
      (10, -11, 12, -13),
    );
    expect(
      (label.iconHaloR, label.iconHaloG, label.iconHaloB, label.iconHaloA),
      (0.125, 0.25, 0.375, 0.5),
    );
    expect(
      (
        label.iconHaloWidth,
        label.iconHaloBlur,
        label.iconFitWidth,
        label.iconFitHeight,
      ),
      (3, 4, 40, 24),
    );
    expect(
      (
        label.textTransform.xx,
        label.textTransform.xy,
        label.textTransform.yx,
        label.textTransform.yy,
      ),
      (1, 2, 3, 4),
    );
    expect(
      (
        label.iconTransform.xx,
        label.iconTransform.xy,
        label.iconTransform.yx,
        label.iconTransform.yy,
      ),
      (5, 6, 7, 8),
    );
    expect(label.layerIndex, 19);
    expect(label.renderGroup, 23);
    expect(label.renderOrder, 29);
  });

  test('decodes placement, line, and style flags independently', () {
    final export = _Export()
      ..u32(LabelExportAbi.flags, 15)
      ..u32(LabelExportAbi.styleFlags, 511)
      ..u32(LabelExportAbi.textJustify, 3);

    final label = _decode(<_Export>[export], _Blob()).single;

    expect(label.textPlaced, isTrue);
    expect(label.iconPlaced, isTrue);
    expect(label.alongLine, isTrue);
    expect(label.iconAlongLine, isTrue);
    expect(label.vertical, isTrue);
    expect(label.iconSdf, isTrue);
    expect(label.textPitchWithMap, isTrue);
    expect(label.textRotationWithMap, isTrue);
    expect(label.iconPitchWithMap, isTrue);
    expect(label.iconRotationWithMap, isTrue);
    expect(label.textKeepUpright, isTrue);
    expect(label.iconKeepUpright, isTrue);
    expect(label.textDirection, TextDirection.rtl);
    expect(label.textJustify, LabelTextJustify.right);
  });

  test('keeps logical BiDi text separate from visual path text', () {
    final blob = _Blob();
    final export = _Export()
      ..string(
        blob,
        LabelExportAbi.textOffset,
        LabelExportAbi.textLength,
        'םולש',
      )
      ..string(
        blob,
        LabelExportAbi.logicalTextOffset,
        LabelExportAbi.logicalTextLength,
        'שלום',
      )
      ..u32(LabelExportAbi.styleFlags, 1 << 8);

    final label = _decode(<_Export>[export], blob).single;

    expect(label.text, 'שלום');
    expect(label.visualText, 'םולש');
    expect(label.textDirection, TextDirection.rtl);
  });

  test('variable strings are not truncated', () {
    final blob = _Blob();
    final visualText = List<String>.filled(200, '駅').join();
    final logicalText = List<String>.filled(200, '町').join();
    final layer = List<String>.filled(90, 'layer').join();
    final icon = List<String>.filled(90, 'icon').join();
    final export = _Export()
      ..string(
        blob,
        LabelExportAbi.textOffset,
        LabelExportAbi.textLength,
        visualText,
      )
      ..string(
        blob,
        LabelExportAbi.logicalTextOffset,
        LabelExportAbi.logicalTextLength,
        logicalText,
      )
      ..string(
        blob,
        LabelExportAbi.layerOffset,
        LabelExportAbi.layerLength,
        layer,
      )
      ..string(
        blob,
        LabelExportAbi.iconOffset,
        LabelExportAbi.iconLength,
        icon,
      );

    final label = _decode(<_Export>[export], blob).single;

    expect(label.text, logicalText);
    expect(label.visualText, visualText);
    expect(label.layer, layer);
    expect(label.icon, icon);
  });

  test('decodes full font stack and formatted section', () {
    final blob = _Blob();
    final fonts = <String>['Noto Sans', 'Arial Unicode MS'];
    final fontsOffset = blob.fonts(fonts);
    final sectionOffset = blob.section(
      start: 1,
      end: 4,
      fonts: <String>['Noto Serif'],
      image: 'inline-shield',
    );
    final visualSectionOffset = blob.section(
      start: 0,
      end: 2,
      fonts: <String>['Visual Face'],
    );
    final export = _Export()
      ..string(
        blob,
        LabelExportAbi.textOffset,
        LabelExportAbi.textLength,
        'aגבאz',
      )
      ..string(
        blob,
        LabelExportAbi.logicalTextOffset,
        LabelExportAbi.logicalTextLength,
        'aאבגz',
      )
      ..u32(LabelExportAbi.textFontsOffset, fontsOffset)
      ..u32(LabelExportAbi.textFontCount, fonts.length)
      ..u32(LabelExportAbi.textSectionsOffset, sectionOffset)
      ..u32(LabelExportAbi.textSectionCount, 1)
      ..u32(LabelExportAbi.visualTextSectionsOffset, visualSectionOffset)
      ..u32(LabelExportAbi.visualTextSectionCount, 1);

    final label = _decode(<_Export>[export], blob).single;

    expect(label.textFont, 'Noto Sans');
    expect(label.textFonts, fonts);
    expect(label.textSections, hasLength(1));
    expect(label.textSections.single.start, 1);
    expect(label.textSections.single.end, 4);
    expect(
      label.text.substring(
        label.textSections.single.start,
        label.textSections.single.end,
      ),
      'אבג',
    );
    expect(label.textSections.single.fontScale, 1.5);
    expect(label.textSections.single.fonts, <String>['Noto Serif']);
    expect(label.textSections.single.imageId, 'inline-shield');
    expect(label.textSections.single.color, const Color(0x80804000));
    expect(label.visualTextSections, hasLength(1));
    expect(label.visualTextSections.single.start, 0);
    expect(label.visualTextSections.single.end, 2);
    expect(label.visualTextSections.single.fonts, <String>['Visual Face']);
  });

  test('decodes center-relative paths and affine transforms', () {
    final blob = _Blob();
    final textPath = blob.path(<(double, double)>[(1, 2), (3, 4)]);
    final iconPath = blob.path(<(double, double)>[(-1, -2)]);
    final export = _Export()
      ..u32(LabelExportAbi.textPathOffset, textPath)
      ..u32(LabelExportAbi.textPathCount, 2)
      ..u32(LabelExportAbi.iconPathOffset, iconPath)
      ..u32(LabelExportAbi.iconPathCount, 1)
      ..f32(LabelExportAbi.textTransformXX, 0.5)
      ..f32(LabelExportAbi.textTransformXY, 0.25)
      ..f32(LabelExportAbi.textTransformYX, -0.25)
      ..f32(LabelExportAbi.textTransformYY, 0.5)
      ..i32(LabelExportAbi.layerIndex, 17);

    final label = _decode(<_Export>[export], blob).single;

    expect(label.textPath.map((point) => (point.x, point.y)), <Object>[
      (1, 2),
      (3, 4),
    ]);
    expect(label.iconPath.single.x, -1);
    expect(label.iconPath.single.y, -2);
    expect(label.textTransform.xx, 0.5);
    expect(label.textTransform.xy, 0.25);
    expect(label.textTransform.yx, -0.25);
    expect(label.textTransform.yy, 0.5);
    expect(label.layerIndex, 17);
  });

  test('rejects a blob reference outside the published snapshot', () {
    final export = _Export()
      ..u32(LabelExportAbi.textOffset, 100)
      ..u32(LabelExportAbi.textLength, 5);

    expect(_decode(<_Export>[export], _Blob()), isEmpty);
  });

  test('rejects malformed variable record offsets', () {
    final badFonts = _Export()
      ..u32(LabelExportAbi.textFontsOffset, 4)
      ..u32(LabelExportAbi.textFontCount, 1);
    final badSections = _Export()
      ..u32(LabelExportAbi.textSectionsOffset, 4)
      ..u32(LabelExportAbi.textSectionCount, 1);
    final badPath = _Export()
      ..u32(LabelExportAbi.textPathOffset, 4)
      ..u32(LabelExportAbi.textPathCount, 1);
    final badLogicalText = _Export()
      ..u32(LabelExportAbi.logicalTextOffset, 4)
      ..u32(LabelExportAbi.logicalTextLength, 1);
    final badVisualSections = _Export()
      ..u32(LabelExportAbi.visualTextSectionsOffset, 4)
      ..u32(LabelExportAbi.visualTextSectionCount, 1);

    expect(_decode(<_Export>[badFonts], _Blob()), isEmpty);
    expect(_decode(<_Export>[badSections], _Blob()), isEmpty);
    expect(_decode(<_Export>[badPath], _Blob()), isEmpty);
    expect(_decode(<_Export>[badLogicalText], _Blob()), isEmpty);
    expect(_decode(<_Export>[badVisualSections], _Blob()), isEmpty);
  });

  test('carries paint effects and stable identity', () {
    final export = _Export()
      ..u32(LabelExportAbi.crossTileID, 4294967295)
      ..f32(LabelExportAbi.iconHaloR, 0.25)
      ..f32(LabelExportAbi.iconHaloA, 0.5)
      ..f32(LabelExportAbi.iconHaloWidth, 3)
      ..f32(LabelExportAbi.iconHaloBlur, 2)
      ..f32(LabelExportAbi.iconFitWidth, 48)
      ..f32(LabelExportAbi.iconFitHeight, 24)
      ..f32(LabelExportAbi.textTranslateX, 5)
      ..f32(LabelExportAbi.iconTranslateY, -4);

    final label = _decode(<_Export>[export], _Blob()).single;

    expect(label.crossTileId, 4294967295);
    expect(label.iconHaloWidth, 3);
    expect(label.iconHaloBlur, 2);
    expect(label.iconFitWidth, 48);
    expect(label.iconFitHeight, 24);
    expect(label.textTranslateX, 5);
    expect(label.iconTranslateY, -4);
  });

  test('split export preserves every legacy LabelData field', () {
    final blob = _Blob();
    final fontsOffset = blob.fonts(<String>['Noto Sans', 'sans-serif']);
    final sectionOffset = blob.section(
      start: 0,
      end: 7,
      fonts: <String>['Noto Sans'],
      image: 'inline-image',
    );
    final visualSectionOffset = blob.section(
      start: 1,
      end: 6,
      fonts: <String>['sans-serif'],
    );
    final textPath = blob.path(<(double, double)>[(1, 2), (3, 4)]);
    final iconPath = blob.path(<(double, double)>[(-1, -2), (-3, -4)]);
    final full = _Export()
      ..f64(LabelExportAbi.lat, 1.25)
      ..f64(LabelExportAbi.lon, 2.5)
      ..f64(LabelExportAbi.iconLat, 3.75)
      ..f64(LabelExportAbi.iconLon, 4.5)
      ..f32(LabelExportAbi.fontSize, 12)
      ..f32(LabelExportAbi.textR, 0.125)
      ..f32(LabelExportAbi.textG, 0.25)
      ..f32(LabelExportAbi.textB, 0.5)
      ..f32(LabelExportAbi.textA, 0.75)
      ..f32(LabelExportAbi.haloR, 0.25)
      ..f32(LabelExportAbi.haloG, 0.5)
      ..f32(LabelExportAbi.haloB, 0.75)
      ..f32(LabelExportAbi.haloA, 1)
      ..f32(LabelExportAbi.haloWidth, 2)
      ..f32(LabelExportAbi.textW, 30)
      ..f32(LabelExportAbi.textH, 14)
      ..f32(LabelExportAbi.iconW, 20)
      ..f32(LabelExportAbi.iconH, 18)
      ..f32(LabelExportAbi.iconSize, 1.5)
      ..f32(LabelExportAbi.iconOpacity, 0.5)
      ..f32(LabelExportAbi.iconR, 0.125)
      ..f32(LabelExportAbi.iconG, 0.25)
      ..f32(LabelExportAbi.iconB, 0.375)
      ..f32(LabelExportAbi.iconA, 0.5)
      ..u32(LabelExportAbi.flags, 15)
      ..f32(LabelExportAbi.textAngle, -0.5)
      ..u32(LabelExportAbi.crossTileID, 42)
      ..string(
        blob,
        LabelExportAbi.textOffset,
        LabelExportAbi.textLength,
        'Visual',
      )
      ..string(
        blob,
        LabelExportAbi.layerOffset,
        LabelExportAbi.layerLength,
        'labels',
      )
      ..string(
        blob,
        LabelExportAbi.iconOffset,
        LabelExportAbi.iconLength,
        'marker',
      )
      ..u32(LabelExportAbi.textFontsOffset, fontsOffset)
      ..u32(LabelExportAbi.textFontCount, 2)
      ..u32(LabelExportAbi.textSectionsOffset, sectionOffset)
      ..u32(LabelExportAbi.textSectionCount, 1)
      ..u32(LabelExportAbi.textPathOffset, textPath)
      ..u32(LabelExportAbi.textPathCount, 2)
      ..u32(LabelExportAbi.iconPathOffset, iconPath)
      ..u32(LabelExportAbi.iconPathCount, 2)
      ..f32(LabelExportAbi.textOffsetX, 5)
      ..f32(LabelExportAbi.textOffsetY, -6)
      ..f32(LabelExportAbi.iconOffsetX, 7)
      ..f32(LabelExportAbi.iconOffsetY, -8)
      ..f32(LabelExportAbi.textOpacity, 0.75)
      ..f32(LabelExportAbi.haloBlur, 1.25)
      ..f32(LabelExportAbi.letterSpacing, 0.125)
      ..f32(LabelExportAbi.lineHeight, 1.5)
      ..f32(LabelExportAbi.maxWidth, 9)
      ..f32(LabelExportAbi.iconAngle, 0.75)
      ..f32(LabelExportAbi.textRotation, 0.25)
      ..f32(LabelExportAbi.iconRotation, -0.25)
      ..f32(LabelExportAbi.textTranslateX, 10)
      ..f32(LabelExportAbi.textTranslateY, -11)
      ..f32(LabelExportAbi.iconTranslateX, 12)
      ..f32(LabelExportAbi.iconTranslateY, -13)
      ..f32(LabelExportAbi.iconHaloR, 0.125)
      ..f32(LabelExportAbi.iconHaloG, 0.25)
      ..f32(LabelExportAbi.iconHaloB, 0.375)
      ..f32(LabelExportAbi.iconHaloA, 0.5)
      ..f32(LabelExportAbi.iconHaloWidth, 3)
      ..f32(LabelExportAbi.iconHaloBlur, 4)
      ..f32(LabelExportAbi.iconFitWidth, 40)
      ..f32(LabelExportAbi.iconFitHeight, 24)
      ..f32(LabelExportAbi.textTransformXX, 1)
      ..f32(LabelExportAbi.textTransformXY, 2)
      ..f32(LabelExportAbi.textTransformYX, 3)
      ..f32(LabelExportAbi.textTransformYY, 4)
      ..f32(LabelExportAbi.iconTransformXX, 5)
      ..f32(LabelExportAbi.iconTransformXY, 6)
      ..f32(LabelExportAbi.iconTransformYX, 7)
      ..f32(LabelExportAbi.iconTransformYY, 8)
      ..i32(LabelExportAbi.layerIndex, 19)
      ..u32(LabelExportAbi.styleFlags, 511)
      ..u32(LabelExportAbi.textJustify, 3)
      ..u32(LabelExportAbi.renderGroup, 23)
      ..u32(LabelExportAbi.renderOrder, 29)
      ..string(
        blob,
        LabelExportAbi.logicalTextOffset,
        LabelExportAbi.logicalTextLength,
        'Logical',
      )
      ..u32(LabelExportAbi.visualTextSectionsOffset, visualSectionOffset)
      ..u32(LabelExportAbi.visualTextSectionCount, 1);
    final legacy = _decode(<_Export>[full], blob).single;
    final splitRecord = _splitRecord(full);
    final statics = decodeLabelStaticExports(
      bytes: splitRecord.statik.bytes,
      blob: blob.build(),
      count: 1,
      stride: LabelStaticExportAbi.size,
    );
    final split = decodeLabelDynamicExports(
      bytes: splitRecord.dynamic.bytes,
      blob: blob.build(),
      count: 1,
      stride: LabelDynamicExportAbi.size,
      staticLabels: statics,
    ).single;

    expect(_labelSignature(split), _labelSignature(legacy));
  });

  test('split scalar refresh reuses decoded content identity', () {
    final blob = _Blob();
    final fontsOffset = blob.fonts(<String>['Noto Sans']);
    final sectionOffset = blob.section(
      start: 0,
      end: 5,
      fonts: <String>['Noto Sans'],
    );
    final statik = _SplitExport(LabelStaticExportAbi.size)
      ..f32(LabelStaticExportAbi.fontSize, 16)
      ..u32(LabelStaticExportAbi.textFontsOffset, fontsOffset)
      ..u32(LabelStaticExportAbi.textFontCount, 1)
      ..u32(LabelStaticExportAbi.textSectionsOffset, sectionOffset)
      ..u32(LabelStaticExportAbi.textSectionCount, 1)
      ..string(
        blob,
        LabelStaticExportAbi.textOffset,
        LabelStaticExportAbi.textLength,
        'Tokyo',
      )
      ..string(
        blob,
        LabelStaticExportAbi.logicalTextOffset,
        LabelStaticExportAbi.logicalTextLength,
        'Tokyo',
      )
      ..string(
        blob,
        LabelStaticExportAbi.layerOffset,
        LabelStaticExportAbi.layerLength,
        'places',
      );
    final first = decodeLabelStaticExports(
      bytes: statik.bytes,
      blob: blob.build(),
      count: 1,
      stride: LabelStaticExportAbi.size,
    );
    statik.f32(LabelStaticExportAbi.fontSize, 20);
    final second = decodeLabelStaticScalarExports(
      bytes: statik.bytes,
      count: 1,
      stride: LabelStaticExportAbi.size,
      previous: first,
    );

    expect(second.single.label.fontSize, 20);
    expect(
      identical(second.single.label.text, first.single.label.text),
      isTrue,
    );
    expect(
      identical(second.single.label.textFonts, first.single.label.textFonts),
      isTrue,
    );
    expect(
      identical(
        second.single.label.textSections,
        first.single.label.textSections,
      ),
      isTrue,
    );
  });

  test('split dynamic records join static content by index', () {
    final staticBlob = _Blob();
    final statik = _SplitExport(LabelStaticExportAbi.size)
      ..string(
        staticBlob,
        LabelStaticExportAbi.textOffset,
        LabelStaticExportAbi.textLength,
        'Road',
      )
      ..string(
        staticBlob,
        LabelStaticExportAbi.logicalTextOffset,
        LabelStaticExportAbi.logicalTextLength,
        'Road',
      );
    final staticLabels = decodeLabelStaticExports(
      bytes: statik.bytes,
      blob: staticBlob.build(),
      count: 1,
      stride: LabelStaticExportAbi.size,
    );
    final dynamicBlob = _Blob();
    final textPath = dynamicBlob.path(<(double, double)>[(1, 2), (3, 4)]);
    final dynamic = _SplitExport(LabelDynamicExportAbi.size)
      ..f64(LabelDynamicExportAbi.lat, 35.5)
      ..f64(LabelDynamicExportAbi.lon, 139.75)
      ..u32(LabelDynamicExportAbi.flags, 1 | 4)
      ..u32(LabelDynamicExportAbi.textPathOffset, textPath)
      ..u32(LabelDynamicExportAbi.textPathCount, 2)
      ..u32(LabelDynamicExportAbi.renderOrder, 19)
      ..u32(LabelDynamicExportAbi.staticIndex, 0);
    final labels = decodeLabelDynamicExports(
      bytes: dynamic.bytes,
      blob: dynamicBlob.build(),
      count: 1,
      stride: LabelDynamicExportAbi.size,
      staticLabels: staticLabels,
    );

    expect(labels.single.lat, 35.5);
    expect(labels.single.lon, 139.75);
    expect(labels.single.alongLine, isTrue);
    expect(labels.single.renderOrder, 19);
    expect(labels.single.textPath, hasLength(2));
    expect(
      identical(labels.single.text, staticLabels.single.label.text),
      isTrue,
    );
  });

  test('split decoders reject malformed content and geometry references', () {
    final badStatic = _SplitExport(LabelStaticExportAbi.size)
      ..u32(LabelStaticExportAbi.textOffset, 8)
      ..u32(LabelStaticExportAbi.textLength, 1);
    expect(
      decodeLabelStaticExports(
        bytes: badStatic.bytes,
        blob: Uint8List(0),
        count: 1,
        stride: LabelStaticExportAbi.size,
      ),
      isEmpty,
    );

    final validStatic = decodeLabelStaticExports(
      bytes: _SplitExport(LabelStaticExportAbi.size).bytes,
      blob: Uint8List(0),
      count: 1,
      stride: LabelStaticExportAbi.size,
    );
    final badIndex = _SplitExport(LabelDynamicExportAbi.size)
      ..u32(LabelDynamicExportAbi.staticIndex, 1);
    expect(
      decodeLabelDynamicExports(
        bytes: badIndex.bytes,
        blob: Uint8List(0),
        count: 1,
        stride: LabelDynamicExportAbi.size,
        staticLabels: validStatic,
      ),
      isEmpty,
    );

    final badPath = _SplitExport(LabelDynamicExportAbi.size)
      ..u32(LabelDynamicExportAbi.textPathOffset, 8)
      ..u32(LabelDynamicExportAbi.textPathCount, 1);
    expect(
      decodeLabelDynamicExports(
        bytes: badPath.bytes,
        blob: Uint8List(0),
        count: 1,
        stride: LabelDynamicExportAbi.size,
        staticLabels: validStatic,
      ),
      isEmpty,
    );
  });

  test('split dynamic ordering follows staticIndex indirection', () {
    final staticBytes = Uint8List(LabelStaticExportAbi.size * 2);
    ByteData.sublistView(staticBytes)
      ..setUint32(LabelStaticExportAbi.crossTileID, 10, Endian.little)
      ..setUint32(
        LabelStaticExportAbi.size + LabelStaticExportAbi.crossTileID,
        20,
        Endian.little,
      );
    final statics = decodeLabelStaticExports(
      bytes: staticBytes,
      blob: Uint8List(0),
      count: 2,
      stride: LabelStaticExportAbi.size,
    );
    final dynamicBytes = Uint8List(LabelDynamicExportAbi.size * 2);
    final dynamicBlob = _Blob();
    final sharedPath = dynamicBlob.path(<(double, double)>[(1, 2), (3, 4)]);
    ByteData.sublistView(dynamicBytes)
      ..setUint32(LabelDynamicExportAbi.staticIndex, 1, Endian.little)
      ..setUint32(LabelDynamicExportAbi.renderOrder, 3, Endian.little)
      ..setUint32(
        LabelDynamicExportAbi.textPathOffset,
        sharedPath,
        Endian.little,
      )
      ..setUint32(LabelDynamicExportAbi.textPathCount, 2, Endian.little)
      ..setUint32(
        LabelDynamicExportAbi.size + LabelDynamicExportAbi.staticIndex,
        0,
        Endian.little,
      )
      ..setUint32(
        LabelDynamicExportAbi.size + LabelDynamicExportAbi.renderOrder,
        7,
        Endian.little,
      )
      ..setUint32(
        LabelDynamicExportAbi.size + LabelDynamicExportAbi.textPathOffset,
        sharedPath,
        Endian.little,
      )
      ..setUint32(
        LabelDynamicExportAbi.size + LabelDynamicExportAbi.textPathCount,
        2,
        Endian.little,
      );
    final labels = decodeLabelDynamicExports(
      bytes: dynamicBytes,
      blob: dynamicBlob.build(),
      count: 2,
      stride: LabelDynamicExportAbi.size,
      staticLabels: statics,
    );

    expect(labels.map((label) => label.crossTileId), <int>[20, 10]);
    expect(labels.map((label) => label.renderOrder), <int>[3, 7]);
    expect(identical(labels[0].textPath, labels[1].textPath), isTrue);
  });
}
