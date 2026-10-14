import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

/// Clears native building footprints within 24 meters of placed models.
///
/// Replace the placement list to update visibility. The renderer borrows the
/// notifier and must be disposed when it is no longer used by the map.
final class BuildingClearanceRenderer extends FillExtrusionRenderer {
  BuildingClearanceRenderer(this._buildings) : super(repaint: _buildings) {
    _buildings.addListener(_updateVisibility);
  }

  static const _radiusMeters = 24.0;
  final ValueListenable<List<LatLng>> _buildings;
  final _tiles = <FillExtrusionTileKey, _TileFootprints>{};

  @override
  bool isVisible(FillExtrusionPart part) =>
      !(_tiles[part.tile]?.hidden.contains((
            part.featureIndex,
            part.polygonIndex,
          )) ??
          false);

  @override
  void didAddTile(FillExtrusionTile tile) {
    final footprints = _TileFootprints(tile);
    _tiles[tile.key] = footprints;
    _updateTile(footprints);
  }

  @override
  void didRemoveTile(FillExtrusionTileKey key) => _tiles.remove(key);

  void _updateVisibility() {
    for (final tile in _tiles.values) {
      _updateTile(tile);
    }
  }

  void _updateTile(_TileFootprints footprints) {
    footprints.hidden.clear();
    if (_buildings.value.isEmpty) return;
    final tile = footprints.tile;
    final tileCount = math.pow(2, tile.key.z).toDouble();
    final worldWidth = tileCount * FillExtrusionTile.extent;
    final radius = _radiusMeters / tile.metersPerUnit;
    final placements = [
      for (final building in _buildings.value)
        _project(building, tile.key, tileCount),
    ];
    for (final bounds in footprints.bounds) {
      if (placements.any(
        (position) => bounds.intersects(position, radius, worldWidth),
      )) {
        footprints.hidden.add(bounds.part);
      }
    }
  }

  /// Removes the placement listener without disposing the shared notifier.
  void dispose() {
    _buildings.removeListener(_updateVisibility);
    _tiles.clear();
  }
}

math.Point<double> _project(
  LatLng position,
  FillExtrusionTileKey tile,
  double tileCount,
) {
  final latitude = position.latitude.clamp(-85.0511287798066, 85.0511287798066);
  final radians = latitude * math.pi / 180;
  final worldY =
      0.5 - math.log(math.tan(math.pi / 4 + radians / 2)) / (2 * math.pi);

  return math.Point(
    ((position.longitude + 180) / 360 * tileCount -
            tile.x -
            tile.wrap * tileCount) *
        FillExtrusionTile.extent,
    (worldY * tileCount - tile.y) * FillExtrusionTile.extent,
  );
}

final class _TileFootprints {
  _TileFootprints(this.tile);

  final FillExtrusionTile tile;
  final hidden = <(int, int)>{};

  // Geometry stays undecoded until the first model is placed.
  late final bounds = [
    for (final part in tile.parts)
      if (part.vertexCount > 0) _Footprint(part, tile.positions),
  ];
}

final class _Footprint {
  _Footprint(FillExtrusionPart source, Float32List positions)
    : part = (source.featureIndex, source.polygonIndex) {
    final end = (source.vertexOffset + source.vertexCount) * 3;
    for (var offset = source.vertexOffset * 3; offset < end; offset += 3) {
      minX = math.min(minX, positions[offset]);
      maxX = math.max(maxX, positions[offset]);
      minY = math.min(minY, positions[offset + 1]);
      maxY = math.max(maxY, positions[offset + 1]);
    }
  }

  final (int, int) part;
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;

  bool intersects(
    math.Point<double> position,
    double radius,
    double worldWidth,
  ) {
    // Match the nearest world copy, including footprints across the antimeridian.
    final x =
        position.x +
        (((minX + maxX) / 2 - position.x) / worldWidth).round() * worldWidth;
    final dx = x - x.clamp(minX, maxX);
    final dy = position.y - position.y.clamp(minY, maxY);

    return dx * dx + dy * dy <= radius * radius;
  }
}
