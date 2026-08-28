import 'dart:collection'
    show ListBase, UnmodifiableListView, UnmodifiableMapView;

import 'package:flutter/widgets.dart' show Offset;

import 'label_reconciler.dart';
import '../native/maplibre_ffi.dart';
import '../sprites/sprite_atlas.dart';
import '../widgets/symbol_overlay.dart';

/// Maintains native symbol placements for the Flutter overlay.
///
/// Entries persist across snapshots so removed symbols can fade out. Current
/// placements are projected to screen positions for the active camera.
class MapLabelSource {
  final _entries = <String, LabelReconcileEntry>{};
  final _orderedEntries = <_OrderedLabelEntry>[];
  final _orderedEntriesByKey = <String, _OrderedLabelEntry>{};
  final _layerBuckets = <_LabelLayerBucket>[];
  final _projectionCoordinates =
      <({double latitude, double longitude, int tileWrap})>[];
  var _activeLayerBucketCount = 0;
  var _nextStableOrdinal = 0;
  var _orderingDirty = true;
  var _projectionCoordinatesDirty = true;
  var _fallbackGeneration = 0;
  var _version = -1;
  var _placedLabels = const <LabelData>[];
  var _symbols = const <MapSymbol>[];
  var _symbolsByLayer = const <int, List<MapSymbol>>{};
  SpriteAtlas? _cachedSpriteAtlas;

  /// Latest native placement snapshot before fade reconciliation.
  List<LabelData> get placedLabels => _placedLabels;

  /// Screen-positioned symbols for the overlay, as of the last
  /// [cacheScreenPositions] call.
  List<MapSymbol> get symbols => _symbols;

  /// Screen-positioned symbols indexed by MapLibre style layer.
  ///
  /// Both the map and each list are immutable snapshots. Symbols retain their
  /// native render order within each layer.
  Map<int, List<MapSymbol>> get symbolsByLayer => _symbolsByLayer;

  /// Returns the current screen-positioned symbols for [layerIndex].
  ///
  /// The returned list is an immutable snapshot. A missing layer returns an
  /// empty list.
  List<MapSymbol> symbolsForLayer(int layerIndex) =>
      _symbolsByLayer[layerIndex] ?? const [];

  /// Current mutable reconciliation entries.
  ///
  /// Callers must not modify the map or its entries, or retain either across a
  /// [reset].
  Map<String, LabelReconcileEntry> get entries => _entries;

  /// Whether [spriteAtlas] differs from the atlas used for the last projection.
  bool hasDifferentSpriteAtlas(SpriteAtlas? spriteAtlas) =>
      !identical(_cachedSpriteAtlas, spriteAtlas);

  /// Pulls a placement snapshot when its native version changes.
  ///
  /// Returns whether a new snapshot was read.
  bool syncFromNative(MaplibreBridge bridge) {
    final version = bridge.getLabelsVersion();
    // Compare for inequality because reset uses a sentinel value to force the
    // next snapshot to be read.
    if (_version == version) return false;
    final placedLabels = List<LabelData>.unmodifiable(bridge.getPlacedLabels());
    _placedLabels = placedLabels;
    reconcileLabelEntries(
      _entries,
      placedLabels,
      fallbackGeneration: _fallbackGeneration++,
    );
    _orderingDirty = true;
    _projectionCoordinatesDirty = true;
    _version = version;

    return true;
  }

  /// Projects every entry to screen space for the current camera.
  ///
  /// Text and icon anchors are projected separately because MapLibre places
  /// them independently. A symbol can have one without the other.
  void cacheScreenPositions(MaplibreBridge bridge, SpriteAtlas? spriteAtlas) {
    _refreshOrdering();
    _refreshProjectionCoordinates();
    final projected = bridge.wrappedLatLonsToScreen(_projectionCoordinates);
    final orderedSymbols = <MapSymbol>[];
    for (var index = 0; index < _activeLayerBucketCount; index++) {
      final bucket = _layerBuckets[index];
      bucket.symbolStart = orderedSymbols.length;
      for (final entry in bucket.entries) {
        final state = entry.state;
        final data = state.data;
        final textAnchor = entry.textProjectionIndex < 0
            ? null
            : projected[entry.textProjectionIndex];
        final iconAnchor = entry.iconProjectionIndex < 0
            ? null
            : projected[entry.iconProjectionIndex];
        final textPosition = _reuseScreenPosition(
          entry.symbol?.textPos,
          textAnchor,
          data.textOffsetX,
          data.textOffsetY,
        );
        final iconPosition =
            identical(iconAnchor, textAnchor) &&
                data.iconOffsetX == data.textOffsetX &&
                data.iconOffsetY == data.textOffsetY
            ? textPosition
            : _reuseScreenPosition(
                entry.symbol?.iconPos,
                iconAnchor,
                data.iconOffsetX,
                data.iconOffsetY,
              );
        orderedSymbols.add(
          entry.resolveSymbol(
            spriteAtlas: spriteAtlas,
            textPosition: textPosition,
            iconPosition: iconPosition,
            fadeIn: !state.appeared,
          ),
        );
        // Only symbols in the current snapshot count as appeared. Entries kept
        // solely for fade-out do not.
        if (state.visible) state.appeared = true;
      }
      bucket.symbolEnd = orderedSymbols.length;
    }
    final symbolSnapshot = UnmodifiableListView(orderedSymbols);
    final orderedByLayer = <int, List<MapSymbol>>{};
    for (var index = 0; index < _activeLayerBucketCount; index++) {
      final bucket = _layerBuckets[index];
      orderedByLayer[bucket.layerIndex] = _SymbolRangeList(
        symbolSnapshot,
        bucket.symbolStart,
        bucket.symbolEnd,
      );
    }
    _symbolsByLayer = UnmodifiableMapView(orderedByLayer);
    _symbols = symbolSnapshot;
    _cachedSpriteAtlas = spriteAtlas;
  }

  /// Drops an entry once the overlay has finished fading it out.
  ///
  /// Ignores entries that became visible again while the fade was running.
  void onFadedOut(String key) {
    final entry = _entries[key];
    if (entry != null && !entry.visible) {
      _entries.remove(key);
      _orderingDirty = true;
      _projectionCoordinatesDirty = true;
    }
  }

  /// Forgets every placement and cached projection.
  ///
  /// The version resets to a value no native snapshot can hold, so the next
  /// [syncFromNative] always re-reads rather than matching a stale version
  /// from the previous style.
  void reset() {
    _entries.clear();
    _placedLabels = const [];
    _symbols = const [];
    _symbolsByLayer = const {};
    _cachedSpriteAtlas = null;
    _orderedEntries.clear();
    _orderedEntriesByKey.clear();
    for (final bucket in _layerBuckets) {
      bucket.entries.clear();
    }
    _layerBuckets.clear();
    _projectionCoordinates.clear();
    _activeLayerBucketCount = 0;
    _nextStableOrdinal = 0;
    _orderingDirty = true;
    _projectionCoordinatesDirty = true;
    _version = -1;
    _fallbackGeneration = 0;
  }

  void _refreshOrdering() {
    if (!_orderingDirty) return;
    _orderingDirty = false;
    var membershipChanged = false;
    _orderedEntries.removeWhere((entry) {
      final removes = !identical(_entries[entry.key], entry.state);
      if (removes) {
        _orderedEntriesByKey.remove(entry.key);
        membershipChanged = true;
      }

      return removes;
    });
    for (final mapEntry in _entries.entries) {
      final cached = _orderedEntriesByKey[mapEntry.key];
      if (cached != null && identical(cached.state, mapEntry.value)) continue;
      final entry = _OrderedLabelEntry(
        key: mapEntry.key,
        state: mapEntry.value,
        stableOrdinal: _nextStableOrdinal++,
      );
      _orderedEntriesByKey[mapEntry.key] = entry;
      _orderedEntries.add(entry);
      membershipChanged = true;
    }
    // Stable ordinals preserve insertion order when native paint ranks tie.
    if (membershipChanged || !_entriesAreOrdered()) {
      _orderedEntries.sort(_compareOrderedEntries);
    }
    _rebuildLayerBuckets();
  }

  bool _entriesAreOrdered() {
    for (var index = 1; index < _orderedEntries.length; index++) {
      if (_compareOrderedEntries(
            _orderedEntries[index - 1],
            _orderedEntries[index],
          ) >
          0) {
        return false;
      }
    }

    return true;
  }

  void _rebuildLayerBuckets() {
    _activeLayerBucketCount = 0;
    int? previousLayerIndex;
    for (final entry in _orderedEntries) {
      final layerIndex = entry.state.data.layerIndex;
      if (previousLayerIndex != layerIndex) {
        final bucket = _activeLayerBucketCount == _layerBuckets.length
            ? _LabelLayerBucket()
            : _layerBuckets[_activeLayerBucketCount];
        if (_activeLayerBucketCount == _layerBuckets.length) {
          _layerBuckets.add(bucket);
        }
        bucket
          ..layerIndex = layerIndex
          ..entries.clear();
        _activeLayerBucketCount++;
        previousLayerIndex = layerIndex;
      }
      _layerBuckets[_activeLayerBucketCount - 1].entries.add(entry);
    }
    for (
      var index = _activeLayerBucketCount;
      index < _layerBuckets.length;
      index++
    ) {
      _layerBuckets[index].entries.clear();
    }
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

int _compareOrderedEntries(_OrderedLabelEntry left, _OrderedLabelEntry right) {
  final leftData = left.state.data;
  final rightData = right.state.data;
  var result = leftData.layerIndex.compareTo(rightData.layerIndex);
  if (result == 0) {
    result = leftData.renderGroup.compareTo(rightData.renderGroup);
  }
  if (result == 0) {
    result = leftData.renderOrder.compareTo(rightData.renderOrder);
  }

  return result == 0
      ? left.stableOrdinal.compareTo(right.stableOrdinal)
      : result;
}

class _OrderedLabelEntry({
  required final String key,
  required final LabelReconcileEntry state,
  required final int stableOrdinal,
}) {
  int textProjectionIndex = -1;
  int iconProjectionIndex = -1;
  SpriteAtlas? _iconAtlas;
  String? _iconName;
  SpriteIcon? _icon;
  var _hasResolvedIcon = false;
  MapSymbol? symbol;

  SpriteIcon? resolveIcon(SpriteAtlas? atlas) {
    final name = state.data.icon;
    if (_hasResolvedIcon && identical(_iconAtlas, atlas) && _iconName == name) {
      return _icon;
    }
    _hasResolvedIcon = true;
    _iconAtlas = atlas;
    _iconName = name;
    _icon = name.isEmpty ? null : atlas?[name];

    return _icon;
  }

  MapSymbol resolveSymbol({
    required SpriteAtlas? spriteAtlas,
    required Offset? textPosition,
    required Offset? iconPosition,
    required bool fadeIn,
  }) {
    final data = state.data;
    final icon = resolveIcon(spriteAtlas);
    final cached = symbol;
    if (cached != null &&
        identical(cached.data, data) &&
        cached.textPos == textPosition &&
        cached.iconPos == iconPosition &&
        identical(cached.icon, icon) &&
        identical(cached.spriteAtlas, spriteAtlas) &&
        cached.visible == state.visible &&
        cached.fadeIn == fadeIn) {
      return cached;
    }
    final next = MapSymbol(
      key: key,
      data: data,
      textPos: textPosition,
      iconPos: iconPosition,
      icon: icon,
      spriteAtlas: spriteAtlas,
      visible: state.visible,
      fadeIn: fadeIn,
    );
    symbol = next;

    return next;
  }
}

class _LabelLayerBucket {
  int layerIndex = 0;
  final List<_OrderedLabelEntry> entries = [];
  int symbolStart = 0;
  int symbolEnd = 0;
}

class _SymbolRangeList(
  final List<MapSymbol> _source,
  final int _start,
  final int _end,
) extends ListBase<MapSymbol> {
  @override
  int get length => _end - _start;

  @override
  set length(int value) => throw UnsupportedError('immutable symbol snapshot');

  @override
  MapSymbol operator [](int index) {
    RangeError.checkValidIndex(index, this);

    return _source[_start + index];
  }

  @override
  void operator []=(int index, MapSymbol value) =>
      throw UnsupportedError('immutable symbol snapshot');
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

/// Applies a symbol's layout offset to its projected anchor.
///
/// The offset is in logical pixels and must be added after projection, so it
/// does not rotate or scale with the camera.
Offset symbolScreenPosition(
  Offset projectedAnchor,
  double offsetX,
  double offsetY,
) => Offset(projectedAnchor.dx + offsetX, projectedAnchor.dy + offsetY);
