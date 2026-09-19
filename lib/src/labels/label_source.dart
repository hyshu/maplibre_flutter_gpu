import 'dart:collection'
    show ListBase, UnmodifiableListView, UnmodifiableMapView;

import 'package:flutter/widgets.dart' show Offset;

import 'label_reconciler.dart';
import '../native/maplibre_ffi.dart';
import '../sprites/sprite_atlas.dart';
import '../widgets/symbols/map_symbol.dart';

/// @docImport '../widgets/symbols/symbol_overlay.dart';

part 'source/label_ordering.dart';
part 'source/label_projection.dart';
part 'source/symbol_views.dart';

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
  var _liveSymbolsByLayer = const <int, List<MapSymbol>>{};
  var _symbolSnapshotsDirty = false;
  SpriteAtlas? _cachedSpriteAtlas;

  /// Latest native placement snapshot before fade reconciliation.
  List<LabelData> get placedLabels => _placedLabels;

  /// Screen-positioned symbols for the overlay, as of the last
  /// [cacheScreenPositions] call.
  List<MapSymbol> get symbols {
    _refreshSymbolSnapshots();

    return _symbols;
  }

  /// Screen-positioned symbols indexed by MapLibre style layer.
  ///
  /// Both the map and each list are immutable snapshots. Symbols retain their
  /// native render order within each layer.
  Map<int, List<MapSymbol>> get symbolsByLayer {
    _refreshSymbolSnapshots();

    return _symbolsByLayer;
  }

  /// Returns the current screen-positioned symbols for [layerIndex].
  ///
  /// The returned list is an immutable snapshot. A missing layer returns an
  /// empty list.
  List<MapSymbol> symbolsForLayer(int layerIndex) {
    _refreshSymbolSnapshots();

    return _symbolsByLayer[layerIndex] ?? const [];
  }

  /// Returns live positions without materializing a new symbol snapshot.
  ///
  /// The view is consumed by [MapSymbolOverlay] during position-only updates.
  /// Callers that retain symbols must use [symbolsForLayer] instead.
  List<MapSymbol> liveSymbolsForLayer(int layerIndex) =>
      _liveSymbolsByLayer[layerIndex] ?? const [];

  /// Style layer indices represented by the current live symbol views.
  Iterable<int> get symbolLayerIndices => _liveSymbolsByLayer.keys;

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
  void cacheScreenPositions(MaplibreBridge bridge, SpriteAtlas? spriteAtlas) =>
      _cacheScreenPositions(bridge, spriteAtlas);

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
    _liveSymbolsByLayer = const {};
    _symbolSnapshotsDirty = false;
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
}
