part of '../label_export_decoder.dart';

/// Applies split placement geometry to cached static label content.
List<LabelData> decodeLabelDynamicExports({
  required Uint8List bytes,
  required Uint8List blob,
  required int count,
  required int stride,
  required List<DecodedLabelStatic> staticLabels,
}) {
  if (count <= 0) return const [];
  if (stride != LabelDynamicExportAbi.size) return const [];
  if (bytes.lengthInBytes < count * stride) return const [];
  final data = ByteData.sublistView(bytes);
  final blobData = ByteData.sublistView(blob);
  final labels = <LabelData>[];
  final paths = <({int offset, int count}), List<LabelPathPoint>>{};
  List<LabelPathPoint> path(int offset, int count) => paths.putIfAbsent((
    offset: offset,
    count: count,
  ), () => .unmodifiable(_path(blobData, offset, count)));
  try {
    for (var index = 0; index < count; index++) {
      final offset = index * stride;
      final staticIndex = data.getUint32(
        offset + LabelDynamicExportAbi.staticIndex,
        Endian.little,
      );
      if (staticIndex >= staticLabels.length) return const [];
      final cached = staticLabels[staticIndex].label;
      final flags = data.getUint32(
        offset + LabelDynamicExportAbi.flags,
        Endian.little,
      );
      labels.add(
        .new(
          lat: data.getFloat64(
            offset + LabelDynamicExportAbi.lat,
            Endian.little,
          ),
          lon: data.getFloat64(
            offset + LabelDynamicExportAbi.lon,
            Endian.little,
          ),
          iconLat: data.getFloat64(
            offset + LabelDynamicExportAbi.iconLat,
            Endian.little,
          ),
          iconLon: data.getFloat64(
            offset + LabelDynamicExportAbi.iconLon,
            Endian.little,
          ),
          fontSize: cached.fontSize,
          textR: cached.textR,
          textG: cached.textG,
          textB: cached.textB,
          textA: cached.textA,
          haloR: cached.haloR,
          haloG: cached.haloG,
          haloB: cached.haloB,
          haloA: cached.haloA,
          haloWidth: cached.haloWidth,
          textOpacity: cached.textOpacity,
          haloBlur: cached.haloBlur,
          letterSpacing: cached.letterSpacing,
          lineHeight: cached.lineHeight,
          maxWidth: cached.maxWidth,
          textFont: cached.textFont,
          textFonts: cached.textFonts,
          textSections: cached.textSections,
          visualTextSections: cached.visualTextSections,
          textPath: path(
            data.getUint32(
              offset + LabelDynamicExportAbi.textPathOffset,
              Endian.little,
            ),
            data.getUint32(
              offset + LabelDynamicExportAbi.textPathCount,
              Endian.little,
            ),
          ),
          iconPath: path(
            data.getUint32(
              offset + LabelDynamicExportAbi.iconPathOffset,
              Endian.little,
            ),
            data.getUint32(
              offset + LabelDynamicExportAbi.iconPathCount,
              Endian.little,
            ),
          ),
          textW: data.getFloat32(
            offset + LabelDynamicExportAbi.textW,
            Endian.little,
          ),
          textH: data.getFloat32(
            offset + LabelDynamicExportAbi.textH,
            Endian.little,
          ),
          iconW: data.getFloat32(
            offset + LabelDynamicExportAbi.iconW,
            Endian.little,
          ),
          iconH: data.getFloat32(
            offset + LabelDynamicExportAbi.iconH,
            Endian.little,
          ),
          iconScale: cached.iconScale,
          iconOpacity: cached.iconOpacity,
          iconR: cached.iconR,
          iconG: cached.iconG,
          iconB: cached.iconB,
          iconA: cached.iconA,
          iconHaloR: cached.iconHaloR,
          iconHaloG: cached.iconHaloG,
          iconHaloB: cached.iconHaloB,
          iconHaloA: cached.iconHaloA,
          iconHaloWidth: cached.iconHaloWidth,
          iconHaloBlur: cached.iconHaloBlur,
          iconFitWidth: cached.iconFitWidth,
          iconFitHeight: cached.iconFitHeight,
          textOffsetX: data.getFloat32(
            offset + LabelDynamicExportAbi.textOffsetX,
            Endian.little,
          ),
          textOffsetY: data.getFloat32(
            offset + LabelDynamicExportAbi.textOffsetY,
            Endian.little,
          ),
          iconOffsetX: data.getFloat32(
            offset + LabelDynamicExportAbi.iconOffsetX,
            Endian.little,
          ),
          iconOffsetY: data.getFloat32(
            offset + LabelDynamicExportAbi.iconOffsetY,
            Endian.little,
          ),
          textPlaced: (flags & _textPlacedFlag) != 0,
          iconPlaced: (flags & _iconPlacedFlag) != 0,
          alongLine: (flags & _textAlongLineFlag) != 0,
          iconAlongLine: (flags & _iconAlongLineFlag) != 0,
          angle: data.getFloat32(
            offset + LabelDynamicExportAbi.textAngle,
            Endian.little,
          ),
          iconAngle: data.getFloat32(
            offset + LabelDynamicExportAbi.iconAngle,
            Endian.little,
          ),
          textRotation: cached.textRotation,
          iconRotation: cached.iconRotation,
          textTranslateX: data.getFloat32(
            offset + LabelDynamicExportAbi.textTranslateX,
            Endian.little,
          ),
          textTranslateY: data.getFloat32(
            offset + LabelDynamicExportAbi.textTranslateY,
            Endian.little,
          ),
          iconTranslateX: data.getFloat32(
            offset + LabelDynamicExportAbi.iconTranslateX,
            Endian.little,
          ),
          iconTranslateY: data.getFloat32(
            offset + LabelDynamicExportAbi.iconTranslateY,
            Endian.little,
          ),
          textTransform: .new(
            xx: data.getFloat32(
              offset + LabelDynamicExportAbi.textTransformXX,
              Endian.little,
            ),
            xy: data.getFloat32(
              offset + LabelDynamicExportAbi.textTransformXY,
              Endian.little,
            ),
            yx: data.getFloat32(
              offset + LabelDynamicExportAbi.textTransformYX,
              Endian.little,
            ),
            yy: data.getFloat32(
              offset + LabelDynamicExportAbi.textTransformYY,
              Endian.little,
            ),
          ),
          iconTransform: .new(
            xx: data.getFloat32(
              offset + LabelDynamicExportAbi.iconTransformXX,
              Endian.little,
            ),
            xy: data.getFloat32(
              offset + LabelDynamicExportAbi.iconTransformXY,
              Endian.little,
            ),
            yx: data.getFloat32(
              offset + LabelDynamicExportAbi.iconTransformYX,
              Endian.little,
            ),
            yy: data.getFloat32(
              offset + LabelDynamicExportAbi.iconTransformYY,
              Endian.little,
            ),
          ),
          textJustify: cached.textJustify,
          vertical: cached.vertical,
          iconSdf: cached.iconSdf,
          textPitchWithMap: cached.textPitchWithMap,
          textRotationWithMap: cached.textRotationWithMap,
          iconPitchWithMap: cached.iconPitchWithMap,
          iconRotationWithMap: cached.iconRotationWithMap,
          textKeepUpright: cached.textKeepUpright,
          iconKeepUpright: cached.iconKeepUpright,
          crossTileId: cached.crossTileId,
          tileWrap: data.getInt32(
            offset + LabelDynamicExportAbi.tileWrap,
            Endian.little,
          ),
          text: cached.text,
          visualText: cached.visualText,
          textDirection: cached.textDirection,
          layer: cached.layer,
          layerIndex: cached.layerIndex,
          renderGroup: cached.renderGroup,
          renderOrder: data.getUint32(
            offset + LabelDynamicExportAbi.renderOrder,
            Endian.little,
          ),
          icon: cached.icon,
        ),
      );
    }
  } on RangeError {
    return const [];
  }

  return labels;
}
