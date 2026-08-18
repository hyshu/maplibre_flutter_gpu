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
  var _fallbackGeneration = 0;
  var _version = -1;
  var _placedLabels = const <LabelData>[];
  var _symbols = const <MapSymbol>[];
  SpriteAtlas? _cachedSpriteAtlas;

  /// Latest native placement snapshot before fade reconciliation.
  List<LabelData> get placedLabels => _placedLabels;

  /// Screen-positioned symbols for the overlay, as of the last
  /// [cacheScreenPositions] call.
  List<MapSymbol> get symbols => _symbols;

  /// Current mutable reconciliation entries.
  ///
  /// Callers must not modify the map or retain it across a [reset].
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
    _version = version;

    return true;
  }

  /// Projects every entry to screen space for the current camera.
  ///
  /// Text and icon anchors are projected separately because MapLibre places
  /// them independently. A symbol can have one without the other.
  void cacheScreenPositions(MaplibreBridge bridge, SpriteAtlas? spriteAtlas) {
    final coordinates = <({double latitude, double longitude})>[];
    for (final state in _entries.values) {
      final data = state.data;
      if (data.textPlaced) {
        coordinates.add((latitude: data.lat, longitude: data.lon));
      }
      if (data.iconPlaced) {
        coordinates.add((latitude: data.iconLat, longitude: data.iconLon));
      }
    }
    final projected = bridge.latLonsToScreen(coordinates);
    var projectionIndex = 0;
    final symbols = <MapSymbol>[];
    for (final entry in _entries.entries) {
      final state = entry.value;
      final data = state.data;
      final textAnchor = data.textPlaced ? projected[projectionIndex++] : null;
      final iconAnchor = data.iconPlaced ? projected[projectionIndex++] : null;
      symbols.add(
        MapSymbol(
          key: entry.key,
          data: data,
          textPos: textAnchor != null
              ? symbolScreenPosition(
                  textAnchor,
                  data.textOffsetX,
                  data.textOffsetY,
                )
              : null,
          iconPos: iconAnchor != null
              ? symbolScreenPosition(
                  iconAnchor,
                  data.iconOffsetX,
                  data.iconOffsetY,
                )
              : null,
          icon: data.icon.isEmpty ? null : spriteAtlas?[data.icon],
          spriteAtlas: spriteAtlas,
          visible: state.visible,
          fadeIn: !state.appeared,
        ),
      );
      // Only symbols in the current snapshot count as appeared. Entries kept
      // solely for fade-out do not.
      if (state.visible) state.appeared = true;
    }
    final ordered =
        <({MapSymbol symbol, int ordinal})>[
          for (var index = 0; index < symbols.length; index++)
            (symbol: symbols[index], ordinal: index),
        ]..sort((left, right) {
          final leftData = left.symbol.data;
          final rightData = right.symbol.data;
          var result = leftData.layerIndex.compareTo(rightData.layerIndex);
          if (result == 0) {
            result = leftData.renderGroup.compareTo(rightData.renderGroup);
          }
          if (result == 0) {
            result = leftData.renderOrder.compareTo(rightData.renderOrder);
          }
          return result == 0 ? left.ordinal.compareTo(right.ordinal) : result;
        });
    _symbols = [for (final entry in ordered) entry.symbol];
    _cachedSpriteAtlas = spriteAtlas;
  }

  /// Drops an entry once the overlay has finished fading it out.
  ///
  /// Ignores entries that became visible again while the fade was running.
  void onFadedOut(String key) {
    final entry = _entries[key];
    if (entry != null && !entry.visible) _entries.remove(key);
  }

  /// Forgets every placement and cached projection.
  ///
  /// The version resets to a value no native snapshot can hold, so the next
  /// [syncFromNative] always re-reads rather than matching a stale version
  /// from the previous style.
  void reset() {
    _entries.clear();
    _placedLabels = const <LabelData>[];
    _symbols = const <MapSymbol>[];
    _cachedSpriteAtlas = null;
    _version = -1;
    _fallbackGeneration = 0;
  }
}

/// Applies a symbol's layout offset to its projected anchor.
///
/// The offset is in logical pixels and must be added after projection, so it
/// does not rotate or scale with the camera.
Offset symbolScreenPosition(
  Offset projectedAnchor,
  double offsetX,
  double offsetY,
) => projectedAnchor + Offset(offsetX, offsetY);
