part of '../label_source.dart';

extension _LabelOrdering on MapLabelSource {
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
    _liveSymbolsByLayer = UnmodifiableMapView({
      for (var index = 0; index < _activeLayerBucketCount; index++)
        _layerBuckets[index].layerIndex: _LiveSymbolLayerList(
          this,
          _layerBuckets[index].layerIndex,
          List.unmodifiable(_layerBuckets[index].entries),
        ),
    });
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

class _LabelLayerBucket {
  int layerIndex = 0;
  final List<_OrderedLabelEntry> entries = [];
  int symbolStart = 0;
  int symbolEnd = 0;
}
