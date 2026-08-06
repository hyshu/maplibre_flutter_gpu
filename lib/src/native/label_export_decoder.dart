import 'dart:convert';
import 'dart:typed_data';

import '../labels/label_data.dart';
import 'abi_generated.dart';

const _textPlacedFlag = 1 << 0;
const _iconPlacedFlag = 1 << 1;
const _alongLineFlag = 1 << 2;

const _textBytes = 128;
const _layerBytes = 64;
const _iconBytes = 64;
const _textFontBytes = 68;

/// Decodes [count] records of [stride] bytes from [bytes].
///
/// Returns an empty list when the input does not contain a complete
/// ABI-compatible record sequence. Returned objects do not retain [bytes].
List<LabelData> decodeLabelExports({
  required Uint8List bytes,
  required int count,
  required int stride,
}) {
  if (count <= 0) return const [];
  if (stride != LabelExportAbi.size) return const [];
  if (bytes.lengthInBytes < count * stride) return const [];
  final data = ByteData.sublistView(bytes);
  final labels = <LabelData>[];
  for (var index = 0; index < count; index++) {
    final offset = index * stride;
    final flags = data.getUint32(offset + LabelExportAbi.flags, Endian.little);
    labels.add(
      LabelData(
        lat: data.getFloat64(offset + LabelExportAbi.lat, Endian.little),
        lon: data.getFloat64(offset + LabelExportAbi.lon, Endian.little),
        iconLat: data.getFloat64(
          offset + LabelExportAbi.iconLat,
          Endian.little,
        ),
        iconLon: data.getFloat64(
          offset + LabelExportAbi.iconLon,
          Endian.little,
        ),
        fontSize: data.getFloat32(
          offset + LabelExportAbi.fontSize,
          Endian.little,
        ),
        textR: data.getFloat32(offset + LabelExportAbi.textR, Endian.little),
        textG: data.getFloat32(offset + LabelExportAbi.textG, Endian.little),
        textB: data.getFloat32(offset + LabelExportAbi.textB, Endian.little),
        textA: data.getFloat32(offset + LabelExportAbi.textA, Endian.little),
        haloR: data.getFloat32(offset + LabelExportAbi.haloR, Endian.little),
        haloG: data.getFloat32(offset + LabelExportAbi.haloG, Endian.little),
        haloB: data.getFloat32(offset + LabelExportAbi.haloB, Endian.little),
        haloA: data.getFloat32(offset + LabelExportAbi.haloA, Endian.little),
        haloWidth: data.getFloat32(
          offset + LabelExportAbi.haloWidth,
          Endian.little,
        ),
        textOpacity: data.getFloat32(
          offset + LabelExportAbi.textOpacity,
          Endian.little,
        ),
        haloBlur: data.getFloat32(
          offset + LabelExportAbi.haloBlur,
          Endian.little,
        ),
        letterSpacing: data.getFloat32(
          offset + LabelExportAbi.letterSpacing,
          Endian.little,
        ),
        lineHeight: data.getFloat32(
          offset + LabelExportAbi.lineHeight,
          Endian.little,
        ),
        maxWidth: data.getFloat32(
          offset + LabelExportAbi.maxWidth,
          Endian.little,
        ),
        textFont: _cstr(
          bytes,
          offset + LabelExportAbi.textFont,
          _textFontBytes,
        ),
        textW: data.getFloat32(offset + LabelExportAbi.textW, Endian.little),
        textH: data.getFloat32(offset + LabelExportAbi.textH, Endian.little),
        iconW: data.getFloat32(offset + LabelExportAbi.iconW, Endian.little),
        iconH: data.getFloat32(offset + LabelExportAbi.iconH, Endian.little),
        iconScale: data.getFloat32(
          offset + LabelExportAbi.iconSize,
          Endian.little,
        ),
        iconOpacity: data.getFloat32(
          offset + LabelExportAbi.iconOpacity,
          Endian.little,
        ),
        iconR: data.getFloat32(offset + LabelExportAbi.iconR, Endian.little),
        iconG: data.getFloat32(offset + LabelExportAbi.iconG, Endian.little),
        iconB: data.getFloat32(offset + LabelExportAbi.iconB, Endian.little),
        iconA: data.getFloat32(offset + LabelExportAbi.iconA, Endian.little),
        textOffsetX: data.getFloat32(
          offset + LabelExportAbi.textOffsetX,
          Endian.little,
        ),
        textOffsetY: data.getFloat32(
          offset + LabelExportAbi.textOffsetY,
          Endian.little,
        ),
        iconOffsetX: data.getFloat32(
          offset + LabelExportAbi.iconOffsetX,
          Endian.little,
        ),
        iconOffsetY: data.getFloat32(
          offset + LabelExportAbi.iconOffsetY,
          Endian.little,
        ),
        textPlaced: (flags & _textPlacedFlag) != 0,
        iconPlaced: (flags & _iconPlacedFlag) != 0,
        alongLine: (flags & _alongLineFlag) != 0,
        angle: data.getFloat32(
          offset + LabelExportAbi.textAngle,
          Endian.little,
        ),
        crossTileId: data.getUint32(
          offset + LabelExportAbi.crossTileID,
          Endian.little,
        ),
        text: _cstr(bytes, offset + LabelExportAbi.text, _textBytes),
        layer: _cstr(bytes, offset + LabelExportAbi.layer, _layerBytes),
        icon: _cstr(bytes, offset + LabelExportAbi.icon, _iconBytes),
      ),
    );
  }
  return labels;
}

/// Decodes a null-terminated UTF-8 string within a fixed-width field.
///
/// Malformed input is replaced rather than rejected.
String _cstr(Uint8List bytes, int start, int max) {
  var end = start;
  while (end < start + max && bytes[end] != 0) {
    end += 1;
  }
  return utf8.decode(bytes.sublist(start, end), allowMalformed: true);
}
