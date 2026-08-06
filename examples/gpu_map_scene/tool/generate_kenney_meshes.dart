import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _jsonChunk = 0x4e4f534a;
const _binChunk = 0x004e4942;
const _glbMagic = 0x46546c67;

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/generate_kenney_meshes.dart '
      '<sedan.glb> <low-detail-building-a.glb>',
    );
    exitCode = 64;

    return;
  }

  final car = _readMesh(File(arguments[0]));
  final building = _readMesh(File(arguments[1]));
  final output = File('lib/gpu/kenney_mesh_data.dart');
  output.writeAsStringSync(_emitDart(car, building));
  stdout.writeln(
    'Generated ${output.path}: '
    'car ${car.vertices.length} vertices, '
    'building ${building.vertices.length} vertices',
  );
}

_Mesh _readMesh(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != _glbMagic ||
      data.getUint32(4, Endian.little) != 2) {
    throw FormatException('${file.path} is not a GLB 2.0 file');
  }

  Map<String, dynamic>? document;
  ByteData? binary;
  var offset = 12;
  while (offset < bytes.length) {
    final length = data.getUint32(offset, Endian.little);
    final type = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (type == _jsonChunk) {
      final source = utf8.decode(bytes.sublist(start, start + length)).trim();
      document = jsonDecode(source) as Map<String, dynamic>;
    } else if (type == _binChunk) {
      binary = ByteData.sublistView(bytes, start, start + length);
    }
    offset = start + length;
  }
  if (document == null || binary == null) {
    throw FormatException('${file.path} has no JSON or BIN chunk');
  }

  final accessors = document['accessors'] as List<dynamic>;
  final views = document['bufferViews'] as List<dynamic>;
  final meshes = document['meshes'] as List<dynamic>;
  final nodes = document['nodes'] as List<dynamic>;
  final sceneIndex = document['scene'] as int? ?? 0;
  final scenes = document['scenes'] as List<dynamic>;
  final scene = scenes[sceneIndex] as Map<String, dynamic>;
  final nodeIndices = (scene['nodes'] as List<dynamic>).cast<int>();

  final vertices = <_Vertex>[];
  final vertexLookup = <String, int>{};
  final triangles = <_Triangle>[];

  for (final nodeIndex in nodeIndices) {
    final node = nodes[nodeIndex] as Map<String, dynamic>;
    final meshIndex = node['mesh'] as int?;
    if (meshIndex == null) continue;
    final translation =
        (node['translation'] as List<dynamic>?)?.cast<num>() ??
        const <num>[0, 0, 0];
    final mesh = meshes[meshIndex] as Map<String, dynamic>;
    final primitives = mesh['primitives'] as List<dynamic>;

    for (final value in primitives) {
      final primitive = value as Map<String, dynamic>;
      if ((primitive['mode'] as int? ?? 4) != 4) {
        throw UnsupportedError('Only triangle GLB primitives are supported');
      }
      final attributes = primitive['attributes'] as Map<String, dynamic>;
      final positions = _readFloatAccessor(
        binary,
        accessors,
        views,
        attributes['POSITION'] as int,
        3,
      );
      final normals = _readFloatAccessor(
        binary,
        accessors,
        views,
        attributes['NORMAL'] as int,
        3,
      );
      final sourceIndices = _readIndexAccessor(
        binary,
        accessors,
        views,
        primitive['indices'] as int,
      );
      final remap = <int>[];

      for (var index = 0; index < positions.length ~/ 3; index++) {
        final vertex = _Vertex(
          positions[index * 3] + translation[0].toDouble(),
          positions[index * 3 + 1] + translation[1].toDouble(),
          positions[index * 3 + 2] + translation[2].toDouble(),
          normals[index * 3],
          normals[index * 3 + 1],
          normals[index * 3 + 2],
        );
        final key = vertex.key;
        final existing = vertexLookup[key];
        if (existing != null) {
          remap.add(existing);
        } else {
          final next = vertices.length;
          vertexLookup[key] = next;
          vertices.add(vertex);
          remap.add(next);
        }
      }

      for (var index = 0; index < sourceIndices.length; index += 3) {
        triangles.add(
          _Triangle(
            remap[sourceIndices[index]],
            remap[sourceIndices[index + 1]],
            remap[sourceIndices[index + 2]],
          ),
        );
      }
    }
  }

  var minX = double.infinity;
  var minY = double.infinity;
  var minZ = double.infinity;
  var maxX = double.negativeInfinity;
  var maxZ = double.negativeInfinity;
  for (final vertex in vertices) {
    minX = math.min(minX, vertex.x);
    minY = math.min(minY, vertex.y);
    minZ = math.min(minZ, vertex.z);
    maxX = math.max(maxX, vertex.x);
    maxZ = math.max(maxZ, vertex.z);
  }
  final centerX = (minX + maxX) / 2;
  final centerZ = (minZ + maxZ) / 2;
  final scale = 1 / math.max(maxX - minX, maxZ - minZ);
  for (final vertex in vertices) {
    vertex
      ..x = (vertex.x - centerX) * scale
      ..y = (vertex.y - minY) * scale
      ..z = (vertex.z - centerZ) * scale;
  }

  const viewDirection = (-1.0, 0.428, 0.65);
  double triangleDepth(_Triangle triangle) {
    final a = vertices[triangle.a];
    final b = vertices[triangle.b];
    final c = vertices[triangle.c];

    return ((a.x + b.x + c.x) * viewDirection.$1 +
            (a.y + b.y + c.y) * viewDirection.$2 +
            (a.z + b.z + c.z) * viewDirection.$3) /
        3;
  }

  triangles.sort(
    (left, right) => triangleDepth(left).compareTo(triangleDepth(right)),
  );

  return _Mesh(file.uri.pathSegments.last, vertices, triangles);
}

List<double> _readFloatAccessor(
  ByteData binary,
  List<dynamic> accessors,
  List<dynamic> views,
  int accessorIndex,
  int components,
) {
  final accessor = accessors[accessorIndex] as Map<String, dynamic>;
  if (accessor['componentType'] != 5126) {
    throw UnsupportedError('Expected a float accessor');
  }
  final view = views[accessor['bufferView'] as int] as Map<String, dynamic>;
  final stride = view['byteStride'] as int? ?? components * 4;
  final start =
      (view['byteOffset'] as int? ?? 0) + (accessor['byteOffset'] as int? ?? 0);
  final count = accessor['count'] as int;

  return [
    for (var index = 0; index < count; index++)
      for (var component = 0; component < components; component++)
        binary.getFloat32(
          start + index * stride + component * 4,
          Endian.little,
        ),
  ];
}

List<int> _readIndexAccessor(
  ByteData binary,
  List<dynamic> accessors,
  List<dynamic> views,
  int accessorIndex,
) {
  final accessor = accessors[accessorIndex] as Map<String, dynamic>;
  final view = views[accessor['bufferView'] as int] as Map<String, dynamic>;
  final type = accessor['componentType'] as int;
  final bytesPerIndex = switch (type) {
    5121 => 1,
    5123 => 2,
    5125 => 4,
    _ => throw UnsupportedError('Unsupported index component type $type'),
  };
  final stride = view['byteStride'] as int? ?? bytesPerIndex;
  final start =
      (view['byteOffset'] as int? ?? 0) + (accessor['byteOffset'] as int? ?? 0);
  final count = accessor['count'] as int;

  return [
    for (var index = 0; index < count; index++)
      switch (type) {
        5121 => binary.getUint8(start + index * stride),
        5123 => binary.getUint16(start + index * stride, Endian.little),
        5125 => binary.getUint32(start + index * stride, Endian.little),
        _ => throw StateError('unreachable'),
      },
  ];
}

String _emitDart(_Mesh car, _Mesh building) {
  final output = StringBuffer()
    ..writeln('// Generated by tool/generate_kenney_meshes.dart.')
    ..writeln('// Source assets are CC0 by Kenney (https://kenney.nl/).')
    ..writeln('// Vertex layout: position.xyz, normal.xyz.')
    ..writeln()
    ..writeln('class KenneyMeshData {')
    ..writeln('  const KenneyMeshData({')
    ..writeln('    required this.sourceName,')
    ..writeln('    required this.vertices,')
    ..writeln('    required this.indices,')
    ..writeln('  });')
    ..writeln()
    ..writeln('  final String sourceName;')
    ..writeln('  final List<double> vertices;')
    ..writeln('  final List<int> indices;')
    ..writeln('}')
    ..writeln()
    ..writeln('// dart format off');
  _emitMesh(output, 'kenneySedanMesh', car);
  output.writeln();
  _emitMesh(output, 'kenneyBuildingMesh', building);
  output.writeln('// dart format on');

  return output.toString();
}

void _emitMesh(StringBuffer output, String variable, _Mesh mesh) {
  output
    ..writeln('const $variable = KenneyMeshData(')
    ..writeln("  sourceName: '${mesh.name}',")
    ..writeln('  vertices: <double>[');
  for (final vertex in mesh.vertices) {
    output.writeln(
      '    ${_number(vertex.x)}, ${_number(vertex.y)}, '
      '${_number(vertex.z)}, ${_number(vertex.nx)}, '
      '${_number(vertex.ny)}, ${_number(vertex.nz)},',
    );
  }
  output.writeln('  ],');
  output.writeln('  indices: <int>[');
  for (var index = 0; index < mesh.triangles.length; index += 6) {
    final end = math.min(index + 6, mesh.triangles.length);
    output.write('    ');
    for (var triangleIndex = index; triangleIndex < end; triangleIndex++) {
      final triangle = mesh.triangles[triangleIndex];
      output.write('${triangle.a}, ${triangle.b}, ${triangle.c}, ');
    }
    output.writeln();
  }
  output
    ..writeln('  ],')
    ..writeln(');');
}

String _number(double value) {
  final rounded = double.parse(value.toStringAsFixed(6));

  return rounded == 0 ? '0.0' : rounded.toString();
}

class _Vertex {
  _Vertex(this.x, this.y, this.z, this.nx, this.ny, this.nz);

  double x;
  double y;
  double z;
  final double nx;
  final double ny;
  final double nz;

  String get key =>
      '${x.toStringAsFixed(6)},${y.toStringAsFixed(6)},'
      '${z.toStringAsFixed(6)},${nx.toStringAsFixed(6)},'
      '${ny.toStringAsFixed(6)},${nz.toStringAsFixed(6)}';
}

class _Triangle {
  const _Triangle(this.a, this.b, this.c);

  final int a;
  final int b;
  final int c;
}

class _Mesh {
  const _Mesh(this.name, this.vertices, this.triangles);

  final String name;
  final List<_Vertex> vertices;
  final List<_Triangle> triangles;
}
