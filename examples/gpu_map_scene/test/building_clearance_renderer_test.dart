import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu_map_scene_example/building_clearance_renderer.dart';

const _key = FillExtrusionTileKey(
  z: 14,
  x: 8000,
  y: 8192,
  overscaledZ: 16,
  wrap: 0,
  segment: 0,
);

class _PlacementNotifier extends ValueNotifier<List<LatLng>> {
  _PlacementNotifier() : super(const []);

  bool get hasPlacementListeners => hasListeners;
}

class _Tile extends FillExtrusionTile {
  _Tile(List<Rect> footprints, {this.key = _key}) {
    final vertices = <double>[];
    for (var index = 0; index < footprints.length; index += 1) {
      final bounds = footprints[index];
      parts.add(
        FillExtrusionPart(
          tile: key,
          featureIndex: 7,
          polygonIndex: index,
          featureId: 'merged-buildings',
          vertexOffset: vertices.length ~/ 3,
          vertexCount: 4,
          indexOffset: index * 6,
          indexCount: 6,
        ),
      );
      vertices.addAll([
        bounds.left,
        bounds.top,
        0,
        bounds.right,
        bounds.top,
        20,
        bounds.right,
        bounds.bottom,
        20,
        bounds.left,
        bounds.bottom,
        0,
      ]);
    }
    _positions = Float32List.fromList(vertices);
  }

  @override
  final FillExtrusionTileKey key;
  @override
  final parts = <FillExtrusionPart>[];
  late final Float32List _positions;
  var positionReads = 0;

  @override
  Float32List get positions {
    positionReads += 1;

    return _positions;
  }

  @override
  int get vertexCount => _positions.length ~/ 3;
  @override
  Uint16List get indices => Uint16List(0);
  @override
  Float32List get normals => Float32List(0);
  @override
  Float32List get edgeDistances => Float32List(0);
  @override
  Uint8List get upperVertices => Uint8List(0);
}

void main() {
  late _PlacementNotifier buildings;
  late BuildingClearanceRenderer renderer;

  setUp(() {
    buildings = _PlacementNotifier();
    renderer = BuildingClearanceRenderer(buildings);
  });

  tearDown(() {
    renderer.dispose();
    buildings.dispose();
  });

  test('nearby polygons hide independently within a merged feature', () {
    final tile = _Tile([
      const Rect.fromLTRB(100, 100, 200, 200),
      const Rect.fromLTRB(1000, 1000, 1100, 1100),
    ]);
    renderer.didAddTile(tile);
    buildings.value = [tile.latLngAt(150, 150)];

    expect(renderer.isVisible(tile.parts[0]), isFalse);
    expect(renderer.isVisible(tile.parts[1]), isTrue);
    expect(tile.parts[0].featureId, tile.parts[1].featureId);
  });

  test('a 24 meter circle intersects footprint edges and rounded corners', () {
    final tile = _Tile([const Rect.fromLTRB(100, 100, 200, 200)]);
    renderer.didAddTile(tile);
    final unitsPerMeter = 1 / tile.metersPerUnit;
    buildings.value = [tile.latLngAt(200 + 23 * unitsPerMeter, 150)];
    expect(renderer.isVisible(tile.parts.single), isFalse);

    buildings.value = [tile.latLngAt(200 + 25 * unitsPerMeter, 150)];
    expect(renderer.isVisible(tile.parts.single), isTrue);

    buildings.value = [
      tile.latLngAt(200 + 18 * unitsPerMeter, 200 + 18 * unitsPerMeter),
    ];
    expect(renderer.isVisible(tile.parts.single), isTrue);
  });

  test('replacing and clearing placements restores previous footprints', () {
    final tile = _Tile([
      const Rect.fromLTRB(100, 100, 200, 200),
      const Rect.fromLTRB(1000, 1000, 1100, 1100),
    ]);
    renderer.didAddTile(tile);
    buildings.value = [tile.latLngAt(150, 150)];
    buildings.value = [tile.latLngAt(1050, 1050)];
    expect(renderer.isVisible(tile.parts[0]), isTrue);
    expect(renderer.isVisible(tile.parts[1]), isFalse);

    buildings.value = [tile.latLngAt(150, 150), tile.latLngAt(1050, 1050)];
    expect(tile.parts.every((part) => !renderer.isVisible(part)), isTrue);

    buildings.value = const [];
    expect(tile.parts.every(renderer.isVisible), isTrue);
  });

  test('new and updated tile snapshots use the active placements', () {
    final original = _Tile([const Rect.fromLTRB(100, 100, 200, 200)]);
    buildings.value = [original.latLngAt(150, 150)];
    renderer.didAddTile(original);
    expect(renderer.isVisible(original.parts.single), isFalse);

    final updated = _Tile([const Rect.fromLTRB(1000, 1000, 1100, 1100)]);
    renderer.didAddTile(updated);
    expect(renderer.isVisible(updated.parts.single), isTrue);

    buildings.value = [updated.latLngAt(1050, 1050)];
    expect(renderer.isVisible(updated.parts.single), isFalse);
    renderer.didRemoveTile(updated.key);
    expect(renderer.isVisible(updated.parts.single), isTrue);
    renderer.didAddTile(updated);
    expect(renderer.isVisible(updated.parts.single), isFalse);
  });

  test('empty placements leave geometry unread and bounds are cached', () {
    final tile = _Tile([const Rect.fromLTRB(100, 100, 200, 200)]);
    renderer.didAddTile(tile);
    expect(renderer.isVisible(tile.parts.single), isTrue);
    expect(tile.positionReads, 0);

    buildings.value = [tile.latLngAt(150, 150)];
    expect(tile.positionReads, 1);
    buildings.value = [tile.latLngAt(1050, 1050)];
    expect(tile.positionReads, 1);
    renderer.didRemoveTile(tile.key);
    buildings.value = [tile.latLngAt(150, 150)];
    expect(tile.positionReads, 1);
  });

  test('repaint listeners observe the recomputed visibility', () {
    final tile = _Tile([const Rect.fromLTRB(100, 100, 200, 200)]);
    renderer.didAddTile(tile);
    final visibility = <bool>[];
    void recordVisibility() =>
        visibility.add(renderer.isVisible(tile.parts.single));
    renderer.repaint!.addListener(recordVisibility);

    buildings.value = [tile.latLngAt(150, 150)];
    buildings.value = const [];
    expect(visibility, [false, true]);
    renderer.repaint!.removeListener(recordVisibility);
  });

  test('placement clearance follows world copies across the antimeridian', () {
    for (final wrap in [-1, 0, 1]) {
      final tile = _Tile(
        [const Rect.fromLTRB(8170, 100, 8190, 200)],
        key: FillExtrusionTileKey(
          z: 14,
          x: 16383,
          y: 8192,
          overscaledZ: 16,
          wrap: wrap,
          segment: 0,
        ),
      );
      renderer.didAddTile(tile);
      final position = tile.latLngAt(8200, 150);
      expect(position.longitude, lessThan(0));
      buildings.value = [position];
      expect(renderer.isVisible(tile.parts.single), isFalse);
    }
  });

  test('dispose removes the listener and retains the shared notifier', () {
    final tile = _Tile([const Rect.fromLTRB(100, 100, 200, 200)]);
    renderer.didAddTile(tile);
    expect(buildings.hasPlacementListeners, isTrue);
    renderer.dispose();
    expect(buildings.hasPlacementListeners, isFalse);

    buildings.value = [tile.latLngAt(150, 150)];
    expect(tile.positionReads, 0);
    expect(renderer.isVisible(tile.parts.single), isTrue);
  });
}
