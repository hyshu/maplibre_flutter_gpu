import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/labels/label_data.dart';
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart'
    hide LabelData;
import 'package:maplibre_flutter_gpu/src/labels/label_source.dart';
import 'package:maplibre_flutter_gpu/src/sprites/sprite_atlas.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbol_overlay.dart'
    show SymbolPositionList;

class _FakeSpriteAtlas implements SpriteAtlas {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LabelData _label({
  required String text,
  String layer = 'places',
  int crossTileId = 0,
  int tileWrap = 0,
  bool textPlaced = true,
  bool iconPlaced = false,
  String icon = '',
  double lat = 35,
  double lon = 139,
  double iconLat = 36,
  double iconLon = 140,
  int layerIndex = 0,
  int renderGroup = 0,
  int renderOrder = 0,
}) => .new(
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
  haloR: 1,
  haloG: 1,
  haloB: 1,
  haloA: 1,
  haloWidth: 1,
  textPlaced: textPlaced,
  iconPlaced: iconPlaced,
  icon: icon,
  text: text,
  layer: layer,
  layerIndex: layerIndex,
  renderGroup: renderGroup,
  renderOrder: renderOrder,
);

/// Serves a scripted sequence of placement snapshots.
class _FakeBridge implements MaplibreBridge {
  new(this.version, this.labels);

  int version;
  List<LabelData> labels;
  var projectionOffset = Offset.zero;
  var getLabelsCalls = 0;
  var batchProjectionCalls = 0;
  final List<List<({double latitude, double longitude, int tileWrap})>>
  projectionInputs = [];
  final List<int> projectionBatchSizes = [];
  final List<({double lat, double lon})> projected = [];

  @override
  int getLabelsVersion() => version;

  @override
  List<LabelData> getPlacedLabels() {
    getLabelsCalls++;

    return labels;
  }

  @override
  Offset latLonToScreen(double lat, double lon) {
    projected.add((lat: lat, lon: lon));

    // Encodes the input so a test can tell which anchor was projected.
    return Offset(lon, lat) + projectionOffset;
  }

  @override
  List<Offset> latLonsToScreen(
    List<({double latitude, double longitude})> coordinates,
  ) {
    return wrappedLatLonsToScreen([
      for (final coordinate in coordinates)
        (
          latitude: coordinate.latitude,
          longitude: coordinate.longitude,
          tileWrap: 0,
        ),
    ]);
  }

  @override
  List<Offset> wrappedLatLonsToScreen(
    List<({double latitude, double longitude, int tileWrap})> coordinates,
  ) {
    batchProjectionCalls++;
    projectionInputs.add(coordinates);
    projectionBatchSizes.add(coordinates.length);

    return [
      for (final coordinate in coordinates)
        latLonToScreen(
          coordinate.latitude,
          coordinate.longitude + coordinate.tileWrap * 360,
        ),
    ];
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected ${invocation.memberName}');
}

void main() {
  group('snapshot versioning', () {
    test('skips a snapshot native has not republished', () {
      // Reprojecting an unchanged snapshot every frame would be pure waste,
      // and re-reconciling it would advance the fallback generation.
      final bridge = _FakeBridge(7, [_label(text: 'A')]);
      final source = MapLabelSource();

      expect(source.syncFromNative(bridge), isTrue);
      expect(source.syncFromNative(bridge), isFalse);
      expect(bridge.getLabelsCalls, 1);
    });

    test('a stable cross-tile id updates its entry in place', () {
      final bridge = _FakeBridge(1, [_label(text: 'A', crossTileId: 42)]);
      final source = MapLabelSource();
      expect(source.syncFromNative(bridge), isTrue);

      bridge
        ..version = 2
        ..labels = [_label(text: 'B', crossTileId: 42)];

      expect(source.syncFromNative(bridge), isTrue);
      expect(source.entries.values.single.data.text, 'B');
    });

    test('caches only the latest raw native placement snapshot', () {
      final bridge = _FakeBridge(1, [_label(text: 'A', crossTileId: 1)]);
      final source = MapLabelSource()..syncFromNative(bridge);

      bridge
        ..version = 2
        ..labels = [_label(text: 'B', crossTileId: 2)];
      source.syncFromNative(bridge);

      expect(source.placedLabels.map((label) => label.text), ['B']);
      expect(
        source.entries.values.map((entry) => entry.data.text),
        containsAll(['A', 'B']),
        reason: 'fade reconciliation may retain A, raw snapshot must not',
      );
      expect(
        () => source.placedLabels.add(_label(text: 'C')),
        throwsUnsupportedError,
      );
    });

    test('an invalid cross-tile id never reuses a fading entry', () {
      // MapLibre reserves 0 and UINT32_MAX as "no identity". Two such symbols
      // are not the same symbol, so matching them across snapshots would let
      // one label inherit another's fade state and anchor.
      for (final invalid in [0, 0xffffffff]) {
        final bridge = _FakeBridge(1, [
          _label(text: 'A', crossTileId: invalid),
        ]);
        final source = MapLabelSource()..syncFromNative(bridge);
        final firstKey = source.entries.keys.single;

        bridge
          ..version = 2
          ..labels = [_label(text: 'B', crossTileId: invalid)];
        source.syncFromNative(bridge);

        // The old entry lingers one snapshot so it can fade, but it must not
        // have been *reused*: the new symbol gets its own key, and the old one
        // is now invisible rather than carrying the new text.
        expect(
          source.entries[firstKey]?.visible,
          isFalse,
          reason: 'id $invalid: previous entry should be fading, not reused',
        );
        expect(source.entries[firstKey]?.data.text, 'A');
        final live = source.entries.entries.where((e) => e.value.visible);
        expect(live, hasLength(1));
        expect(live.single.key, isNot(firstKey));
        expect(live.single.value.data.text, 'B');
      }
    });
  });

  group('screen projection', () {
    test('detects a newly loaded sprite atlas', () {
      final bridge = _FakeBridge(1, [_label(text: 'A')]);
      final source = MapLabelSource()..syncFromNative(bridge);

      expect(source.hasDifferentSpriteAtlas(null), isFalse);
      source.cacheScreenPositions(bridge, null);
      expect(source.hasDifferentSpriteAtlas(null), isFalse);
      final atlas = _FakeSpriteAtlas();
      expect(source.hasDifferentSpriteAtlas(atlas), isTrue);
      source.cacheScreenPositions(bridge, atlas);
      expect(source.hasDifferentSpriteAtlas(atlas), isFalse);
    });

    test('projects text and icon anchors separately', () {
      // The two anchors are distinct map positions; projecting one for both
      // would drag icons onto their labels.
      final bridge = _FakeBridge(1, [
        _label(
          text: 'A',
          textPlaced: true,
          iconPlaced: true,
          lat: 10,
          lon: 20,
          iconLat: 30,
          iconLon: 40,
        ),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);

      source.cacheScreenPositions(bridge, null);

      expect(bridge.projected, [(lat: 10, lon: 20), (lat: 30, lon: 40)]);
      expect(bridge.batchProjectionCalls, 1);
      final symbol = source.symbols.single;
      expect(symbol.textPos, isNotNull);
      expect(symbol.iconPos, isNotNull);
    });

    test('projects each low-zoom world copy independently', () {
      final bridge = _FakeBridge(1, [
        _label(text: 'west', crossTileId: 7, tileWrap: -1, lon: 140),
        _label(text: 'center', crossTileId: 7, lon: 140),
        _label(text: 'east', crossTileId: 7, tileWrap: 1, lon: 140),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);

      source.cacheScreenPositions(bridge, null);

      expect(source.symbols, hasLength(3));
      expect(source.symbols.map((symbol) => symbol.textPos!.dx), <double>[
        -220,
        140,
        500,
      ]);
      expect(
        bridge.projectionInputs.single.map((coordinate) => coordinate.tileWrap),
        [-1, 0, 1],
      );
    });

    test('reuses shared projection input across camera updates', () {
      final bridge = _FakeBridge(1, [
        _label(
          text: 'A',
          textPlaced: true,
          iconPlaced: true,
          icon: 'marker',
          lat: 10,
          lon: 20,
          iconLat: 10,
          iconLon: 20,
        ),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);

      source.cacheScreenPositions(bridge, null);
      final firstInput = bridge.projectionInputs.single;
      source.cacheScreenPositions(bridge, null);

      expect(bridge.projectionBatchSizes, [1, 1]);
      expect(bridge.projectionInputs.last, same(firstInput));
      expect(source.symbols.single.textPos, const Offset(20, 10));
      expect(source.symbols.single.iconPos, const Offset(20, 10));
    });

    test('keeps projection input when only symbol content changes', () {
      final bridge = _FakeBridge(1, [
        _label(text: 'A', crossTileId: 42, lat: 10, lon: 20),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);
      source.cacheScreenPositions(bridge, null);
      final firstInput = bridge.projectionInputs.single;

      bridge
        ..version = 2
        ..labels = [_label(text: 'B', crossTileId: 42, lat: 10, lon: 20)];
      source.syncFromNative(bridge);
      source.cacheScreenPositions(bridge, null);

      expect(bridge.projectionInputs.last, same(firstInput));
      expect(source.symbols.single.data.text, 'B');
    });

    test('reuses a settled symbol until its position changes', () {
      final bridge = _FakeBridge(1, [
        _label(text: 'A', crossTileId: 42, lat: 10, lon: 20),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);
      source.cacheScreenPositions(bridge, null);
      source.cacheScreenPositions(bridge, null);
      final settled = source.symbols.single;

      source.cacheScreenPositions(bridge, null);
      expect(source.symbols.single, same(settled));

      bridge.projectionOffset = const Offset(5, 7);
      source.cacheScreenPositions(bridge, null);
      expect(source.symbols.single, isNot(same(settled)));
      expect(source.symbols.single.textPos, const Offset(25, 17));
    });

    test('does not project an anchor MapLibre did not place', () {
      final bridge = _FakeBridge(1, [
        _label(text: 'A', textPlaced: true, iconPlaced: false),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);

      source.cacheScreenPositions(bridge, null);

      expect(bridge.projected, hasLength(1));
      expect(source.symbols.single.iconPos, isNull);
    });

    test('reorders stable entries when native render ranks change', () {
      final bridge = _FakeBridge(1, [
        _label(text: 'front', crossTileId: 1, renderOrder: 1),
        _label(text: 'back', crossTileId: 2, renderOrder: 0),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);

      source.cacheScreenPositions(bridge, null);
      expect(source.symbols.map((symbol) => symbol.data.text), [
        'back',
        'front',
      ]);

      bridge
        ..version = 2
        ..labels = [
          _label(text: 'front', crossTileId: 1, renderOrder: 0),
          _label(text: 'back', crossTileId: 2, renderOrder: 1),
        ];
      source.syncFromNative(bridge);
      source.cacheScreenPositions(bridge, null);

      expect(source.symbols.map((symbol) => symbol.data.text), [
        'front',
        'back',
      ]);
    });

    test('indexes immutable symbols by layer in native render order', () {
      final bridge = _FakeBridge(1, [
        _label(
          text: 'five-last',
          crossTileId: 1,
          layerIndex: 5,
          renderGroup: 1,
        ),
        _label(text: 'two', crossTileId: 2, layerIndex: 2),
        _label(
          text: 'five-first',
          crossTileId: 3,
          layerIndex: 5,
          renderGroup: 0,
        ),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);

      source.cacheScreenPositions(bridge, null);

      expect(source.symbolsByLayer.keys, [2, 5]);
      expect(source.symbolLayerIndices, [2, 5]);
      expect(source.symbolsForLayer(5).map((symbol) => symbol.data.text), [
        'five-first',
        'five-last',
      ]);
      expect(source.symbols.map((symbol) => symbol.data.text), [
        'two',
        'five-first',
        'five-last',
      ]);
      expect(source.symbolsForLayer(5), same(source.symbolsForLayer(5)));
      expect(source.symbols[1], same(source.symbolsForLayer(5).first));
      expect(source.symbolsForLayer(99), isEmpty);
      expect(
        () => source.symbolsForLayer(5).add(source.symbols.first),
        throwsUnsupportedError,
      );
      expect(
        () => source.symbolsByLayer[7] = source.symbols,
        throwsUnsupportedError,
      );
    });

    test('retained layer snapshots do not follow later projections', () {
      final bridge = _FakeBridge(1, [
        _label(text: 'A', crossTileId: 42, layerIndex: 2, lat: 10, lon: 20),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);
      source.cacheScreenPositions(bridge, null);
      final previous = source.symbolsForLayer(2);

      bridge.projectionOffset = const Offset(5, 7);
      source.cacheScreenPositions(bridge, null);

      expect(previous.single.textPos, const Offset(20, 10));
      expect(source.symbolsForLayer(2).single.textPos, const Offset(25, 17));
    });

    test(
      'live layer views expose current positions without changing snapshots',
      () {
        final bridge = _FakeBridge(1, [
          _label(text: 'A', crossTileId: 42, layerIndex: 2, lat: 10, lon: 20),
        ]);
        final source = MapLabelSource()..syncFromNative(bridge);
        source.cacheScreenPositions(bridge, null);
        final live = source.liveSymbolsForLayer(2) as SymbolPositionList;
        final key = live.single.key;
        final previous = source.symbolsForLayer(2);

        bridge.projectionOffset = const Offset(5, 7);
        source.cacheScreenPositions(bridge, null);

        expect(source.liveSymbolsForLayer(2), same(live));
        expect(live.anchorFor(key, icon: false), const Offset(25, 17));
        expect(live.positioned(previous.single).textPos, const Offset(25, 17));
        expect(previous.single.textPos, const Offset(20, 10));
      },
    );

    test('rebuilds the layer index when a symbol changes layers', () {
      final bridge = _FakeBridge(1, [
        _label(text: 'A', crossTileId: 42, layerIndex: 2),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);
      source.cacheScreenPositions(bridge, null);
      expect(source.symbolsForLayer(2), hasLength(1));

      bridge
        ..version = 2
        ..labels = [_label(text: 'A', crossTileId: 42, layerIndex: 5)];
      source.syncFromNative(bridge);
      source.cacheScreenPositions(bridge, null);

      expect(source.symbolsForLayer(2), isEmpty);
      expect(source.symbolsForLayer(5), hasLength(1));
      expect(source.symbolsByLayer.keys, [5]);
    });
  });

  group('fade lifecycle', () {
    test('a symbol fades in only on its first visible frame', () {
      final bridge = _FakeBridge(1, [_label(text: 'A')]);
      final source = MapLabelSource()..syncFromNative(bridge);

      source.cacheScreenPositions(bridge, null);
      expect(source.symbols.single.fadeIn, isTrue);

      source.cacheScreenPositions(bridge, null);
      expect(source.symbols.single.fadeIn, isFalse);
    });

    test('a missing symbol stays for one snapshot so it can fade out', () {
      final bridge = _FakeBridge(1, [
        _label(text: 'A', layer: 'l', crossTileId: 1),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);
      expect(source.entries, hasLength(1));

      bridge
        ..version = 2
        ..labels = [];
      source.syncFromNative(bridge);

      expect(source.entries, hasLength(1));
      expect(source.entries.values.single.visible, isFalse);
    });

    test('a faded-out entry is dropped', () {
      final bridge = _FakeBridge(1, [
        _label(text: 'A', layer: 'l', crossTileId: 1),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);
      bridge
        ..version = 2
        ..labels = [];
      source.syncFromNative(bridge);

      source.onFadedOut(source.entries.keys.single);

      expect(source.entries, isEmpty);
      source.cacheScreenPositions(bridge, null);
      expect(source.symbols, isEmpty);
    });

    test('a symbol that came back is not dropped by a late fade callback', () {
      // The overlay's fade completion can arrive after the symbol reappears;
      // honouring it would delete a visible symbol.
      final bridge = _FakeBridge(1, [
        _label(text: 'A', layer: 'l', crossTileId: 1),
      ]);
      final source = MapLabelSource()..syncFromNative(bridge);
      final key = source.entries.keys.single;

      source.onFadedOut(key);

      expect(source.entries, hasLength(1));
    });
  });

  group('reset', () {
    test('re-reads even when native reports the same version', () {
      // A style reload replaces every symbol while native's version counter
      // keeps running; matching the old version would strand stale labels.
      final bridge = _FakeBridge(5, [_label(text: 'A')]);
      final source = MapLabelSource()..syncFromNative(bridge);
      source.cacheScreenPositions(bridge, null);

      source.reset();

      expect(source.entries, isEmpty);
      expect(source.symbols, isEmpty);
      expect(source.symbolsByLayer, isEmpty);
      expect(source.placedLabels, isEmpty);
      expect(source.syncFromNative(bridge), isTrue);
    });
  });
}
