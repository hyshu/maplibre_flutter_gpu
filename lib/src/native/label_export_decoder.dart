import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../labels/label_data.dart';
import 'abi_generated.dart';

const _textPlacedFlag = 1 << 0;
const _iconPlacedFlag = 1 << 1;
const _textAlongLineFlag = 1 << 2;
const _iconAlongLineFlag = 1 << 3;

const _verticalFlag = 1 << 0;
const _iconSdfFlag = 1 << 1;
const _textPitchMapFlag = 1 << 2;
const _textRotationMapFlag = 1 << 3;
const _iconPitchMapFlag = 1 << 4;
const _iconRotationMapFlag = 1 << 5;
const _textKeepUprightFlag = 1 << 6;
const _iconKeepUprightFlag = 1 << 7;
const _textRtlFlag = 1 << 8;

const _sectionColorFlag = 1 << 0;
const _sectionImageFlag = 1 << 1;

/// Decodes [count] fixed records and their variable-size [blob].
///
/// Returns an empty list when any record or blob reference is incomplete.
/// Returned objects do not retain either input buffer.
List<LabelData> decodeLabelExports({
  required Uint8List bytes,
  required Uint8List blob,
  required int count,
  required int stride,
}) {
  if (count <= 0) return const [];
  if (stride != LabelExportAbi.size) return const [];
  if (bytes.lengthInBytes < count * stride) return const [];
  final data = ByteData.sublistView(bytes);
  final blobData = ByteData.sublistView(blob);
  final labels = <LabelData>[];
  try {
    for (var index = 0; index < count; index++) {
      final offset = index * stride;
      final flags = data.getUint32(
        offset + LabelExportAbi.flags,
        Endian.little,
      );
      final styleFlags = data.getUint32(
        offset + LabelExportAbi.styleFlags,
        Endian.little,
      );
      final fonts = _strings(
        blob,
        blobData,
        data.getUint32(offset + LabelExportAbi.textFontsOffset, Endian.little),
        data.getUint32(offset + LabelExportAbi.textFontCount, Endian.little),
      );
      final visualText = _string(
        blob,
        data.getUint32(offset + LabelExportAbi.textOffset, Endian.little),
        data.getUint32(offset + LabelExportAbi.textLength, Endian.little),
      );
      final logicalTextLength = data.getUint32(
        offset + LabelExportAbi.logicalTextLength,
        Endian.little,
      );
      final logicalText = logicalTextLength == 0 && visualText.isNotEmpty
          ? visualText
          : _string(
              blob,
              data.getUint32(
                offset + LabelExportAbi.logicalTextOffset,
                Endian.little,
              ),
              logicalTextLength,
            );
      labels.add(
        .new(
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
          textFont: fonts.isEmpty ? '' : fonts.first,
          textFonts: .unmodifiable(fonts),
          textSections: .unmodifiable(
            _sections(
              blob,
              blobData,
              data.getUint32(
                offset + LabelExportAbi.textSectionsOffset,
                Endian.little,
              ),
              data.getUint32(
                offset + LabelExportAbi.textSectionCount,
                Endian.little,
              ),
            ),
          ),
          visualTextSections: .unmodifiable(
            _sections(
              blob,
              blobData,
              data.getUint32(
                offset + LabelExportAbi.visualTextSectionsOffset,
                Endian.little,
              ),
              data.getUint32(
                offset + LabelExportAbi.visualTextSectionCount,
                Endian.little,
              ),
            ),
          ),
          textPath: .unmodifiable(
            _path(
              blobData,
              data.getUint32(
                offset + LabelExportAbi.textPathOffset,
                Endian.little,
              ),
              data.getUint32(
                offset + LabelExportAbi.textPathCount,
                Endian.little,
              ),
            ),
          ),
          iconPath: .unmodifiable(
            _path(
              blobData,
              data.getUint32(
                offset + LabelExportAbi.iconPathOffset,
                Endian.little,
              ),
              data.getUint32(
                offset + LabelExportAbi.iconPathCount,
                Endian.little,
              ),
            ),
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
          iconHaloR: data.getFloat32(
            offset + LabelExportAbi.iconHaloR,
            Endian.little,
          ),
          iconHaloG: data.getFloat32(
            offset + LabelExportAbi.iconHaloG,
            Endian.little,
          ),
          iconHaloB: data.getFloat32(
            offset + LabelExportAbi.iconHaloB,
            Endian.little,
          ),
          iconHaloA: data.getFloat32(
            offset + LabelExportAbi.iconHaloA,
            Endian.little,
          ),
          iconHaloWidth: data.getFloat32(
            offset + LabelExportAbi.iconHaloWidth,
            Endian.little,
          ),
          iconHaloBlur: data.getFloat32(
            offset + LabelExportAbi.iconHaloBlur,
            Endian.little,
          ),
          iconFitWidth: data.getFloat32(
            offset + LabelExportAbi.iconFitWidth,
            Endian.little,
          ),
          iconFitHeight: data.getFloat32(
            offset + LabelExportAbi.iconFitHeight,
            Endian.little,
          ),
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
          alongLine: (flags & _textAlongLineFlag) != 0,
          iconAlongLine: (flags & _iconAlongLineFlag) != 0,
          angle: data.getFloat32(
            offset + LabelExportAbi.textAngle,
            Endian.little,
          ),
          iconAngle: data.getFloat32(
            offset + LabelExportAbi.iconAngle,
            Endian.little,
          ),
          textRotation: data.getFloat32(
            offset + LabelExportAbi.textRotation,
            Endian.little,
          ),
          iconRotation: data.getFloat32(
            offset + LabelExportAbi.iconRotation,
            Endian.little,
          ),
          textTranslateX: data.getFloat32(
            offset + LabelExportAbi.textTranslateX,
            Endian.little,
          ),
          textTranslateY: data.getFloat32(
            offset + LabelExportAbi.textTranslateY,
            Endian.little,
          ),
          iconTranslateX: data.getFloat32(
            offset + LabelExportAbi.iconTranslateX,
            Endian.little,
          ),
          iconTranslateY: data.getFloat32(
            offset + LabelExportAbi.iconTranslateY,
            Endian.little,
          ),
          textTransform: .new(
            xx: data.getFloat32(
              offset + LabelExportAbi.textTransformXX,
              Endian.little,
            ),
            xy: data.getFloat32(
              offset + LabelExportAbi.textTransformXY,
              Endian.little,
            ),
            yx: data.getFloat32(
              offset + LabelExportAbi.textTransformYX,
              Endian.little,
            ),
            yy: data.getFloat32(
              offset + LabelExportAbi.textTransformYY,
              Endian.little,
            ),
          ),
          iconTransform: .new(
            xx: data.getFloat32(
              offset + LabelExportAbi.iconTransformXX,
              Endian.little,
            ),
            xy: data.getFloat32(
              offset + LabelExportAbi.iconTransformXY,
              Endian.little,
            ),
            yx: data.getFloat32(
              offset + LabelExportAbi.iconTransformYX,
              Endian.little,
            ),
            yy: data.getFloat32(
              offset + LabelExportAbi.iconTransformYY,
              Endian.little,
            ),
          ),
          textJustify: _justify(
            data.getUint32(offset + LabelExportAbi.textJustify, Endian.little),
          ),
          vertical: (styleFlags & _verticalFlag) != 0,
          iconSdf: (styleFlags & _iconSdfFlag) != 0,
          textPitchWithMap: (styleFlags & _textPitchMapFlag) != 0,
          textRotationWithMap: (styleFlags & _textRotationMapFlag) != 0,
          iconPitchWithMap: (styleFlags & _iconPitchMapFlag) != 0,
          iconRotationWithMap: (styleFlags & _iconRotationMapFlag) != 0,
          textKeepUpright: (styleFlags & _textKeepUprightFlag) != 0,
          iconKeepUpright: (styleFlags & _iconKeepUprightFlag) != 0,
          textDirection: (styleFlags & _textRtlFlag) != 0 ? .rtl : .ltr,
          crossTileId: data.getUint32(
            offset + LabelExportAbi.crossTileID,
            Endian.little,
          ),
          tileWrap: data.getInt32(
            offset + LabelExportAbi.tileWrap,
            Endian.little,
          ),
          text: logicalText,
          visualText: visualText,
          layer: _string(
            blob,
            data.getUint32(offset + LabelExportAbi.layerOffset, Endian.little),
            data.getUint32(offset + LabelExportAbi.layerLength, Endian.little),
          ),
          layerIndex: data.getInt32(
            offset + LabelExportAbi.layerIndex,
            Endian.little,
          ),
          renderGroup: data.getUint32(
            offset + LabelExportAbi.renderGroup,
            Endian.little,
          ),
          renderOrder: data.getUint32(
            offset + LabelExportAbi.renderOrder,
            Endian.little,
          ),
          icon: _string(
            blob,
            data.getUint32(offset + LabelExportAbi.iconOffset, Endian.little),
            data.getUint32(offset + LabelExportAbi.iconLength, Endian.little),
          ),
        ),
      );
    }
  } on RangeError {
    return const [];
  } on FormatException {
    return const [];
  }

  return labels;
}

/// Static symbol content decoded once per native static snapshot.
final class DecodedLabelStatic {
  const new(this.label);

  /// A geometry-free label carrying the cached content and style values.
  final LabelData label;
}

/// Decodes the content and evaluated style portion of a split label snapshot.
List<DecodedLabelStatic> decodeLabelStaticExports({
  required Uint8List bytes,
  required Uint8List blob,
  required int count,
  required int stride,
}) {
  if (count <= 0) return const [];
  if (stride != LabelStaticExportAbi.size) return const [];
  if (bytes.lengthInBytes < count * stride) return const [];
  final data = ByteData.sublistView(bytes);
  final blobData = ByteData.sublistView(blob);
  final labels = <DecodedLabelStatic>[];
  try {
    for (var index = 0; index < count; index++) {
      final offset = index * stride;
      final styleFlags = data.getUint32(
        offset + LabelStaticExportAbi.styleFlags,
        Endian.little,
      );
      final List<String> fonts = .unmodifiable(
        _strings(
          blob,
          blobData,
          data.getUint32(
            offset + LabelStaticExportAbi.textFontsOffset,
            Endian.little,
          ),
          data.getUint32(
            offset + LabelStaticExportAbi.textFontCount,
            Endian.little,
          ),
        ),
      );
      final visualText = _string(
        blob,
        data.getUint32(offset + LabelStaticExportAbi.textOffset, Endian.little),
        data.getUint32(offset + LabelStaticExportAbi.textLength, Endian.little),
      );
      final logicalTextLength = data.getUint32(
        offset + LabelStaticExportAbi.logicalTextLength,
        Endian.little,
      );
      final logicalText = logicalTextLength == 0 && visualText.isNotEmpty
          ? visualText
          : _string(
              blob,
              data.getUint32(
                offset + LabelStaticExportAbi.logicalTextOffset,
                Endian.little,
              ),
              logicalTextLength,
            );
      labels.add(
        .new(
          .new(
            lat: 0,
            lon: 0,
            fontSize: data.getFloat32(
              offset + LabelStaticExportAbi.fontSize,
              Endian.little,
            ),
            textR: data.getFloat32(
              offset + LabelStaticExportAbi.textR,
              Endian.little,
            ),
            textG: data.getFloat32(
              offset + LabelStaticExportAbi.textG,
              Endian.little,
            ),
            textB: data.getFloat32(
              offset + LabelStaticExportAbi.textB,
              Endian.little,
            ),
            textA: data.getFloat32(
              offset + LabelStaticExportAbi.textA,
              Endian.little,
            ),
            haloR: data.getFloat32(
              offset + LabelStaticExportAbi.haloR,
              Endian.little,
            ),
            haloG: data.getFloat32(
              offset + LabelStaticExportAbi.haloG,
              Endian.little,
            ),
            haloB: data.getFloat32(
              offset + LabelStaticExportAbi.haloB,
              Endian.little,
            ),
            haloA: data.getFloat32(
              offset + LabelStaticExportAbi.haloA,
              Endian.little,
            ),
            haloWidth: data.getFloat32(
              offset + LabelStaticExportAbi.haloWidth,
              Endian.little,
            ),
            textOpacity: data.getFloat32(
              offset + LabelStaticExportAbi.textOpacity,
              Endian.little,
            ),
            haloBlur: data.getFloat32(
              offset + LabelStaticExportAbi.haloBlur,
              Endian.little,
            ),
            letterSpacing: data.getFloat32(
              offset + LabelStaticExportAbi.letterSpacing,
              Endian.little,
            ),
            lineHeight: data.getFloat32(
              offset + LabelStaticExportAbi.lineHeight,
              Endian.little,
            ),
            maxWidth: data.getFloat32(
              offset + LabelStaticExportAbi.maxWidth,
              Endian.little,
            ),
            textFont: fonts.isEmpty ? '' : fonts.first,
            textFonts: fonts,
            textSections: .unmodifiable(
              _sections(
                blob,
                blobData,
                data.getUint32(
                  offset + LabelStaticExportAbi.textSectionsOffset,
                  Endian.little,
                ),
                data.getUint32(
                  offset + LabelStaticExportAbi.textSectionCount,
                  Endian.little,
                ),
              ),
            ),
            visualTextSections: .unmodifiable(
              _sections(
                blob,
                blobData,
                data.getUint32(
                  offset + LabelStaticExportAbi.visualTextSectionsOffset,
                  Endian.little,
                ),
                data.getUint32(
                  offset + LabelStaticExportAbi.visualTextSectionCount,
                  Endian.little,
                ),
              ),
            ),
            iconScale: data.getFloat32(
              offset + LabelStaticExportAbi.iconSize,
              Endian.little,
            ),
            iconOpacity: data.getFloat32(
              offset + LabelStaticExportAbi.iconOpacity,
              Endian.little,
            ),
            iconR: data.getFloat32(
              offset + LabelStaticExportAbi.iconR,
              Endian.little,
            ),
            iconG: data.getFloat32(
              offset + LabelStaticExportAbi.iconG,
              Endian.little,
            ),
            iconB: data.getFloat32(
              offset + LabelStaticExportAbi.iconB,
              Endian.little,
            ),
            iconA: data.getFloat32(
              offset + LabelStaticExportAbi.iconA,
              Endian.little,
            ),
            iconHaloR: data.getFloat32(
              offset + LabelStaticExportAbi.iconHaloR,
              Endian.little,
            ),
            iconHaloG: data.getFloat32(
              offset + LabelStaticExportAbi.iconHaloG,
              Endian.little,
            ),
            iconHaloB: data.getFloat32(
              offset + LabelStaticExportAbi.iconHaloB,
              Endian.little,
            ),
            iconHaloA: data.getFloat32(
              offset + LabelStaticExportAbi.iconHaloA,
              Endian.little,
            ),
            iconHaloWidth: data.getFloat32(
              offset + LabelStaticExportAbi.iconHaloWidth,
              Endian.little,
            ),
            iconHaloBlur: data.getFloat32(
              offset + LabelStaticExportAbi.iconHaloBlur,
              Endian.little,
            ),
            iconFitWidth: data.getFloat32(
              offset + LabelStaticExportAbi.iconFitWidth,
              Endian.little,
            ),
            iconFitHeight: data.getFloat32(
              offset + LabelStaticExportAbi.iconFitHeight,
              Endian.little,
            ),
            textRotation: data.getFloat32(
              offset + LabelStaticExportAbi.textRotation,
              Endian.little,
            ),
            iconRotation: data.getFloat32(
              offset + LabelStaticExportAbi.iconRotation,
              Endian.little,
            ),
            textJustify: _justify(
              data.getUint32(
                offset + LabelStaticExportAbi.textJustify,
                Endian.little,
              ),
            ),
            vertical: (styleFlags & _verticalFlag) != 0,
            iconSdf: (styleFlags & _iconSdfFlag) != 0,
            textPitchWithMap: (styleFlags & _textPitchMapFlag) != 0,
            textRotationWithMap: (styleFlags & _textRotationMapFlag) != 0,
            iconPitchWithMap: (styleFlags & _iconPitchMapFlag) != 0,
            iconRotationWithMap: (styleFlags & _iconRotationMapFlag) != 0,
            textKeepUpright: (styleFlags & _textKeepUprightFlag) != 0,
            iconKeepUpright: (styleFlags & _iconKeepUprightFlag) != 0,
            textDirection: (styleFlags & _textRtlFlag) != 0 ? .rtl : .ltr,
            crossTileId: data.getUint32(
              offset + LabelStaticExportAbi.crossTileID,
              Endian.little,
            ),
            text: logicalText,
            visualText: visualText,
            layer: _string(
              blob,
              data.getUint32(
                offset + LabelStaticExportAbi.layerOffset,
                Endian.little,
              ),
              data.getUint32(
                offset + LabelStaticExportAbi.layerLength,
                Endian.little,
              ),
            ),
            layerIndex: data.getInt32(
              offset + LabelStaticExportAbi.layerIndex,
              Endian.little,
            ),
            renderGroup: data.getUint32(
              offset + LabelStaticExportAbi.renderGroup,
              Endian.little,
            ),
            renderOrder: 0,
            icon: _string(
              blob,
              data.getUint32(
                offset + LabelStaticExportAbi.iconOffset,
                Endian.little,
              ),
              data.getUint32(
                offset + LabelStaticExportAbi.iconLength,
                Endian.little,
              ),
            ),
          ),
        ),
      );
    }
  } on RangeError {
    return const [];
  } on FormatException {
    return const [];
  }

  return labels;
}

/// Refreshes static scalar values while retaining previously decoded content.
List<DecodedLabelStatic> decodeLabelStaticScalarExports({
  required Uint8List bytes,
  required int count,
  required int stride,
  required List<DecodedLabelStatic> previous,
}) {
  if (count <= 0) return const [];
  if (stride != LabelStaticExportAbi.size) return const [];
  if (bytes.lengthInBytes < count * stride || previous.length != count) {
    return const [];
  }
  final data = ByteData.sublistView(bytes);
  final labels = <DecodedLabelStatic>[];
  try {
    for (var index = 0; index < count; index++) {
      final offset = index * stride;
      final cached = previous[index].label;
      final styleFlags = data.getUint32(
        offset + LabelStaticExportAbi.styleFlags,
        Endian.little,
      );
      labels.add(
        .new(
          .new(
            lat: 0,
            lon: 0,
            fontSize: data.getFloat32(
              offset + LabelStaticExportAbi.fontSize,
              Endian.little,
            ),
            textR: data.getFloat32(
              offset + LabelStaticExportAbi.textR,
              Endian.little,
            ),
            textG: data.getFloat32(
              offset + LabelStaticExportAbi.textG,
              Endian.little,
            ),
            textB: data.getFloat32(
              offset + LabelStaticExportAbi.textB,
              Endian.little,
            ),
            textA: data.getFloat32(
              offset + LabelStaticExportAbi.textA,
              Endian.little,
            ),
            haloR: data.getFloat32(
              offset + LabelStaticExportAbi.haloR,
              Endian.little,
            ),
            haloG: data.getFloat32(
              offset + LabelStaticExportAbi.haloG,
              Endian.little,
            ),
            haloB: data.getFloat32(
              offset + LabelStaticExportAbi.haloB,
              Endian.little,
            ),
            haloA: data.getFloat32(
              offset + LabelStaticExportAbi.haloA,
              Endian.little,
            ),
            haloWidth: data.getFloat32(
              offset + LabelStaticExportAbi.haloWidth,
              Endian.little,
            ),
            textOpacity: data.getFloat32(
              offset + LabelStaticExportAbi.textOpacity,
              Endian.little,
            ),
            haloBlur: data.getFloat32(
              offset + LabelStaticExportAbi.haloBlur,
              Endian.little,
            ),
            letterSpacing: data.getFloat32(
              offset + LabelStaticExportAbi.letterSpacing,
              Endian.little,
            ),
            lineHeight: data.getFloat32(
              offset + LabelStaticExportAbi.lineHeight,
              Endian.little,
            ),
            maxWidth: data.getFloat32(
              offset + LabelStaticExportAbi.maxWidth,
              Endian.little,
            ),
            textFont: cached.textFont,
            textFonts: cached.textFonts,
            textSections: cached.textSections,
            visualTextSections: cached.visualTextSections,
            iconScale: data.getFloat32(
              offset + LabelStaticExportAbi.iconSize,
              Endian.little,
            ),
            iconOpacity: data.getFloat32(
              offset + LabelStaticExportAbi.iconOpacity,
              Endian.little,
            ),
            iconR: data.getFloat32(
              offset + LabelStaticExportAbi.iconR,
              Endian.little,
            ),
            iconG: data.getFloat32(
              offset + LabelStaticExportAbi.iconG,
              Endian.little,
            ),
            iconB: data.getFloat32(
              offset + LabelStaticExportAbi.iconB,
              Endian.little,
            ),
            iconA: data.getFloat32(
              offset + LabelStaticExportAbi.iconA,
              Endian.little,
            ),
            iconHaloR: data.getFloat32(
              offset + LabelStaticExportAbi.iconHaloR,
              Endian.little,
            ),
            iconHaloG: data.getFloat32(
              offset + LabelStaticExportAbi.iconHaloG,
              Endian.little,
            ),
            iconHaloB: data.getFloat32(
              offset + LabelStaticExportAbi.iconHaloB,
              Endian.little,
            ),
            iconHaloA: data.getFloat32(
              offset + LabelStaticExportAbi.iconHaloA,
              Endian.little,
            ),
            iconHaloWidth: data.getFloat32(
              offset + LabelStaticExportAbi.iconHaloWidth,
              Endian.little,
            ),
            iconHaloBlur: data.getFloat32(
              offset + LabelStaticExportAbi.iconHaloBlur,
              Endian.little,
            ),
            iconFitWidth: data.getFloat32(
              offset + LabelStaticExportAbi.iconFitWidth,
              Endian.little,
            ),
            iconFitHeight: data.getFloat32(
              offset + LabelStaticExportAbi.iconFitHeight,
              Endian.little,
            ),
            textRotation: data.getFloat32(
              offset + LabelStaticExportAbi.textRotation,
              Endian.little,
            ),
            iconRotation: data.getFloat32(
              offset + LabelStaticExportAbi.iconRotation,
              Endian.little,
            ),
            textJustify: _justify(
              data.getUint32(
                offset + LabelStaticExportAbi.textJustify,
                Endian.little,
              ),
            ),
            vertical: (styleFlags & _verticalFlag) != 0,
            iconSdf: (styleFlags & _iconSdfFlag) != 0,
            textPitchWithMap: (styleFlags & _textPitchMapFlag) != 0,
            textRotationWithMap: (styleFlags & _textRotationMapFlag) != 0,
            iconPitchWithMap: (styleFlags & _iconPitchMapFlag) != 0,
            iconRotationWithMap: (styleFlags & _iconRotationMapFlag) != 0,
            textKeepUpright: (styleFlags & _textKeepUprightFlag) != 0,
            iconKeepUpright: (styleFlags & _iconKeepUprightFlag) != 0,
            textDirection: (styleFlags & _textRtlFlag) != 0 ? .rtl : .ltr,
            crossTileId: data.getUint32(
              offset + LabelStaticExportAbi.crossTileID,
              Endian.little,
            ),
            text: cached.text,
            visualText: cached.visualText,
            layer: cached.layer,
            layerIndex: data.getInt32(
              offset + LabelStaticExportAbi.layerIndex,
              Endian.little,
            ),
            renderGroup: data.getUint32(
              offset + LabelStaticExportAbi.renderGroup,
              Endian.little,
            ),
            renderOrder: 0,
            icon: cached.icon,
          ),
        ),
      );
    }
  } on RangeError {
    return const [];
  }

  return labels;
}

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

String _string(Uint8List blob, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > blob.lengthInBytes) {
    throw RangeError('Label blob string is out of range');
  }

  return utf8.decode(blob.sublist(offset, offset + length));
}

List<String> _strings(Uint8List blob, ByteData data, int offset, int count) {
  if (count == 0) return const [];
  final size = LabelStringRefExportAbi.size * count;
  if (offset < 0 || offset + size > blob.lengthInBytes) {
    throw RangeError('Label blob string refs are out of range');
  }
  return .generate(count, (index) {
    final record = offset + index * LabelStringRefExportAbi.size;

    return _string(
      blob,
      data.getUint32(record + LabelStringRefExportAbi.offset, Endian.little),
      data.getUint32(record + LabelStringRefExportAbi.length, Endian.little),
    );
  }, growable: false);
}

List<LabelTextSection> _sections(
  Uint8List blob,
  ByteData data,
  int offset,
  int count,
) {
  if (count == 0) return const [];
  final size = LabelTextSectionExportAbi.size * count;
  if (offset < 0 || offset + size > blob.lengthInBytes) {
    throw RangeError('Label blob sections are out of range');
  }
  return .generate(count, (index) {
    final record = offset + index * LabelTextSectionExportAbi.size;
    final flags = data.getUint32(
      record + LabelTextSectionExportAbi.flags,
      Endian.little,
    );

    return .new(
      start: data.getUint32(
        record + LabelTextSectionExportAbi.start,
        Endian.little,
      ),
      end: data.getUint32(
        record + LabelTextSectionExportAbi.end,
        Endian.little,
      ),
      fontScale: data.getFloat32(
        record + LabelTextSectionExportAbi.fontScale,
        Endian.little,
      ),
      fonts: .unmodifiable(
        _strings(
          blob,
          data,
          data.getUint32(
            record + LabelTextSectionExportAbi.fontsOffset,
            Endian.little,
          ),
          data.getUint32(
            record + LabelTextSectionExportAbi.fontCount,
            Endian.little,
          ),
        ),
      ),
      color: (flags & _sectionColorFlag) == 0
          ? null
          : _premultipliedColor(
              data.getFloat32(
                record + LabelTextSectionExportAbi.colorR,
                Endian.little,
              ),
              data.getFloat32(
                record + LabelTextSectionExportAbi.colorG,
                Endian.little,
              ),
              data.getFloat32(
                record + LabelTextSectionExportAbi.colorB,
                Endian.little,
              ),
              data.getFloat32(
                record + LabelTextSectionExportAbi.colorA,
                Endian.little,
              ),
            ),
      imageId: (flags & _sectionImageFlag) == 0
          ? null
          : _string(
              blob,
              data.getUint32(
                record + LabelTextSectionExportAbi.imageOffset,
                Endian.little,
              ),
              data.getUint32(
                record + LabelTextSectionExportAbi.imageLength,
                Endian.little,
              ),
            ),
    );
  }, growable: false);
}

List<LabelPathPoint> _path(ByteData data, int offset, int count) {
  if (count == 0) return const [];
  final size = LabelPathPointExportAbi.size * count;
  if (offset < 0 || offset + size > data.lengthInBytes) {
    throw RangeError('Label blob path is out of range');
  }
  return .generate(count, (index) {
    final record = offset + index * LabelPathPointExportAbi.size;

    return .new(
      data.getFloat32(record + LabelPathPointExportAbi.x, Endian.little),
      data.getFloat32(record + LabelPathPointExportAbi.y, Endian.little),
    );
  }, growable: false);
}

LabelTextJustify _justify(int value) => switch (value) {
  0 => .auto,
  2 => .left,
  3 => .right,
  _ => .center,
};

Color _premultipliedColor(double r, double g, double b, double a) {
  final alpha = (a * 255).round().clamp(0, 255);
  if (alpha == 0) return const Color(0x00000000);

  return .fromARGB(
    alpha,
    (r / a * 255).round().clamp(0, 255),
    (g / a * 255).round().clamp(0, 255),
    (b / a * 255).round().clamp(0, 255),
  );
}
