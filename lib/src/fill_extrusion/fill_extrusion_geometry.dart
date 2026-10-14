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
  }) : _vertexData = vertexData,
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

  @override
  Float32List get positions => _positions ?? (_decode()._positions!);
  @override
  Float32List get normals => _normals ?? (_decode()._normals!);
  @override
  Float32List get edgeDistances =>
      _edgeDistances ?? (_decode()._edgeDistances!);
  @override
  Uint8List get upperVertices => _upperVertices ?? (_decode()._upperVertices!);

  /// Whether vertices carry per-feature base, height, and color ranges.
  bool get isDataDriven => _vertexStride >= fillExtrusionDataDrivenVertexStride;

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

  DecodedFillExtrusionTile _decode() {
    final count = vertexCount;
    final positions = Float32List(count * 3);
    final normals = Float32List(count * 2);
    final edgeDistances = Float32List(count);
    final upper = Uint8List(count);
    final data = ByteData.sublistView(_vertexData);
    final dataDriven = _vertexStride >= fillExtrusionDataDrivenVertexStride;
    final heights = _heights;
    for (var vertex = 0; vertex < count; vertex += 1) {
      final offset = vertex * _vertexStride;
      final packed = data.getUint16(offset + 4, Endian.little);
      final fraction = packed >> 1;
      final isUpper = packed & 1;
      double z;
      if (dataDriven) {
        final rangeOffset = offset + (isUpper == 1 ? 20 : 12);
        final low = data.getFloat32(rangeOffset, Endian.little);
        final high = data.getFloat32(rangeOffset + 4, Endian.little);
        final t = isUpper == 1 ? heights.heightT : heights.baseT;
        z = low + (high - low) * t;
      } else {
        z = isUpper == 1 ? heights.height : heights.base;
      }
      positions[vertex * 3] =
          data.getInt16(offset, Endian.little) + (fraction >> 8) / 128;
      positions[vertex * 3 + 1] =
          data.getInt16(offset + 2, Endian.little) + (fraction & 255) / 128;
      positions[vertex * 3 + 2] = z < 0 ? 0 : z;
      edgeDistances[vertex] = data
          .getUint16(offset + 6, Endian.little)
          .toDouble();
      normals[vertex * 2] = data.getInt16(offset + 8, Endian.little) / 16384;
      normals[vertex * 2 + 1] =
          data.getInt16(offset + 10, Endian.little) / 16384;
      upper[vertex] = isUpper;
    }
    _orientNormalsOutward(positions, normals);
    _positions = positions;
    _normals = normals;
    _edgeDistances = edgeDistances;
    _upperVertices = upper;

    return this;
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
