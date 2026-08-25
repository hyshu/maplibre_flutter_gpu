import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/labels/label_data.dart';
import 'package:maplibre_flutter_gpu/src/labels/label_reconciler.dart';

LabelData _label({
  required int crossTileId,
  int tileWrap = 0,
  String layer = 'labels',
  String text = 'label',
  String icon = '',
  double lat = 1,
  double lon = 2,
  double iconLat = 3,
  double iconLon = 4,
  bool textPlaced = true,
  bool iconPlaced = false,
}) => LabelData(
  crossTileId: crossTileId,
  tileWrap: tileWrap,
  lat: lat,
  lon: lon,
  iconLat: iconLat,
  iconLon: iconLon,
  fontSize: 12,
  textR: 0,
  textG: 0,
  textB: 0,
  textA: 1,
  haloR: 0,
  haloG: 0,
  haloB: 0,
  haloA: 0,
  haloWidth: 0,
  textPlaced: textPlaced,
  iconPlaced: iconPlaced,
  text: text,
  layer: layer,
  icon: icon,
);

void main() {
  test('stable cross-tile identity exact-upserts the latest placement', () {
    final entries = <String, LabelReconcileEntry>{};
    final first = _label(crossTileId: 42, text: 'old', lat: 10, lon: 20);

    reconcileLabelEntries(entries, [first], fallbackGeneration: 0);

    expect(entries.keys, ['labels:42:0']);
    final entry = entries['labels:42:0']!..appeared = true;
    final latest = _label(
      crossTileId: 42,
      text: 'new',
      icon: 'marker',
      lat: 30,
      lon: 40,
      iconLat: 50,
      iconLon: 60,
      textPlaced: false,
      iconPlaced: true,
    );

    reconcileLabelEntries(entries, [latest], fallbackGeneration: 1);

    expect(identical(entries['labels:42:0'], entry), isTrue);
    expect(identical(entry.data, latest), isTrue);
    expect(entry.data.lat, 30);
    expect(entry.data.iconLat, 50);
    expect(entry.data.textPlaced, isFalse);
    expect(entry.data.iconPlaced, isTrue);
    expect(entry.appeared, isTrue);
    expect(entry.visible, isTrue);
  });

  test('layer scopes IDs and invalid IDs never collide or get reused', () {
    final entries = <String, LabelReconcileEntry>{};
    final firstSnapshot = [
      _label(crossTileId: 7, layer: 'roads'),
      _label(crossTileId: 7, layer: 'places'),
      _label(crossTileId: 0, layer: 'roads', text: 'zero-a'),
      _label(crossTileId: 0, layer: 'roads', text: 'zero-b'),
      _label(crossTileId: 0xffffffff, layer: 'roads', text: 'max-a'),
      _label(crossTileId: 0xffffffff, layer: 'roads', text: 'max-b'),
    ];

    reconcileLabelEntries(entries, firstSnapshot, fallbackGeneration: 3);

    expect(entries, containsPair('roads:7:0', isA<LabelReconcileEntry>()));
    expect(entries, containsPair('places:7:0', isA<LabelReconcileEntry>()));
    final firstFallbackKeys = entries.keys
        .where((key) => key != 'roads:7:0' && key != 'places:7:0')
        .toSet();
    expect(firstFallbackKeys, hasLength(4));
    expect(firstFallbackKeys.every((key) => key.startsWith('roads:-')), isTrue);

    reconcileLabelEntries(entries, [
      _label(crossTileId: 0, layer: 'roads', text: 'next'),
    ], fallbackGeneration: 4);

    final visibleKeys = entries.entries
        .where((entry) => entry.value.visible)
        .map((entry) => entry.key)
        .toSet();
    expect(visibleKeys, hasLength(1));
    expect(firstFallbackKeys.intersection(visibleKeys), isEmpty);
    expect(firstFallbackKeys.every((key) => !entries[key]!.visible), isTrue);
    expect(entries['roads:7:0']!.visible, isFalse);
    expect(entries['places:7:0']!.visible, isFalse);
  });

  test('missing snapshots get one fade grace period without accumulating', () {
    final entries = <String, LabelReconcileEntry>{};
    var maxEntryCount = 0;

    for (var generation = 0; generation < 1000; generation++) {
      reconcileLabelEntries(entries, [
        _label(crossTileId: generation + 1),
      ], fallbackGeneration: generation);
      if (entries.length > maxEntryCount) maxEntryCount = entries.length;
    }

    expect(maxEntryCount, 2);
    expect(entries, hasLength(2));
    expect(entries['labels:999:0']!.visible, isFalse);
    expect(entries['labels:1000:0']!.visible, isTrue);

    reconcileLabelEntries(entries, const [], fallbackGeneration: 1000);
    expect(entries.keys, ['labels:1000:0']);
    expect(entries['labels:1000:0']!.visible, isFalse);

    reconcileLabelEntries(entries, const [], fallbackGeneration: 1001);
    expect(entries, isEmpty);
  });

  test('a symbol revived during its grace snapshot preserves its state', () {
    final entries = <String, LabelReconcileEntry>{};
    reconcileLabelEntries(entries, [
      _label(crossTileId: 1),
    ], fallbackGeneration: 0);
    final original = entries['labels:1:0']!..appeared = true;

    reconcileLabelEntries(entries, [
      _label(crossTileId: 2),
    ], fallbackGeneration: 1);
    expect(original.visible, isFalse);

    reconcileLabelEntries(entries, [
      _label(crossTileId: 1, text: 'revived'),
    ], fallbackGeneration: 2);

    expect(identical(entries['labels:1:0'], original), isTrue);
    expect(original.visible, isTrue);
    expect(original.appeared, isTrue);
    expect(original.data.text, 'revived');
    expect(entries['labels:2:0']!.visible, isFalse);
  });

  test('world copies keep separate stable identities', () {
    final entries = <String, LabelReconcileEntry>{};

    reconcileLabelEntries(entries, [
      _label(crossTileId: 7, tileWrap: -1),
      _label(crossTileId: 7),
      _label(crossTileId: 7, tileWrap: 1),
    ], fallbackGeneration: 0);

    expect(
      entries.keys,
      containsAll(['labels:7:-1', 'labels:7:0', 'labels:7:1']),
    );
    expect(entries, hasLength(3));
  });
}
