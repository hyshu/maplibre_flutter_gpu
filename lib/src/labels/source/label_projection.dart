part of '../label_source.dart';

extension _LabelProjection on MapLabelSource {
  void _cacheScreenPositions(MaplibreBridge bridge, SpriteAtlas? spriteAtlas) {
    _refreshOrdering();
    _refreshProjectionCoordinates();
    final projected = bridge.wrappedLatLonsToScreen(_projectionCoordinates);
    for (var index = 0; index < _activeLayerBucketCount; index++) {
      final bucket = _layerBuckets[index];
      for (final entry in bucket.entries) {
        final state = entry.state;
        final data = state.data;
        final textAnchor = entry.textProjectionIndex < 0
            ? null
            : projected[entry.textProjectionIndex];
        final iconAnchor = entry.iconProjectionIndex < 0
            ? null
            : projected[entry.iconProjectionIndex];
        entry.textPosition = _reuseScreenPosition(
          entry.textPosition,
          textAnchor,
          data.textOffsetX,
          data.textOffsetY,
        );
        entry.iconPosition =
            identical(iconAnchor, textAnchor) &&
                data.iconOffsetX == data.textOffsetX &&
                data.iconOffsetY == data.textOffsetY
            ? entry.textPosition
            : _reuseScreenPosition(
                entry.iconPosition,
                iconAnchor,
                data.iconOffsetX,
                data.iconOffsetY,
              );
        entry.fadeIn = !state.appeared;
        // Only symbols in the current snapshot count as appeared. Entries kept
        // solely for fade-out do not.
        if (state.visible) state.appeared = true;
      }
    }
    _symbolSnapshotsDirty = true;
    _cachedSpriteAtlas = spriteAtlas;
  }

  void _refreshProjectionCoordinates() {
    if (!_projectionCoordinatesDirty) return;
    _projectionCoordinatesDirty = false;
    // Equal text and icon anchors share one native projection slot.
    var projectionIndex = 0;
    var matches = true;
    for (final entry in _orderedEntries) {
      final data = entry.state.data;
      entry
        ..textProjectionIndex = -1
        ..iconProjectionIndex = -1;
      if (data.textPlaced) {
        entry.textProjectionIndex = projectionIndex;
        matches =
            _projectionCoordinateMatches(
              projectionIndex,
              data.lat,
              data.lon,
              data.tileWrap,
            ) &&
            matches;
        projectionIndex++;
      }
      if (!data.iconPlaced) continue;
      if (data.textPlaced &&
          data.iconLat == data.lat &&
          data.iconLon == data.lon) {
        entry.iconProjectionIndex = entry.textProjectionIndex;
      } else {
        entry.iconProjectionIndex = projectionIndex;
        matches =
            _projectionCoordinateMatches(
              projectionIndex,
              data.iconLat,
              data.iconLon,
              data.tileWrap,
            ) &&
            matches;
        projectionIndex++;
      }
    }
    matches = matches && projectionIndex == _projectionCoordinates.length;
    if (matches) return;

    _projectionCoordinates.clear();
    for (final entry in _orderedEntries) {
      final data = entry.state.data;
      if (data.textPlaced) {
        _projectionCoordinates.add((
          latitude: data.lat,
          longitude: data.lon,
          tileWrap: data.tileWrap,
        ));
      }
      if (data.iconPlaced &&
          (!data.textPlaced ||
              data.iconLat != data.lat ||
              data.iconLon != data.lon)) {
        _projectionCoordinates.add((
          latitude: data.iconLat,
          longitude: data.iconLon,
          tileWrap: data.tileWrap,
        ));
      }
    }
  }

  bool _projectionCoordinateMatches(
    int index,
    double latitude,
    double longitude,
    int tileWrap,
  ) {
    if (index >= _projectionCoordinates.length) return false;
    final coordinate = _projectionCoordinates[index];

    return coordinate.latitude == latitude &&
        coordinate.longitude == longitude &&
        coordinate.tileWrap == tileWrap;
  }
}

Offset? _reuseScreenPosition(
  Offset? previous,
  Offset? projectedAnchor,
  double offsetX,
  double offsetY,
) {
  if (projectedAnchor == null) return null;
  final x = projectedAnchor.dx + offsetX;
  final y = projectedAnchor.dy + offsetY;
  if (previous?.dx == x && previous?.dy == y) return previous;

  return Offset(x, y);
}
