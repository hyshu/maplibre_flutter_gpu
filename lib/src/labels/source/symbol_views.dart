part of '../label_source.dart';

extension _LabelSnapshots on MapLabelSource {
  void _refreshSymbolSnapshots() {
    if (!_symbolSnapshotsDirty) return;
    final orderedSymbols = <MapSymbol>[];
    for (var index = 0; index < _activeLayerBucketCount; index++) {
      final bucket = _layerBuckets[index];
      bucket.symbolStart = orderedSymbols.length;
      for (final entry in bucket.entries) {
        orderedSymbols.add(entry.resolveSymbol(_cachedSpriteAtlas));
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
    _symbolSnapshotsDirty = false;
  }
}

class _OrderedLabelEntry({
  required final String key,
  required final LabelReconcileEntry state,
  required final int stableOrdinal,
}) {
  int textProjectionIndex = -1;
  int iconProjectionIndex = -1;
  Offset? textPosition;
  Offset? iconPosition;
  bool fadeIn = true;
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

  MapSymbol resolveSymbol(SpriteAtlas? spriteAtlas) {
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

class _LiveSymbolLayerList(
  final MapLabelSource _source,
  final int _layerIndex,
  final List<_OrderedLabelEntry> _entries,
) extends ListBase<MapSymbol> implements SymbolPositionList {
  final Map<String, _OrderedLabelEntry> _entriesByKey = {
    for (final entry in _entries) entry.key: entry,
  };

  @override
  int get length => _entries.length;

  @override
  set length(int value) => throw UnsupportedError('immutable symbol view');

  @override
  MapSymbol operator [](int index) {
    RangeError.checkValidIndex(index, this);

    return _entries[index].resolveSymbol(_source._cachedSpriteAtlas);
  }

  @override
  void operator []=(int index, MapSymbol value) =>
      throw UnsupportedError('immutable symbol view');

  @override
  Offset? anchorFor(String key, {required bool icon}) {
    final entry = _entriesByKey[key];
    if (entry == null || entry.state.data.layerIndex != _layerIndex) {
      return null;
    }

    return icon ? entry.iconPosition : entry.textPosition;
  }

  @override
  MapSymbol positioned(MapSymbol symbol) {
    final entry = _entriesByKey[symbol.key];
    if (entry == null || entry.state.data.layerIndex != _layerIndex) {
      return symbol;
    }

    return entry.resolveSymbol(_source._cachedSpriteAtlas);
  }
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
