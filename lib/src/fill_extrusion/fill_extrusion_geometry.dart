import 'dart:convert';
import 'dart:typed_data';

import '../native/abi_generated.dart';
import 'fill_extrusion_renderer.dart';

/// Native fill-extrusion vertex strides with constant and data-driven paint.
const fillExtrusionConstantVertexStride = 12;
const fillExtrusionDataDrivenVertexStride = 44;

/// Feature identifier kinds stored in exported part records.
abstract final class FillExtrusionFeatureIdType {
  static const none = 0;
  static const unsigned = 1;
  static const signed = 2;
  static const double = 3;
  static const string = 4;
}

/// The heights a command's vertex shader would use.
///
/// Constant layouts use [base] and [height]. Data-driven layouts interpolate
/// each vertex's ranges with [baseT] and [heightT].
final class const FillExtrusionHeights({
  required final double base,
  required final double height,
  required final double baseT,
  required final double heightT,
});

/// Reads part records exported for one command.
///
/// [readString] returns the text of a string identifier from its native
/// address and byte length. Records shorter than the known layout yield no
/// parts.
List<FillExtrusionPart> parseFillExtrusionParts(
  ByteData records, {
  required int count,
  required int stride,
  required FillExtrusionTileKey tile,
  required String Function(int address, int length) readString,
}) {
  if (count <= 0 ||
      stride < CommandFillExtrusionPartAbi.size ||
      records.lengthInBytes < count * stride) {
    return const [];
  }
  return List<FillExtrusionPart>.generate(count, (index) {
    final offset = index * stride;
    int field(int fieldOffset) =>
        records.getUint32(offset + fieldOffset, Endian.little);
    final idOffset = offset + CommandFillExtrusionPartAbi.idValue;
    final Object? featureId = switch (field(
      CommandFillExtrusionPartAbi.idType,
    )) {
      FillExtrusionFeatureIdType.unsigned => records.getUint64(
        idOffset,
        Endian.little,
      ),
      FillExtrusionFeatureIdType.signed => records.getInt64(
        idOffset,
        Endian.little,
      ),
      FillExtrusionFeatureIdType.double => records.getFloat64(
        idOffset,
        Endian.little,
      ),
      FillExtrusionFeatureIdType.string => readString(
        records.getUint64(idOffset, Endian.little),
        field(CommandFillExtrusionPartAbi.idLength),
      ),
      _ => null,
    };

    return FillExtrusionPart(
      tile: tile,
      featureIndex: field(CommandFillExtrusionPartAbi.featureIndex),
      polygonIndex: field(CommandFillExtrusionPartAbi.polygonIndex),
      featureId: featureId,
      vertexOffset: field(CommandFillExtrusionPartAbi.vertexOffset),
      vertexCount: field(CommandFillExtrusionPartAbi.vertexCount),
      indexOffset: field(CommandFillExtrusionPartAbi.indexOffset),
      indexCount: field(CommandFillExtrusionPartAbi.indexCount),
    );
  }, growable: false);
}

/// Decodes UTF-8 identifier bytes, replacing malformed sequences.
String decodeFillExtrusionId(Uint8List bytes) =>
    utf8.decode(bytes, allowMalformed: true);

/// Returns the indices of visible parts, or null when nothing is hidden.
///
/// Indices outside every part stay visible. [visible] holds one flag per part.
Uint16List? visibleFillExtrusionIndices(
  Uint16List indices,
  List<FillExtrusionPart> parts,
  List<bool> visible,
) {
  var hiddenCount = 0;
  for (var index = 0; index < parts.length; index += 1) {
    if (!visible[index]) hiddenCount += parts[index].indexCount;
  }
  if (hiddenCount == 0) return null;
  final result = Uint16List(indices.length - hiddenCount);
  var cursor = 0;
  var copied = 0;
  void copyUntil(int end) {
    final clamped = end.clamp(copied, indices.length);
    result.setRange(cursor, cursor + clamped - copied, indices, copied);
    cursor += clamped - copied;
    copied = clamped;
  }

  // Parts are exported in index order. Sorting keeps the copy correct for
  // any order.
  final order = List<int>.generate(parts.length, (index) => index)
    ..sort((a, b) => parts[a].indexOffset.compareTo(parts[b].indexOffset));
  for (final index in order) {
    if (visible[index]) continue;
    final part = parts[index];
    copyUntil(part.indexOffset);
    copied = (part.indexOffset + part.indexCount).clamp(copied, indices.length);
  }
  copyUntil(indices.length);

  return cursor == result.length
      ? result
      : Uint16List.sublistView(result, 0, cursor);
}

/// Floats per vertex in the material stream for constant and data-driven paint.
const fillExtrusionMaterialConstantFloats = 8;
const fillExtrusionMaterialDataDrivenFloats = 16;

/// Floats per vertex in the replacement mesh stream, which appends a height
/// offset in meters to the material layout.
const fillExtrusionMeshConstantFloats = fillExtrusionMaterialConstantFloats + 1;
const fillExtrusionMeshDataDrivenFloats =
    fillExtrusionMaterialDataDrivenFloats + 1;

/// Floats per vertex in the material's application attribute stream.
const fillExtrusionCustomAttributeFloats = 8;

/// Spreads [values], holding [count] floats per vertex, to the eight-float
/// stride of the application attribute stream.
///
/// Missing or mis-sized [values] produce zeros.
Float32List packFillExtrusionCustomAttributes(
  Float32List? values, {
  required int vertexCount,
  required int count,
}) {
  final result = Float32List(vertexCount * fillExtrusionCustomAttributeFloats);
  if (values == null || count <= 0 || values.length != vertexCount * count) {
    return result;
  }
  final used = count > fillExtrusionCustomAttributeFloats
      ? fillExtrusionCustomAttributeFloats
      : count;
  for (var vertex = 0; vertex < vertexCount; vertex += 1) {
    result.setRange(
      vertex * fillExtrusionCustomAttributeFloats,
      vertex * fillExtrusionCustomAttributeFloats + used,
      values,
      vertex * count,
    );
  }

  return result;
}

/// Validates source mappings and returns each replacement vertex's part.
///
/// Unowned vertices use -1. A triangle cannot cross part boundaries because
/// visibility is evaluated for whole building parts.
Int32List fillExtrusionMeshPartIndices(
  FillExtrusionTile tile,
  FillExtrusionMesh mesh,
) {
  final sourceParts = Int32List(tile.vertexCount)
    ..fillRange(0, tile.vertexCount, -1);
  for (var index = 0; index < tile.parts.length; index += 1) {
    final part = tile.parts[index];
    final start = part.vertexOffset.clamp(0, tile.vertexCount);
    final end = (part.vertexOffset + part.vertexCount).clamp(
      start,
      tile.vertexCount,
    );
    sourceParts.fillRange(start, end, index);
  }
  final result = Int32List(mesh.vertexCount);
  for (var vertex = 0; vertex < mesh.vertexCount; vertex += 1) {
    final source = mesh.sourceVertexIndices[vertex];
    if (source >= tile.vertexCount) {
      throw ArgumentError(
        'Fill-extrusion mesh source vertex exceeds tile vertex count',
      );
    }
    result[vertex] = sourceParts[source];
  }
  final indices = mesh.indices;
  for (var index = 0; index < indices.length; index += 3) {
    final part = result[indices[index]];
    if (result[indices[index + 1]] != part ||
        result[indices[index + 2]] != part) {
      throw ArgumentError(
        'Fill-extrusion mesh triangles must belong to one part',
      );
    }
  }

  return result;
}

/// Filters replacement triangles by their source part's visibility.
///
/// Returns null when nothing is hidden. Unowned vertices remain visible.
Uint32List? visibleFillExtrusionMeshIndices(
  FillExtrusionMesh mesh,
  Int32List partIndices,
  List<bool> visible,
) {
  if (!visible.contains(false)) return null;
  final indices = mesh.indices;
  var hidden = 0;
  for (var index = 0; index < indices.length; index += 3) {
    final part = partIndices[indices[index]];
    if (part >= 0 && !visible[part]) hidden += 3;
  }
  if (hidden == 0) return null;
  final result = Uint32List(indices.length - hidden);
  var offset = 0;
  for (var index = 0; index < indices.length; index += 3) {
    final part = partIndices[indices[index]];
    if (part >= 0 && !visible[part]) continue;
    result.setRange(offset, offset + 3, indices, index);
    offset += 3;
  }

  return result;
}

/// Remaps the eight-float application attribute stream to replacement vertices.
Float32List packFillExtrusionMeshAttributes(
  Float32List attributes,
  Uint16List sourceVertexIndices,
) {
  final result = Float32List(
    sourceVertexIndices.length * fillExtrusionCustomAttributeFloats,
  );
  for (var vertex = 0; vertex < sourceVertexIndices.length; vertex += 1) {
    final offset = vertex * fillExtrusionCustomAttributeFloats;
    result.setRange(
      offset,
      offset + fillExtrusionCustomAttributeFloats,
      attributes,
      sourceVertexIndices[vertex] * fillExtrusionCustomAttributeFloats,
    );
  }

  return result;
}

/// A fill-extrusion tile decoded from MapLibre's exported vertex layout.
///
/// [vertexData] holds 12-byte constant or 44-byte data-driven vertices. Both
/// start with int16 position, uint16 packed fraction and top flag, uint16 ring
/// distance, and int16 normal scaled by 2^14. Data-driven vertices continue
/// with float base and height ranges.
final class DecodedFillExtrusionTile extends FillExtrusionTile {
  DecodedFillExtrusionTile({
    required this.key,
    required this.parts,
    required this.indices,
    required Uint8List vertexData,
    required int vertexStride,
    required this._heights,
  }) : _vertexData = vertexData.offsetInBytes % 4 == 0
           ? vertexData
           : Uint8List.fromList(vertexData),
       _vertexStride = vertexStride,
       vertexCount = vertexStride <= 0 ? 0 : vertexData.length ~/ vertexStride;

  final Uint8List _vertexData;
  final int _vertexStride;
  final FillExtrusionHeights _heights;

  @override
  final FillExtrusionTileKey key;
  @override
  final List<FillExtrusionPart> parts;
  @override
  final Uint16List indices;
  @override
  final int vertexCount;

  Float32List? _positions;
  Float32List? _normals;
  Float32List? _edgeDistances;
  Uint8List? _upperVertices;

  // Each array decodes on first use and on its own, so an application that
  // reads only positions pays for nothing else. Tiles leave and re-enter the
  // customizer's budget on zoom changes, so these run often.
  @override
  Float32List get positions => _positions ??= _decodePositions();
  @override
  Float32List get normals => _normals ??= _decodeNormals();
  @override
  Float32List get edgeDistances => _edgeDistances ??= _decodeEdgeDistances();
  @override
  Uint8List get upperVertices => _upperVertices ??= _decodeUpperVertices();

  /// Whether vertices carry per-feature base, height, and color ranges.
  bool get isDataDriven => _vertexStride >= fillExtrusionDataDrivenVertexStride;

  /// Bytes in owned source geometry and lazily decoded vertex arrays.
  ///
  /// This excludes feature metadata and objects retained by the application.
  int get retainedByteLength =>
      _vertexData.lengthInBytes +
      indices.lengthInBytes +
      (_positions?.lengthInBytes ?? 0) +
      (_normals?.lengthInBytes ?? 0) +
      (_edgeDistances?.lengthInBytes ?? 0) +
      (_upperVertices?.lengthInBytes ?? 0);

  /// Drops the decoded vertex arrays and keeps the source geometry.
  ///
  /// Each array is decoded again on its next use. Releasing them before a
  /// tile is dropped lets a byte budget keep more tiles across a zoom change.
  void releaseDecodedArrays() {
    _positions = null;
    _normals = null;
    _edgeDistances = null;
    _upperVertices = null;
  }

  /// Whether the evaluated heights match this snapshot.
  bool hasHeights(FillExtrusionHeights heights) =>
      _heights.base == heights.base &&
      _heights.height == heights.height &&
      _heights.baseT == heights.baseT &&
      _heights.heightT == heights.heightT;

  /// Whether [parts] group the same vertex ranges for outward normals.
  bool hasSamePartVertices(List<FillExtrusionPart> parts) {
    if (identical(this.parts, parts)) return true;
    if (this.parts.length != parts.length) return false;
    for (var index = 0; index < parts.length; index += 1) {
      if (this.parts[index].vertexOffset != parts[index].vertexOffset ||
          this.parts[index].vertexCount != parts[index].vertexCount) {
        return false;
      }
    }
    return true;
  }

  /// Creates an immutable metadata snapshot sharing the owned geometry bytes.
  ///
  /// Retained snapshots keep their original identifiers and evaluated heights.
  DecodedFillExtrusionTile withMetadata({
    required List<FillExtrusionPart> parts,
    required FillExtrusionHeights heights,
  }) => DecodedFillExtrusionTile(
    key: key,
    parts: parts,
    indices: indices,
    vertexData: _vertexData,
    vertexStride: _vertexStride,
    heights: heights,
  );

  /// Builds the vertex stream drawn by fill-extrusion materials.
  ///
  /// Each vertex holds x and y including the sub-unit fraction, the top flag,
  /// the ring distance, the outward normal, and the sign that turns it back
  /// into MapLibre's lighting normal. Data-driven tiles append the native
  /// base, height, and packed color ranges.
  Float32List materialVertices() {
    final floats = isDataDriven
        ? fillExtrusionMaterialDataDrivenFloats
        : fillExtrusionMaterialConstantFloats;
    final result = Float32List(vertexCount * floats);
    final data = ByteData.sublistView(_vertexData);
    final positions = this.positions;
    final normals = this.normals;
    final edgeDistances = this.edgeDistances;
    final upper = upperVertices;
    for (var vertex = 0; vertex < vertexCount; vertex += 1) {
      final output = vertex * floats;
      final source = vertex * _vertexStride;
      final outwardX = normals[vertex * 2];
      final outwardY = normals[vertex * 2 + 1];
      final rawX = data.getInt16(source + 8, Endian.little);
      final rawY = data.getInt16(source + 10, Endian.little);
      result[output] = positions[vertex * 3];
      result[output + 1] = positions[vertex * 3 + 1];
      result[output + 2] = upper[vertex].toDouble();
      result[output + 3] = edgeDistances[vertex];
      result[output + 4] = outwardX;
      result[output + 5] = outwardY;
      result[output + 6] = rawX * outwardX + rawY * outwardY < 0 ? -1 : 1;
      if (floats == fillExtrusionMaterialDataDrivenFloats) {
        for (var index = 0; index < 8; index += 1) {
          result[output + 8 + index] = data.getFloat32(
            source + 12 + index * 4,
            Endian.little,
          );
        }
      }
    }

    return result;
  }

  /// Packs replacement geometry with inherited native paint.
  ///
  /// Each vertex holds its tile position, height fraction, ring distance,
  /// outward normal, and lighting sign in the material layout. Data-driven
  /// tiles copy the source vertex's paint ranges, and the height offset in
  /// meters follows last.
  Float32List meshVertices(FillExtrusionMesh mesh) {
    final source = materialVertices();
    final floats = isDataDriven
        ? fillExtrusionMaterialDataDrivenFloats
        : fillExtrusionMaterialConstantFloats;
    final meshFloats = isDataDriven
        ? fillExtrusionMeshDataDrivenFloats
        : fillExtrusionMeshConstantFloats;
    final lightingSigns = Float32List(vertexCount)
      ..fillRange(0, vertexCount, 1);
    for (final part in parts) {
      final start = part.vertexOffset.clamp(0, vertexCount);
      final end = (part.vertexOffset + part.vertexCount).clamp(
        start,
        vertexCount,
      );
      for (var vertex = start; vertex < end; vertex += 1) {
        final offset = vertex * floats;
        if (source[offset + 4] == 0 && source[offset + 5] == 0) continue;
        lightingSigns.fillRange(start, end, source[offset + 6]);
        break;
      }
    }
    final result = Float32List(mesh.vertexCount * meshFloats);
    final positions = mesh.positions;
    final fractions = mesh.heightFractions;
    final offsets = mesh.heightOffsets;
    final normals = mesh.normals;
    final sources = mesh.sourceVertexIndices;
    final distances = mesh.edgeDistances;
    for (var vertex = 0; vertex < mesh.vertexCount; vertex += 1) {
      final output = vertex * meshFloats;
      final normal = vertex * 3;
      final mapped = sources[vertex];
      final input = mapped * floats;
      result[output] = positions[vertex * 2];
      result[output + 1] = positions[vertex * 2 + 1];
      result[output + 2] = fractions[vertex];
      result[output + 3] = distances?[vertex] ?? source[input + 3];
      result[output + 4] = normals[normal];
      result[output + 5] = normals[normal + 1];
      result[output + 6] = normals[normal + 2];
      result[output + 7] = lightingSigns[mapped];
      if (isDataDriven) {
        result.setRange(output + 8, output + floats, source, input + 8);
      }
      result[output + floats] = offsets?[vertex] ?? 0;
    }

    return result;
  }

  // Each vertex starts with 16-bit slots for x, y, packed fraction and top
  // flag, ring distance, normal x, and normal y. Data-driven vertices continue
  // with float base and height ranges at float slots 3 and 5. Typed views
  // replace per-field ByteData reads, which dominated re-adding a city's tiles.
  int get _slotStride => _vertexStride ~/ 2;

  Int16List get _shorts =>
      Int16List.sublistView(_vertexData, 0, vertexCount * _vertexStride);

  Uint16List get _unsignedShorts =>
      Uint16List.sublistView(_vertexData, 0, vertexCount * _vertexStride);

  Float32List _decodePositions() {
    final count = vertexCount;
    final positions = Float32List(count * 3);
    final shorts = _shorts;
    final unsignedShorts = _unsignedShorts;
    final stride = _slotStride;
    final heights = _heights;
    if (isDataDriven) {
      final floats = Float32List.sublistView(
        _vertexData,
        0,
        count * _vertexStride,
      );
      final floatStride = _vertexStride ~/ 4;
      for (var vertex = 0; vertex < count; vertex += 1) {
        final slot = vertex * stride;
        final packed = unsignedShorts[slot + 2];
        final isUpper = packed & 1;
        final range = vertex * floatStride + (isUpper == 1 ? 5 : 3);
        final low = floats[range];
        final z =
            low +
            (floats[range + 1] - low) *
                (isUpper == 1 ? heights.heightT : heights.baseT);
        final fraction = packed >> 1;
        final offset = vertex * 3;
        positions[offset] = shorts[slot] + (fraction >> 8) / 128;
        positions[offset + 1] = shorts[slot + 1] + (fraction & 255) / 128;
        positions[offset + 2] = z < 0 ? 0 : z;
      }
    } else {
      final base = heights.base < 0 ? 0.0 : heights.base;
      final height = heights.height < 0 ? 0.0 : heights.height;
      for (var vertex = 0; vertex < count; vertex += 1) {
        final slot = vertex * stride;
        final packed = unsignedShorts[slot + 2];
        final fraction = packed >> 1;
        final offset = vertex * 3;
        positions[offset] = shorts[slot] + (fraction >> 8) / 128;
        positions[offset + 1] = shorts[slot + 1] + (fraction & 255) / 128;
        positions[offset + 2] = packed & 1 == 1 ? height : base;
      }
    }
    return positions;
  }

  Float32List _decodeNormals() {
    final count = vertexCount;
    final normals = Float32List(count * 2);
    final shorts = _shorts;
    final stride = _slotStride;
    for (var vertex = 0; vertex < count; vertex += 1) {
      final slot = vertex * stride;
      normals[vertex * 2] = shorts[slot + 4] / 16384;
      normals[vertex * 2 + 1] = shorts[slot + 5] / 16384;
    }
    _orientNormalsOutward(positions, normals);

    return normals;
  }

  Float32List _decodeEdgeDistances() {
    final count = vertexCount;
    final distances = Float32List(count);
    final unsignedShorts = _unsignedShorts;
    final stride = _slotStride;
    for (var vertex = 0; vertex < count; vertex += 1) {
      distances[vertex] = unsignedShorts[vertex * stride + 3].toDouble();
    }
    return distances;
  }

  Uint8List _decodeUpperVertices() {
    final count = vertexCount;
    final upper = Uint8List(count);
    final unsignedShorts = _unsignedShorts;
    final stride = _slotStride;
    for (var vertex = 0; vertex < count; vertex += 1) {
      upper[vertex] = unsignedShorts[vertex * stride + 2] & 1;
    }
    return upper;
  }

  /// Makes wall normals point away from each part's material.
  ///
  /// MapLibre derives normals from ring order, so their direction depends on
  /// the source's winding. With cross(a, b) = a.x * b.y - a.y * b.x, every
  /// exported normal lies on the positive cross side of its edge. A part's
  /// material lies on that side when its rings enclose positive area. Holes
  /// wind opposite to outer rings and see the material on the same side, so
  /// one decision orients every wall of the part.
  void _orientNormalsOutward(Float32List positions, Float32List normals) {
    for (final part in parts) {
      final end = (part.vertexOffset + part.vertexCount).clamp(0, vertexCount);
      var crossSum = 0.0;
      var normalSum = 0.0;
      var vertex = part.vertexOffset;
      while (vertex + 3 < end) {
        final isWall = normals[vertex * 2] != 0 || normals[vertex * 2 + 1] != 0;
        if (!isWall) {
          vertex += 1;
          continue;
        }
        // A wall quad lists the edge's later point twice, then its earlier
        // point twice.
        final laterX = positions[vertex * 3];
        final laterY = positions[vertex * 3 + 1];
        final earlierX = positions[(vertex + 2) * 3];
        final earlierY = positions[(vertex + 2) * 3 + 1];
        // Twice the signed area contributed by the edge.
        crossSum += earlierX * laterY - laterX * earlierY;
        normalSum +=
            (laterX - earlierX) * normals[vertex * 2 + 1] -
            (laterY - earlierY) * normals[vertex * 2];
        vertex += 4;
      }
      final materialOnPositiveSide = crossSum > 0;
      final normalsOnPositiveSide = normalSum > 0;
      if (materialOnPositiveSide != normalsOnPositiveSide) continue;
      for (var index = part.vertexOffset * 2; index < end * 2; index += 1) {
        normals[index] = -normals[index];
      }
    }
  }
}
