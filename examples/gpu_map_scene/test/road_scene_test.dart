import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu_map_scene_example/gpu/kenney_mesh_data.dart';
import 'package:maplibre_flutter_gpu_map_scene_example/osrm_route_service.dart';
import 'package:maplibre_flutter_gpu_map_scene_example/road_scene.dart';

void main() {
  test('cars use a slow five-minute road loop', () {
    expect(carLoopDuration, const Duration(minutes: 5));
  });

  test('closed route sampling wraps and interpolates', () {
    final route = parseOsrmRoadLoop(
      '{"code":"Ok","routes":[{"geometry":{"type":"LineString",'
      '"coordinates":[[139.0,35.0],[140.0,36.0]]}}]}',
    );
    expect(sampleClosedRoute(route, 0), sampleClosedRoute(route, 1));
    final midway = sampleClosedRoute(const [LatLng(0, 0), LatLng(10, 20)], 0.5);
    expect(midway, const LatLng(5, 10));
  });

  test('OSRM request asks for full GeoJSON road geometry', () {
    final uri = tokyoStationRouteUri();

    expect(uri.host, osrmDemoServer);
    expect(uri.path, startsWith('/route/v1/driving/'));
    expect(uri.queryParameters['geometries'], 'geojson');
    expect(uri.queryParameters['overview'], 'full');
    expect(tokyoStationRouteWaypoints.first, tokyoStationRouteWaypoints.last);
  });

  test('OSRM response becomes a closed geographic route', () {
    final route = parseOsrmRoadLoop(
      '{"code":"Ok","routes":[{"geometry":{"type":"LineString",'
      '"coordinates":[[139.1,35.1],[139.2,35.2],[139.3,35.3]]}}]}',
    );

    expect(route, hasLength(4));
    expect(route.first, const LatLng(35.1, 139.1));
    expect(route.last, route.first);
  });

  test('OSRM failure does not manufacture a fallback route', () {
    expect(
      () => parseOsrmRoadLoop(
        '{"code":"NoRoute","message":"No route was found"}',
      ),
      throwsFormatException,
    );
  });

  test('route progress follows distance rather than vertex count', () {
    final midpoint = sampleClosedRoute(const [
      LatLng(0, 0),
      LatLng(0, 1),
      LatLng(0, 4),
    ], 0.5);
    expect(midpoint.latitude, 0);
    expect(midpoint.longitude, closeTo(2, 1e-9));
  });

  test('overlay shader manifest contains vertex and fragment pair', () {
    final manifest = jsonDecode(
      File('shaders/OverlayShaders.shaderbundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(
      manifest.keys,
      containsAll(<String>['OverlayVertex', 'OverlayFragment']),
    );
  });

  test('models use map-space transforms instead of screen projection', () {
    final renderer = File('lib/gpu/map_scene_renderer.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final vertexShader = File('shaders/overlay.vert').readAsStringSync();

    expect(renderer, contains('frame.mapTransform'));
    expect(renderer, contains('mapTransform.project(object.position)'));
    expect(renderer, contains('drawIndexed(mesh.indexCount)'));
    expect(vertexShader, contains('overlay.view_projection'));
    expect('$main\n$renderer', isNot(contains('toScreenOffset')));
    expect('$main\n$renderer', isNot(contains('screenPosition')));
  });

  test('bundles colorless Kenney car and building geometry', () {
    expect(kenneySedanMesh.sourceName, 'sedan.glb');
    expect(kenneyBuildingMesh.sourceName, 'low-detail-building-a.glb');
    expect(kenneySedanMesh.vertices.length % 6, 0);
    expect(kenneyBuildingMesh.vertices.length % 6, 0);
    expect(kenneySedanMesh.indices.length % 3, 0);
    expect(kenneyBuildingMesh.indices.length % 3, 0);
    expect(
      kenneySedanMesh.indices.reduce(
        (left, right) => left > right ? left : right,
      ),
      lessThan(kenneySedanMesh.vertices.length ~/ 6),
    );
    expect(
      kenneyBuildingMesh.indices.reduce(
        (left, right) => left > right ? left : right,
      ),
      lessThan(kenneyBuildingMesh.vertices.length ~/ 6),
    );
  });
}
