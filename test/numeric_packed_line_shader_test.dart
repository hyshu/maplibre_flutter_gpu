import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

const _variants = [
  ('Line', 'line'),
  ('LineSDF', 'line_sdf'),
  ('LineGradient', 'line_gradient'),
  ('LinePattern', 'line_pattern'),
  ('FillOutlineTriangulated', 'fill_outline_triangulated'),
];

void main() {
  for (final (name, stem) in _variants) {
    test('$name preserves uniforms, varyings and all original main math', () {
      final original = File('shaders/$stem.vert').readAsStringSync();
      final packed = File('shaders/${stem}_packed.vert').readAsStringSync();
      const uniformStart = 'layout(binding = 0) uniform ';
      const bodyStart = '    float dpr =';
      expect(
        packed.substring(
          packed.indexOf(uniformStart),
          packed.indexOf('void main()'),
        ),
        original.substring(
          original.indexOf(uniformStart),
          original.indexOf('void main()'),
        ),
      );
      expect(
        packed
            .substring(packed.indexOf(bodyStart))
            .replaceAll(RegExp(r'//[^\n]*'), ''),
        original
            .substring(original.indexOf(bodyStart))
            .replaceAll(RegExp(r'//[^\n]*'), ''),
      );
      expect(packed, contains('layout(location = 0) in highp vec3 a_packed;'));
      expect(packed, contains('#include "line_packed_decode.glsl"'));
      final decoder = File('shaders/line_packed_decode.glsl')
          .readAsStringSync();
      expect(decoder, contains('highp uvec3 words = uvec3(a_packed);'));
      expect(decoder, isNot(contains('floatBitsToUint')));
      final manifest = jsonDecode(
        File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(manifest['${name}PackedVertex'], {
        'type': 'vertex',
        'file': '${stem}_packed.vert',
      });
    });
  }

  test('all compiled variants use three floats and unchanged uniform ABI', () {
    final bytes = File('assets/shaderbundles/MapShaders.shaderbundle')
        .readAsBytesSync();
    expect(ascii.decode(bytes.sublist(4, 8)), 'IPSB');
    final data = ByteData.sublistView(bytes);
    final root = _Table(bytes, data.getUint32(0, Endian.little));
    final shaders = {
      for (final shader in root.tables(0)) shader.text(0): shader,
    };
    for (final (name, _) in _variants) {
      expect(
        shaders.containsKey('${name}PackedVertex'),
        isTrue,
        reason: 'Regenerate the shader bundle with the updated manifest.',
      );
      for (final backend in [1, 2, 3, 4, 5]) {
        final original = shaders['${name}Vertex']!.table(backend)!;
        final packed = shaders['${name}PackedVertex']!.table(backend)!;
        final inputs = packed.tables(2);
        expect(inputs, hasLength(1));
        final input = inputs.single;
        final originalInput = original.tables(2).first;
        expect(input.text(0), 'a_packed');
        expect(input.integer32(4), originalInput.integer32(4));
        expect(input.integer(1), 0);
        expect(input.integer(5), 32);
        expect(input.integer(6), 3);
        expect(input.integer(7), 1);
        expect(input.integer(8), 0);
        expect(
          packed.tables(3).map(_uniform),
          original.tables(3).map(_uniform),
          reason: '$name backend $backend uniform ABI',
        );
        if (name == 'Line') {
          final drawable = packed
              .tables(3)
              .firstWhere((block) => block.text(0) == 'LineDrawableUBO');
          expect(drawable.tables(5), hasLength(9));
          final ratio = drawable
              .tables(5)
              .firstWhere((member) => member.text(0) == 'u_ratio');
          final dpr = drawable
              .tables(5)
              .firstWhere((member) => member.text(0) == 'u_device_pixel_ratio');
          expect(ratio.integer(2), 64);
          expect(dpr.integer(2), 92);
          expect(dpr.integer(2) + dpr.integer(4), 96);
        }
      }
    }
  });
}

Map<String, Object> _uniform(_Table uniform) => {
  'name': uniform.text(0),
  'set': uniform.integer(2),
  'binding': uniform.integer(3),
  'size': uniform.integer(4),
  'fields': uniform.tables(5).map(_field).toList(),
};

Map<String, Object> _field(_Table field) => {
  'name': field.text(0),
  'type': field.integer32(1),
  for (var index = 2; index <= 7; index++) '$index': field.integer(index),
};

// Reads the documented Flutter shader bundle tables without altering them.
final class _Table {
  _Table(this.bytes, this.offset) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  final int offset;

  int? _fieldOffset(int field) {
    final vtable = offset - data.getInt32(offset, Endian.little);
    final entry = 4 + field * 2;
    if (entry >= data.getUint16(vtable, Endian.little)) return null;
    final relative = data.getUint16(vtable + entry, Endian.little);

    return relative == 0 ? null : offset + relative;
  }

  int? _target(int field) {
    final address = _fieldOffset(field);
    if (address == null) return null;

    return address + data.getUint32(address, Endian.little);
  }

  int integer(int field) {
    final address = _fieldOffset(field);

    return address == null ? 0 : data.getUint64(address, Endian.little);
  }

  int integer32(int field) {
    final address = _fieldOffset(field);

    return address == null ? 0 : data.getUint32(address, Endian.little);
  }

  String text(int field) {
    final address = _target(field);
    if (address == null) return '';
    final length = data.getUint32(address, Endian.little);

    return utf8.decode(bytes.sublist(address + 4, address + 4 + length));
  }

  _Table? table(int field) {
    final address = _target(field);

    return address == null ? null : _Table(bytes, address);
  }

  List<_Table> tables(int field) {
    final address = _target(field);
    if (address == null) return [];
    final length = data.getUint32(address, Endian.little);

    return List.generate(length, (index) {
      final entry = address + 4 + index * 4;

      return _Table(bytes, entry + data.getUint32(entry, Endian.little));
    });
  }
}
