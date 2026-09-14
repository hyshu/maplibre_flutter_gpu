part of '../label_export_decoder.dart';

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
          _decodeStaticScalars(
            data,
            offset,
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
      labels.add(
        .new(
          _decodeStaticScalars(
            data,
            offset,
            textFont: cached.textFont,
            textFonts: cached.textFonts,
            textSections: cached.textSections,
            visualTextSections: cached.visualTextSections,
            text: cached.text,
            visualText: cached.visualText,
            layer: cached.layer,
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

LabelData _decodeStaticScalars(
  ByteData data,
  int offset, {
  required String textFont,
  required List<String> textFonts,
  required List<LabelTextSection> textSections,
  required List<LabelTextSection> visualTextSections,
  required String text,
  required String visualText,
  required String layer,
  required String icon,
}) {
  final styleFlags = data.getUint32(
    offset + LabelStaticExportAbi.styleFlags,
    Endian.little,
  );

  return .new(
    lat: 0,
    lon: 0,
    fontSize: data.getFloat32(
      offset + LabelStaticExportAbi.fontSize,
      Endian.little,
    ),
    textR: data.getFloat32(offset + LabelStaticExportAbi.textR, Endian.little),
    textG: data.getFloat32(offset + LabelStaticExportAbi.textG, Endian.little),
    textB: data.getFloat32(offset + LabelStaticExportAbi.textB, Endian.little),
    textA: data.getFloat32(offset + LabelStaticExportAbi.textA, Endian.little),
    haloR: data.getFloat32(offset + LabelStaticExportAbi.haloR, Endian.little),
    haloG: data.getFloat32(offset + LabelStaticExportAbi.haloG, Endian.little),
    haloB: data.getFloat32(offset + LabelStaticExportAbi.haloB, Endian.little),
    haloA: data.getFloat32(offset + LabelStaticExportAbi.haloA, Endian.little),
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
    textFont: textFont,
    textFonts: textFonts,
    textSections: textSections,
    visualTextSections: visualTextSections,
    iconScale: data.getFloat32(
      offset + LabelStaticExportAbi.iconSize,
      Endian.little,
    ),
    iconOpacity: data.getFloat32(
      offset + LabelStaticExportAbi.iconOpacity,
      Endian.little,
    ),
    iconR: data.getFloat32(offset + LabelStaticExportAbi.iconR, Endian.little),
    iconG: data.getFloat32(offset + LabelStaticExportAbi.iconG, Endian.little),
    iconB: data.getFloat32(offset + LabelStaticExportAbi.iconB, Endian.little),
    iconA: data.getFloat32(offset + LabelStaticExportAbi.iconA, Endian.little),
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
      data.getUint32(offset + LabelStaticExportAbi.textJustify, Endian.little),
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
    text: text,
    visualText: visualText,
    layer: layer,
    layerIndex: data.getInt32(
      offset + LabelStaticExportAbi.layerIndex,
      Endian.little,
    ),
    renderGroup: data.getUint32(
      offset + LabelStaticExportAbi.renderGroup,
      Endian.little,
    ),
    renderOrder: 0,
    icon: icon,
  );
}
