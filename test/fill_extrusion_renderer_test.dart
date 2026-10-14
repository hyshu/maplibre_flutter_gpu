import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/fill_extrusion/fill_extrusion_geometry.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';
import 'package:maplibre_flutter_gpu/src/frame/uniform_packer.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/command_payload.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

import 'support/compact_command.dart';

const _key = FillExtrusionTileKey(
  z: 14,
  x: 14552,
  y: 6451,
  overscaledZ: 16,
  wrap: 0,
  segment: 0,
);

/// Builds vertices as MapLibre's FillExtrusionBucket lays out one ring.
///
/// Each point adds a roof vertex, and each edge adds a wall quad listing the
/// edge's later point twice and its earlier point twice. Normals are the edge
/// direction rotated by 90 degrees, as native exports them.
({Uint8List vertices, Uint16List indices}) _nativeRing(
  List<(double, double)> ring, {
  int stride = fillExtrusionConstantVertexStride,
  List<double> dataDrivenRanges = const [],
}) {
  final vertices = BytesBuilder();
  final indices = <int>[];
  var edgeDistance = 0;
  var vertex = 0;
  void add(double x, double y, double nx, double ny, int upper, int ed) {
    final data = ByteData(stride);
    final intX = x.floor();
    final intY = y.floor();
    final fractionX = ((x - intX) * 128).toInt();
    final fractionY = ((y - intY) * 128).toInt();
    data
      ..setInt16(0, intX, .little)
      ..setInt16(2, intY, .little)
      ..setUint16(4, (fractionX * 256 + fractionY) * 2 + upper, .little)
      ..setUint16(6, ed, .little)
      ..setInt16(8, (nx * 16384).round(), .little)
      ..setInt16(10, (ny * 16384).round(), .little);
    for (var index = 0; index < dataDrivenRanges.length; index += 1) {
      data.setFloat32(12 + index * 4, dataDrivenRanges[index], .little);
    }
    vertices.add(data.buffer.asUint8List());
    vertex += 1;
  }

  for (var index = 0; index < ring.length; index += 1) {
    final (x1, y1) = ring[index];
    add(x1, y1, 0, 0, 1, edgeDistance);
    if (index == ring.length - 1) continue;
    final (x2, y2) = ring[index + 1];
    final length = math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));
    final nx = -(y2 - y1) / length;
    final ny = (x2 - x1) / length;
    final quad = vertex;
    add(x2, y2, nx, ny, 0, edgeDistance);
    add(x2, y2, nx, ny, 1, edgeDistance);
    edgeDistance += length.floor();
    add(x1, y1, nx, ny, 0, edgeDistance);
    add(x1, y1, nx, ny, 1, edgeDistance);
    indices.addAll([quad, quad + 2, quad + 1, quad + 1, quad + 2, quad + 3]);
  }

  return (
    vertices: vertices.takeBytes(),
    indices: Uint16List.fromList(indices),
  );
}

DecodedFillExtrusionTile _tile(
  List<(double, double)> ring, {
  FillExtrusionHeights heights = const FillExtrusionHeights(
    base: 2,
    height: 30,
    baseT: 0,
    heightT: 0,
  ),
  int stride = fillExtrusionConstantVertexStride,
  List<double> dataDrivenRanges = const [],
}) {
  final native = _nativeRing(
    ring,
    stride: stride,
    dataDrivenRanges: dataDrivenRanges,
  );
  final vertexCount = native.vertices.length ~/ stride;

  return DecodedFillExtrusionTile(
    key: _key,
    parts: [
      FillExtrusionPart(
        tile: _key,
        featureIndex: 0,
        polygonIndex: 0,
        featureId: 1,
        vertexOffset: 0,
        vertexCount: vertexCount,
        indexOffset: 0,
        indexCount: native.indices.length,
      ),
    ],
    indices: native.indices,
    vertexData: native.vertices,
    vertexStride: stride,
    heights: heights,
  );
}

// A clockwise ring in tile coordinates, the Mapbox Vector Tile exterior winding.
const _exteriorSquare = [
  (100.0, 100.0),
  (200.0, 100.0),
  (200.0, 200.0),
  (100.0, 200.0),
  (100.0, 100.0),
];

void main() {
  test('the payload exposes fill-extrusion features', () {
    final command = TestCommand(
      sections: CommandPayloadSections.fillExtrusionFeatures,
    );
    final offset = command.fillExtrusionFeaturesOffset;
    expect(offset % 8, 0);
    command.payloadData
      ..setUint64(
        offset + CommandFillExtrusionFeaturesAbi.parts,
        0x1000,
        .little,
      )
      ..setUint64(
        offset + CommandFillExtrusionFeaturesAbi.layerId,
        0x2000,
        .little,
      )
      ..setUint32(
        offset + CommandFillExtrusionFeaturesAbi.partCount,
        3,
        .little,
      )
      ..setUint32(
        offset + CommandFillExtrusionFeaturesAbi.partStride,
        CommandFillExtrusionPartAbi.size,
        .little,
      )
      ..setUint32(
        offset + CommandFillExtrusionFeaturesAbi.layerIdLength,
        9,
        .little,
      )
      ..setInt32(offset + CommandFillExtrusionFeaturesAbi.tileWrap, -1, .little)
      ..setUint32(
        offset + CommandFillExtrusionFeaturesAbi.tileOverscaledZ,
        16,
        .little,
      )
      ..setUint32(offset + CommandFillExtrusionFeaturesAbi.tileZ, 14, .little)
      ..setUint32(offset + CommandFillExtrusionFeaturesAbi.tileX, 3, .little)
      ..setUint32(offset + CommandFillExtrusionFeaturesAbi.tileY, 5, .little)
      ..setUint32(
        offset + CommandFillExtrusionFeaturesAbi.segmentIndex,
        2,
        .little,
      );
    final reader = command.reader;
    expect(reader.read(command.data, 0), isTrue);
    expect(reader.hasFillExtrusionFeatures, isTrue);
    expect(reader.fillExtrusionPartsAddress, 0x1000);
    expect(reader.fillExtrusionLayerIdAddress, 0x2000);
    expect(reader.fillExtrusionLayerIdLength, 9);
    expect(reader.fillExtrusionPartCount, 3);
    expect(reader.fillExtrusionPartStride, CommandFillExtrusionPartAbi.size);
    expect(reader.fillExtrusionTileWrap, -1);
    expect(reader.fillExtrusionTileOverscaledZ, 16);
    expect(reader.fillExtrusionTileZ, 14);
    expect(reader.fillExtrusionTileX, 3);
    expect(reader.fillExtrusionTileY, 5);
    expect(reader.fillExtrusionSegmentIndex, 2);

    final plain = TestCommand(sections: 0).reader;
    expect(plain.hasFillExtrusionFeatures, isFalse);
    expect(plain.fillExtrusionPartsAddress, 0);
    expect(plain.fillExtrusionPartCount, 0);
  });

  test('part records decode every identifier kind', () {
    const stride = CommandFillExtrusionPartAbi.size;
    final records = ByteData(stride * 4);
    void record(int index, int type, void Function(int offset) writeId) {
      final offset = index * stride;
      records
        ..setUint32(
          offset + CommandFillExtrusionPartAbi.featureIndex,
          7,
          .little,
        )
        ..setUint32(
          offset + CommandFillExtrusionPartAbi.polygonIndex,
          index,
          .little,
        )
        ..setUint32(
          offset + CommandFillExtrusionPartAbi.vertexOffset,
          index * 10,
          .little,
        )
        ..setUint32(
          offset + CommandFillExtrusionPartAbi.vertexCount,
          10,
          .little,
        )
        ..setUint32(
          offset + CommandFillExtrusionPartAbi.indexOffset,
          index * 30,
          .little,
        )
        ..setUint32(
          offset + CommandFillExtrusionPartAbi.indexCount,
          30,
          .little,
        )
        ..setUint32(offset + CommandFillExtrusionPartAbi.idType, type, .little);
      writeId(offset);
    }

    record(
      0,
      FillExtrusionFeatureIdType.unsigned,
      (offset) => records.setUint64(
        offset + CommandFillExtrusionPartAbi.idValue,
        42,
        .little,
      ),
    );
    record(1, FillExtrusionFeatureIdType.string, (offset) {
      records
        ..setUint64(
          offset + CommandFillExtrusionPartAbi.idValue,
          0xBEEF,
          .little,
        )
        ..setUint32(offset + CommandFillExtrusionPartAbi.idLength, 5, .little);
    });
    record(
      2,
      FillExtrusionFeatureIdType.double,
      (offset) => records.setFloat64(
        offset + CommandFillExtrusionPartAbi.idValue,
        2.5,
        .little,
      ),
    );
    record(3, FillExtrusionFeatureIdType.none, (_) {});

    final parts = parseFillExtrusionParts(
      records,
      count: 4,
      stride: stride,
      tile: _key,
      readString: (address, length) => 'id@$address/$length',
    );
    expect(parts.map((part) => part.featureId), [
      42,
      'id@${0xBEEF}/5',
      2.5,
      null,
    ]);
    expect(parts.map((part) => part.polygonIndex), [0, 1, 2, 3]);
    expect(parts[2].vertexOffset, 20);
    expect(parts[3].indexOffset, 90);
    expect(parts.every((part) => part.featureIndex == 7), isTrue);
    expect(parts.every((part) => part.tile == _key), isTrue);

    expect(
      parseFillExtrusionParts(
        records,
        count: 5,
        stride: stride,
        tile: _key,
        readString: (_, _) => '',
      ),
      isEmpty,
    );
  });

  test('hidden parts are removed from the index list', () {
    final indices = Uint16List.fromList(List.generate(30, (index) => index));
    FillExtrusionPart part(int offset, int count) => FillExtrusionPart(
      tile: _key,
      featureIndex: 0,
      polygonIndex: 0,
      featureId: null,
      vertexOffset: 0,
      vertexCount: 0,
      indexOffset: offset,
      indexCount: count,
    );
    // Indices 18 to 29 belong to no part and always stay visible.
    final parts = [part(6, 12), part(0, 6)];

    expect(visibleFillExtrusionIndices(indices, parts, [true, true]), isNull);
    expect(visibleFillExtrusionIndices(indices, parts, [false, true]), [
      ...List.generate(6, (index) => index),
      ...List.generate(12, (index) => index + 18),
    ]);
    expect(
      visibleFillExtrusionIndices(indices, parts, [false, false]),
      List.generate(12, (index) => index + 18),
    );
  });

  test('vertices decode positions, heights, and outward normals', () {
    final ring = [
      (100.5, 100.25),
      (200.0, 100.25),
      (200.0, 200.0),
      (100.5, 200.0),
      (100.5, 100.25),
    ];
    final tile = _tile(ring);
    expect(tile.vertexCount, 5 + 4 * 4);
    expect(tile.isDataDriven, isFalse);
    expect(tile.positions[0], 100.5);
    expect(tile.positions[1], 100.25);
    expect(tile.positions[2], 30, reason: 'roof vertices use the height');
    // The first wall's later point at the base.
    expect(tile.positions.sublist(3, 6), [200.0, 100.25, 2.0]);
    expect(tile.upperVertices.sublist(0, 5), [1, 0, 1, 0, 1]);
    expect(tile.edgeDistances[3], 99, reason: 'the earlier point follows');

    // The first wall runs along the north side and must face north.
    expect(tile.normals[2], closeTo(0, 1e-6));
    expect(tile.normals[3], closeTo(-1, 1e-6));
    // The roof vertex has no normal.
    expect(tile.normals.sublist(0, 2), [0, 0]);

    // A ring with the opposite winding exports normals that already face out.
    final reversed = _tile(_exteriorSquare.reversed.toList());
    final northWall = [
      for (var vertex = 0; vertex < reversed.vertexCount; vertex += 1)
        if (reversed.positions[vertex * 3 + 1] == 100 &&
            reversed.normals[vertex * 2 + 1] != 0)
          reversed.normals[vertex * 2 + 1],
    ];
    expect(northWall, isNotEmpty);
    expect(northWall.every((y) => y < 0), isTrue);
  });

  test('data-driven heights interpolate each vertex range', () {
    final tile = _tile(
      _exteriorSquare,
      stride: fillExtrusionDataDrivenVertexStride,
      dataDrivenRanges: [4, 8, 20, 40, 1, 2, 3, 4],
      heights: const FillExtrusionHeights(
        base: 0,
        height: 0,
        baseT: 0.5,
        heightT: 0.25,
      ),
    );
    expect(tile.isDataDriven, isTrue);
    expect(tile.positions[2], 25, reason: 'roof at the interpolated height');
    expect(tile.positions[5], 6, reason: 'base at the interpolated base');

    final stream = tile.materialVertices();
    expect(
      stream.length,
      tile.vertexCount * fillExtrusionMaterialDataDrivenFloats,
    );
    expect(stream.sublist(8, 16), [4, 8, 20, 40, 1, 2, 3, 4]);
  });

  test('the material stream restores MapLibre normals for lighting', () {
    final tile = _tile(_exteriorSquare);
    final stream = tile.materialVertices();
    const floats = fillExtrusionMaterialConstantFloats;
    expect(stream.length, tile.vertexCount * floats);
    // Roof vertex: position, top flag, distance, no normal.
    expect(stream.sublist(0, 4), [100, 100, 1, 0]);
    expect(stream[6], 1);
    // The first wall vertex faces north and native exported it facing south.
    final wall = floats;
    expect(stream[wall + 2], 0, reason: 'base vertex');
    expect(stream[wall + 4], closeTo(0, 1e-6));
    expect(stream[wall + 5], closeTo(-1, 1e-6));
    expect(stream[wall + 6], -1);

    final reversed = _tile(_exteriorSquare.reversed.toList())
        .materialVertices();
    expect(reversed[wall + 6], 1);
  });

  test('application attributes spread to an eight-float stride', () {
    final packed = packFillExtrusionCustomAttributes(
      Float32List.fromList([1, 2, 3, 4, 5, 6]),
      vertexCount: 2,
      count: 3,
    );
    expect(packed, [1, 2, 3, 0, 0, 0, 0, 0, 4, 5, 6, 0, 0, 0, 0, 0]);
    expect(
      packFillExtrusionCustomAttributes(null, vertexCount: 1, count: 4),
      List.filled(8, 0.0),
    );
    expect(
      packFillExtrusionCustomAttributes(
        Float32List(3),
        vertexCount: 2,
        count: 4,
      ),
      List.filled(16, 0.0),
    );
  });

  test('tile coordinates convert to geography and meters', () {
    const key = FillExtrusionTileKey(
      z: 1,
      x: 1,
      y: 1,
      overscaledZ: 1,
      wrap: 1,
      segment: 0,
    );
    final tile = DecodedFillExtrusionTile(
      key: key,
      parts: const [],
      indices: Uint16List(0),
      vertexData: Uint8List(0),
      vertexStride: fillExtrusionConstantVertexStride,
      heights: const FillExtrusionHeights(
        base: 0,
        height: 0,
        baseT: 0,
        heightT: 0,
      ),
    );
    final corner = tile.latLngAt(0, 0);
    expect(corner.latitude, closeTo(0, 1e-9));
    expect(corner.longitude, closeTo(0, 1e-9));
    final southEast = tile.latLngAt(8192, 8192);
    expect(southEast.latitude, closeTo(-85.0511287798, 1e-6));
    expect(southEast.longitude, closeTo(-180, 1e-9));
    expect(tile.vertexCount, 0);
    expect(tile.positions, isEmpty);

    const equator = 2 * math.pi * 6378137.0 / 8192;
    expect(
      DecodedFillExtrusionTile(
        key: const FillExtrusionTileKey(
          z: 0,
          x: 0,
          y: 0,
          overscaledZ: 0,
          wrap: 0,
          segment: 0,
        ),
        parts: const [],
        indices: Uint16List(0),
        vertexData: Uint8List(0),
        vertexStride: fillExtrusionConstantVertexStride,
        heights: const FillExtrusionHeights(
          base: 0,
          height: 0,
          baseT: 0,
          heightT: 0,
        ),
      ).metersPerUnit,
      closeTo(equator, 1e-6),
    );
  });

  test('tile keys compare by value', () {
    const same = FillExtrusionTileKey(
      z: 14,
      x: 14552,
      y: 6451,
      overscaledZ: 16,
      wrap: 0,
      segment: 0,
    );
    expect(same, _key);
    expect(same.hashCode, _key.hashCode);
    expect(
      const FillExtrusionTileKey(
        z: 14,
        x: 14552,
        y: 6451,
        overscaledZ: 16,
        wrap: 0,
        segment: 1,
      ),
      isNot(_key),
    );
  });

  test('materials receive the tile scale in drawable padding', () {
    final command = TestCommand(
      drawableSize: RendererUboAbi.fillExtrusionDrawableBytes,
      propsSize: RendererUboAbi.fillExtrusionPropsBytes,
      sections: CommandPayloadSections.fillExtrusionFeatures,
    );
    final offset = command.fillExtrusionFeaturesOffset;
    command.payloadData
      ..setUint32(offset + CommandFillExtrusionFeaturesAbi.tileZ, 14, .little)
      ..setUint32(
        offset + CommandFillExtrusionFeaturesAbi.tileY,
        6451,
        .little,
      );
    expect(command.reader.read(command.data, 0), isTrue);
    final destination = Uint8List(512);
    final destinationData = ByteData.sublistView(destination);
    packCommandUniforms(
      payload: command.reader,
      destination: destination,
      destinationData: destinationData,
      shader: ShaderType.fillExtrusion,
      flags: 0,
      drawableOffset: 0,
      drawableLength: RendererUboAbi.fillExtrusionDrawableBytes,
      propsOffset: 256,
      propsLength: RendererUboAbi.fillExtrusionPropsBytes,
      tilePropsOffset: 0,
      tilePropsLength: 0,
      devicePixelRatio: 2,
      textureWidth: 0,
      textureHeight: 0,
    );
    final latitude = math.atan(
      _sinh(math.pi * (1 - 2 * (6451.5) / math.pow(2, 14))),
    );
    final expected =
        2 * math.pi * 6378137.0 * math.cos(latitude) / (math.pow(2, 14) * 8192);
    expect(
      destinationData.getFloat32(
        RendererUboAbi.fillExtrusionMetersPerUnitOffset,
        .little,
      ),
      closeTo(expected, 1e-6),
    );
  });
}

double _sinh(num value) => (math.exp(value) - math.exp(-value)) / 2;
