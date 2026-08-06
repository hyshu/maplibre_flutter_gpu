import 'dart:convert';

enum StyleLayerGroup { buildings3d, labels, symbols, roads, water }

/// Semantic layer groups derived from a MapLibre style document.
///
/// UI code can present familiar concepts instead of exposing style layer IDs.
class StyleLayerCatalog {
  StyleLayerCatalog._(this._layers);

  factory StyleLayerCatalog.fromStyle(String styleJson) {
    final style = jsonDecode(styleJson) as Map<String, dynamic>;
    final rawLayers = style['layers'] as List<dynamic>? ?? const [];
    final groups = <StyleLayerGroup, List<String>>{
      for (final group in StyleLayerGroup.values) group: <String>[],
    };

    for (final value in rawLayers) {
      if (value is! Map<String, dynamic>) continue;
      final id = value['id'] as String?;
      final type = value['type'] as String?;
      if (id == null || type == null) continue;

      final sourceLayer = value['source-layer'] as String? ?? '';
      final layout = value['layout'] as Map<String, dynamic>? ?? const {};
      final normalizedId = id.toLowerCase();
      final normalizedSource = sourceLayer.toLowerCase();

      if (type == 'fill-extrusion' &&
          (normalizedId.contains('building') ||
              normalizedSource.contains('building'))) {
        groups[StyleLayerGroup.buildings3d]!.add(id);
      }

      if ((type == 'line' || type == 'fill') &&
          (normalizedSource == 'transportation' ||
              normalizedId.startsWith('road_') ||
              normalizedId.startsWith('tunnel_') ||
              normalizedId.startsWith('bridge_'))) {
        groups[StyleLayerGroup.roads]!.add(id);
      }

      if ((type == 'line' || type == 'fill') &&
          (normalizedSource == 'water' ||
              normalizedSource == 'waterway' ||
              normalizedId == 'water')) {
        groups[StyleLayerGroup.water]!.add(id);
      }

      if (type != 'symbol') continue;
      final hasText = layout.containsKey('text-field');
      final hasIcon = layout.containsKey('icon-image');
      final isPoi =
          normalizedSource == 'poi' ||
          normalizedSource == 'aerodrome_label' ||
          normalizedId.contains('poi') ||
          normalizedId.contains('airport');
      final isRoadBadge =
          normalizedId.contains('shield') || normalizedId.contains('arrow');

      if (isPoi || isRoadBadge || (hasIcon && !hasText)) {
        groups[StyleLayerGroup.symbols]!.add(id);
      } else if (hasText) {
        groups[StyleLayerGroup.labels]!.add(id);
      }
    }
    return StyleLayerCatalog._({
      for (final entry in groups.entries)
        entry.key: List.unmodifiable(entry.value),
    });
  }

  final Map<StyleLayerGroup, List<String>> _layers;

  List<String> operator [](StyleLayerGroup group) => _layers[group]!;
}
