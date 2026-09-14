part of '../label_export_decoder.dart';

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
