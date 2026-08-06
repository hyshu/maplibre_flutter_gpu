import 'label_data.dart';

const _invalidCrossTileId = 0xffffffff;

/// Mutable presentation state for one MapLibre-placed symbol.
class LabelReconcileEntry {
  /// Most recent placement data for the symbol.
  LabelData data;

  /// Whether the symbol exists in the latest placement snapshot.
  bool visible;

  /// Whether the symbol has already appeared in the overlay.
  bool appeared;

  /// Creates presentation state for [data].
  LabelReconcileEntry({
    required this.data,
    required this.visible,
    this.appeared = false,
  });
}

/// Reconciles a placement snapshot using MapLibre's cross-tile identity.
///
/// Symbols with a valid identity retain their presentation state within their
/// style layer. Symbols without one receive snapshot-specific identities.
/// [fallbackGeneration] must therefore differ between placement snapshots.
///
/// Updates [entries] in place. Missing entries remain for one snapshot to
/// support fade-out and are removed if the following snapshot does not revive
/// them.
void reconcileLabelEntries(
  Map<String, LabelReconcileEntry> entries,
  Iterable<LabelData> labels, {
  required int fallbackGeneration,
}) {
  assert(fallbackGeneration >= 0);

  // Record entries that were already missing before applying this snapshot.
  // Revived entries are retained and entries still missing are removed.
  final expiringKeys = entries.entries
      .where((entry) => !entry.value.visible)
      .map((entry) => entry.key)
      .toList(growable: false);
  final seen = <String>{};
  var fallbackOrdinal = 0;

  for (final label in labels) {
    final id = label.crossTileId;
    final hasStableId = id != 0 && id != _invalidCrossTileId;
    final String key;
    if (hasStableId) {
      key = '${label.layer}:$id';
    } else {
      // Valid identities never use a negative suffix. This keeps fallback keys
      // distinct even when a layer ID contains colons.
      key = '${label.layer}:-${fallbackGeneration + 1}-$fallbackOrdinal';
      fallbackOrdinal += 1;
    }

    final existing = entries[key];
    if (existing == null) {
      entries[key] = LabelReconcileEntry(data: label, visible: true);
    } else {
      // The latest placement is authoritative. Anchor positions and placement
      // flags are replaced rather than merged across snapshots.
      existing
        ..data = label
        ..visible = true;
    }
    seen.add(key);
  }

  for (final key in expiringKeys) {
    if (!seen.contains(key)) entries.remove(key);
  }
  for (final entry in entries.entries) {
    if (!seen.contains(entry.key)) entry.value.visible = false;
  }
}
