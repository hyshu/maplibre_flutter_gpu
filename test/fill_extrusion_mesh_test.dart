import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/fill_extrusion/fill_extrusion_geometry.dart';
import 'package:maplibre_flutter_gpu/src/fill_extrusion/fill_extrusion_renderer.dart';

const _key = FillExtrusionTileKey(
  z: 14,
  x: 14552,
  y: 6451,
  overscaledZ: 14,
  wrap: 0,
  segment: 0,
);

class _Tile extends FillExtrusionTile {
  _Tile({required this.vertexCount, required this.parts});

  @override
  FillExtrusionTileKey get key => _key;

  @override
  final int vertexCount;

  @override
  final List<FillExtrusionPart> parts;

  @override
  Float32List get positions => Float32List(vertexCount * 3);

  @override
  Float32List get normals => Float32List(vertexCount * 2);

  @override
  Float32List get edgeDistances => Float32List(vertexCount);

  @override
  Uint8List get upperVertices => Uint8List(vertexCount);

  @override
  Uint16List get indices => Uint16List(0);
}

FillExtrusionPart _part(int index, int first, int count) => FillExtrusionPart(
  tile: _key,
  featureIndex: index,
  polygonIndex: 0,
  featureId: index,
  vertexOffset: first,
  vertexCount: count,
  indexOffset: index * 3,
  indexCount: 3,
);

FillExtrusionMesh _mesh({
  List<int> sources = const [0, 1, 2],
  List<int> triangles = const [0, 1, 2],
  Float32List? positions,
  Float32List? heightFractions,
  Float32List? heightOffsets,
  Float32List? normals,
  Float32List? edgeDistances,
}) => FillExtrusionMesh(
  positions: positions ?? Float32List(sources.length * 2),
  heightFractions: heightFractions ?? Float32List(sources.length),
  heightOffsets: heightOffsets,
  normals:
      normals ??
      Float32List.fromList([
        for (final _ in sources) ...[0, 0, 1],
      ]),
  indices: triangles,
  sourceVertexIndices: Uint16List.fromList(sources),
  edgeDistances: edgeDistances,
);

void main() {
  group('mesh snapshots', () {
    test('owns immutable copies of every supplied array', () {
      final positions = Float32List.fromList([1, 2, 3, 4, 5, 6]);
      final fractions = Float32List.fromList([0, 0.5, 1]);
      final offsets = Float32List.fromList([-1, 0, 2]);
      final normals = Float32List.fromList([0, 0, 2, 0, 0, 2, 0, 0, 2]);
      final indices = Uint16List.fromList([0, 1, 2]);
      final sources = Uint16List.fromList([3, 4, 5]);
      final distances = Float32List.fromList([0, 10, 20]);
      final mesh = FillExtrusionMesh(
        positions: positions,
        heightFractions: fractions,
        heightOffsets: offsets,
        normals: normals,
        indices: indices,
        sourceVertexIndices: sources,
        edgeDistances: distances,
      );
      positions[0] = 100;
      fractions[0] = 100;
      offsets[0] = 100;
      normals[2] = 100;
      indices[0] = 2;
      sources[0] = 0;
      distances[0] = 100;

      expect(mesh.positions.first, 1);
      expect(mesh.heightFractions, [0, 0.5, 1]);
      expect(mesh.heightOffsets, [-1, 0, 2]);
      expect(mesh.normals[2], 2);
      expect(mesh.indices, [0, 1, 2]);
      expect(mesh.sourceVertexIndices, [3, 4, 5]);
      expect(mesh.edgeDistances, [0, 10, 20]);
      expect(mesh.vertexCount, 3);
      expect(() => mesh.positions[0] = 0, throwsUnsupportedError);
      expect(() => mesh.heightFractions[0] = 0, throwsUnsupportedError);
      expect(() => mesh.heightOffsets![0] = 0, throwsUnsupportedError);
      expect(() => mesh.normals[0] = 0, throwsUnsupportedError);
      expect(() => mesh.indices[0] = 0, throwsUnsupportedError);
      expect(() => mesh.sourceVertexIndices[0] = 0, throwsUnsupportedError);
      expect(() => mesh.edgeDistances![0] = 0, throwsUnsupportedError);
      expect(
        () => mesh.positions.buffer.asFloat32List()[0] = 0,
        throwsUnsupportedError,
      );
    });

    test('allows empty geometry to remove every triangle', () {
      final mesh = _mesh(sources: [], triangles: []);

      expect(mesh.vertexCount, 0);
      expect(mesh.indices, isEmpty);
      expect(mesh.heightOffsets, isNull);
      expect(mesh.edgeDistances, isNull);
    });

    test('preserves replacement indices beyond the native 16-bit range', () {
      final mesh = _mesh(
        sources: List<int>.filled(65538, 0),
        triangles: [65535, 65536, 65537],
      );

      expect(mesh.vertexCount, 65538);
      expect(mesh.indices, [65535, 65536, 65537]);
      expect(mesh.indices.lengthInBytes, 12);
    });

    test('rejects inconsistent vertex and triangle array lengths', () {
      expect(() => _mesh(positions: Float32List(5)), throwsArgumentError);
      expect(() => _mesh(positions: Float32List(8)), throwsArgumentError);
      expect(() => _mesh(normals: Float32List(6)), throwsArgumentError);
      expect(() => _mesh(heightFractions: Float32List(2)), throwsArgumentError);
      expect(() => _mesh(heightOffsets: Float32List(4)), throwsArgumentError);
      expect(() => _mesh(edgeDistances: Float32List(2)), throwsArgumentError);
      expect(() => _mesh(triangles: [0, 1]), throwsArgumentError);
    });

    test('rejects invalid indices and zero-length normals', () {
      expect(() => _mesh(triangles: [0, 1, 3]), throwsArgumentError);
      expect(() => _mesh(triangles: [-1, 1, 2]), throwsArgumentError);
      expect(() => _mesh(triangles: [0x100000000, 1, 2]), throwsArgumentError);
      expect(() => _mesh(normals: Float32List(9)), throwsArgumentError);
    });

    test('rejects non-finite values in each float stream', () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => _mesh(positions: Float32List(6)..[0] = value),
          throwsArgumentError,
        );
        expect(
          () => _mesh(heightFractions: Float32List(3)..[0] = value),
          throwsArgumentError,
        );
        expect(
          () => _mesh(heightOffsets: Float32List(3)..[0] = value),
          throwsArgumentError,
        );
        expect(
          () => _mesh(
            normals: Float32List.fromList([value, 0, 1, 0, 0, 1, 0, 0, 1]),
          ),
          throwsArgumentError,
        );
        expect(
          () => _mesh(edgeDistances: Float32List(3)..[0] = value),
          throwsArgumentError,
        );
      }
    });
  });

  group('source part ownership', () {
    final tile = _Tile(vertexCount: 9, parts: [_part(0, 0, 3), _part(1, 3, 3)]);

    test('maps reordered and duplicated vertices to their source parts', () {
      final mesh = _mesh(
        sources: [5, 3, 3, 2, 1, 0, 6, 7, 8],
        triangles: [0, 1, 2, 3, 4, 5, 6, 7, 8],
      );

      expect(fillExtrusionMeshPartIndices(tile, mesh), [
        1,
        1,
        1,
        0,
        0,
        0,
        -1,
        -1,
        -1,
      ]);
    });

    test('rejects source vertices outside the tile', () {
      expect(
        () => fillExtrusionMeshPartIndices(tile, _mesh(sources: [9, 9, 9])),
        throwsArgumentError,
      );
    });

    test('rejects triangles spanning different source parts', () {
      expect(
        () => fillExtrusionMeshPartIndices(tile, _mesh(sources: [0, 1, 3])),
        throwsArgumentError,
      );
      expect(
        () => fillExtrusionMeshPartIndices(tile, _mesh(sources: [0, 1, 8])),
        throwsArgumentError,
      );
    });

    test('returns empty ownership for an empty replacement', () {
      expect(
        fillExtrusionMeshPartIndices(tile, _mesh(sources: [], triangles: [])),
        isEmpty,
      );
    });

    test('filters replacement triangles while retaining unowned vertices', () {
      final mesh = _mesh(
        sources: [3, 4, 5, 0, 1, 2, 6, 7, 8],
        triangles: [0, 1, 2, 3, 4, 5, 6, 7, 8],
      );
      final parts = fillExtrusionMeshPartIndices(tile, mesh);

      expect(
        visibleFillExtrusionMeshIndices(mesh, parts, [true, true]),
        isNull,
      );
      expect(visibleFillExtrusionMeshIndices(mesh, parts, [true, false]), [
        3,
        4,
        5,
        6,
        7,
        8,
      ]);
      expect(visibleFillExtrusionMeshIndices(mesh, parts, [false, false]), [
        6,
        7,
        8,
      ]);
    });

    test('returns empty indices when all replacement triangles are hidden', () {
      final mesh = _mesh();
      final parts = fillExtrusionMeshPartIndices(tile, mesh);

      expect(
        visibleFillExtrusionMeshIndices(mesh, parts, [false, true]),
        isEmpty,
      );
    });

    test('visibility filtering preserves indices above 65535', () {
      final sources = List<int>.filled(65538, 0);
      sources.fillRange(65535, 65538, 3);
      final mesh = _mesh(
        sources: sources,
        triangles: [0, 1, 2, 65535, 65536, 65537],
      );
      final parts = fillExtrusionMeshPartIndices(tile, mesh);
      final visible = visibleFillExtrusionMeshIndices(mesh, parts, [
        false,
        true,
      ])!;

      expect(visible, [65535, 65536, 65537]);
      expect(visible.lengthInBytes, 12);
    });
  });

  test(
    'remaps all packed custom attributes including repeated source vertices',
    () {
      final attributes = Float32List.fromList([
        for (var source = 0; source < 3; source += 1)
          for (var component = 0; component < 8; component += 1)
            source * 10.0 + component,
      ]);
      final mapped = packFillExtrusionMeshAttributes(
        attributes,
        Uint16List.fromList([2, 0, 2, 1]),
      );

      expect(mapped, [
        ...attributes.sublist(16, 24),
        ...attributes.sublist(0, 8),
        ...attributes.sublist(16, 24),
        ...attributes.sublist(8, 16),
      ]);
      expect(
        packFillExtrusionMeshAttributes(attributes, Uint16List(0)),
        isEmpty,
      );
    },
  );
}
