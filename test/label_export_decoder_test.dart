import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/label_export_decoder.dart';

/// Builds one `LabelExport` record the way the native bridge lays it out.
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

  /// Writes a NUL-terminated string into one of the fixed char buffers.
  void str(int offset, String value, int capacity) {
    final encoded = utf8.encode(value);
    expect(
      encoded.length,
      lessThan(capacity),
      reason: 'test string must leave room for the terminator',
    );
    bytes.setRange(offset, offset + encoded.length, encoded);
  }
}

Uint8List _buffer(List<_Export> exports) {
  final bytes = Uint8List(exports.length * LabelExportAbi.size);
  for (var i = 0; i < exports.length; i++) {
    bytes.setRange(
      i * LabelExportAbi.size,
      (i + 1) * LabelExportAbi.size,
      exports[i].bytes,
    );
  }
  return bytes;
}

void main() {
  group('record framing', () {
    test('decodes each record at its own stride', () {
      final first = _Export()..f64(LabelExportAbi.lat, 35.5);
      final second = _Export()..f64(LabelExportAbi.lat, 12.25);

      final labels = decodeLabelExports(
        bytes: _buffer(<_Export>[first, second]),
        count: 2,
        stride: LabelExportAbi.size,
      );

      expect(labels, hasLength(2));
      expect(labels[0].lat, 35.5);
      expect(labels[1].lat, 12.25);
    });

    test('an ABI stride mismatch decodes nothing', () {
      // Every offset below would address the wrong field, so plausible-looking
      // garbage is worse than no labels at all.
      expect(
        decodeLabelExports(
          bytes: _buffer(<_Export>[_Export()]),
          count: 1,
          stride: LabelExportAbi.size - 8,
        ),
        isEmpty,
      );
    });

    test('a buffer shorter than the record count decodes nothing', () {
      expect(
        decodeLabelExports(
          bytes: _buffer(<_Export>[_Export()]),
          count: 2,
          stride: LabelExportAbi.size,
        ),
        isEmpty,
      );
    });

    test('an empty frame decodes nothing', () {
      expect(
        decodeLabelExports(
          bytes: Uint8List(0),
          count: 0,
          stride: LabelExportAbi.size,
        ),
        isEmpty,
      );
    });
  });

  group('anchors and offsets', () {
    test('keeps the text anchor separate from the icon anchor', () {
      // These are distinct map positions; conflating them drags icons onto
      // their labels, which still looks like a rendered map.
      final export = _Export()
        ..f64(LabelExportAbi.lat, 35.68)
        ..f64(LabelExportAbi.lon, 139.76)
        ..f64(LabelExportAbi.iconLat, 35.10)
        ..f64(LabelExportAbi.iconLon, 139.10);

      final label = decodeLabelExports(
        bytes: export.bytes,
        count: 1,
        stride: LabelExportAbi.size,
      ).single;

      expect(label.lat, 35.68);
      expect(label.lon, 139.76);
      expect(label.iconLat, 35.10);
      expect(label.iconLon, 139.10);
    });

    test('keeps text and icon screen offsets apart', () {
      final export = _Export()
        ..f32(LabelExportAbi.textOffsetX, 1)
        ..f32(LabelExportAbi.textOffsetY, 2)
        ..f32(LabelExportAbi.iconOffsetX, 3)
        ..f32(LabelExportAbi.iconOffsetY, 4);

      final label = decodeLabelExports(
        bytes: export.bytes,
        count: 1,
        stride: LabelExportAbi.size,
      ).single;

      expect(label.textOffsetX, 1);
      expect(label.textOffsetY, 2);
      expect(label.iconOffsetX, 3);
      expect(label.iconOffsetY, 4);
    });
  });

  group('flags', () {
    test('unpacks placement bits independently', () {
      for (final expected in <({int bits, bool text, bool icon, bool line})>[
        (bits: 0, text: false, icon: false, line: false),
        (bits: 1, text: true, icon: false, line: false),
        (bits: 2, text: false, icon: true, line: false),
        (bits: 4, text: false, icon: false, line: true),
        (bits: 7, text: true, icon: true, line: true),
      ]) {
        final label = decodeLabelExports(
          bytes: (_Export()..u32(LabelExportAbi.flags, expected.bits)).bytes,
          count: 1,
          stride: LabelExportAbi.size,
        ).single;

        expect(
          label.textPlaced,
          expected.text,
          reason: 'bits ${expected.bits}',
        );
        expect(
          label.iconPlaced,
          expected.icon,
          reason: 'bits ${expected.bits}',
        );
        expect(label.alongLine, expected.line, reason: 'bits ${expected.bits}');
      }
    });
  });

  group('fixed-width strings', () {
    test('stops at the terminator rather than the buffer end', () {
      final export = _Export()
        ..str(LabelExportAbi.text, 'CENTRAL STATION', 128)
        ..str(LabelExportAbi.layer, 'place-labels', 64)
        ..str(LabelExportAbi.icon, 'rail_metro_11', 64);

      final label = decodeLabelExports(
        bytes: export.bytes,
        count: 1,
        stride: LabelExportAbi.size,
      ).single;

      expect(label.text, 'CENTRAL STATION');
      expect(label.layer, 'place-labels');
      expect(label.icon, 'rail_metro_11');
    });

    test('reads an empty buffer as an empty string', () {
      // An unset icon buffer is all zeroes; it must not read as one NUL char.
      final label = decodeLabelExports(
        bytes: _Export().bytes,
        count: 1,
        stride: LabelExportAbi.size,
      ).single;

      expect(label.text, isEmpty);
      expect(label.layer, isEmpty);
      expect(label.icon, isEmpty);
    });

    test('does not bleed one string field into the next', () {
      // The buffers are adjacent, so an off-by-one capacity would append the
      // following field's contents.
      final export = _Export()
        ..str(LabelExportAbi.text, 'A', 128)
        ..str(LabelExportAbi.layer, 'B', 64)
        ..str(LabelExportAbi.icon, 'C', 64);

      final label = decodeLabelExports(
        bytes: export.bytes,
        count: 1,
        stride: LabelExportAbi.size,
      ).single;

      expect(label.text, 'A');
      expect(label.layer, 'B');
      expect(label.icon, 'C');
    });
  });

  group('identity', () {
    test('carries the cross-tile id used to reconcile across frames', () {
      final label = decodeLabelExports(
        bytes: (_Export()..u32(LabelExportAbi.crossTileID, 4294967295)).bytes,
        count: 1,
        stride: LabelExportAbi.size,
      ).single;

      expect(label.crossTileId, 4294967295);
    });
  });
}
