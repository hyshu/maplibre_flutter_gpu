import 'dart:convert';
import 'dart:io';

import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

const osrmDemoServer = 'router.project-osrm.org';

/// Coarse destinations around Tokyo Station.
///
/// OSRM snaps these points to its OpenStreetMap road graph and calculates the
/// detailed loop geometry at runtime.
const tokyoStationRouteWaypoints = [
  LatLng(35.681314, 139.763272),
  LatLng(35.685367, 139.763083),
  LatLng(35.685221, 139.771376),
  LatLng(35.681956, 139.769974),
  LatLng(35.676133, 139.769778),
  LatLng(35.677188, 139.761911),
  LatLng(35.681314, 139.763272),
];

Uri tokyoStationRouteUri() {
  final coordinates = tokyoStationRouteWaypoints
      .map((point) => '${point.longitude},${point.latitude}')
      .join(';');

  return Uri.https(osrmDemoServer, '/route/v1/driving/$coordinates', const {
    'geometries': 'geojson',
    'overview': 'full',
    'steps': 'false',
  });
}

Future<List<LatLng>> fetchTokyoStationRoadLoop({HttpClient? httpClient}) async {
  final client = httpClient ?? HttpClient();
  final ownsClient = httpClient == null;
  try {
    final request = await client
        .getUrl(tokyoStationRouteUri())
        .timeout(const Duration(seconds: 10));
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(
        HttpHeaders.userAgentHeader,
        'maplibre_flutter_gpu gpu_map_scene example',
      );
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'OSRM returned HTTP ${response.statusCode}',
        uri: tokyoStationRouteUri(),
      );
    }
    return parseOsrmRoadLoop(body);
  } finally {
    if (ownsClient) client.close(force: true);
  }
}

List<LatLng> parseOsrmRoadLoop(String responseBody) {
  final json = jsonDecode(responseBody) as Map<String, dynamic>;
  if (json['code'] != 'Ok') {
    throw FormatException(
      'OSRM route failed: ${json['message'] ?? json['code'] ?? 'unknown error'}',
    );
  }
  final routes = json['routes'] as List<dynamic>?;
  if (routes == null || routes.isEmpty) {
    throw const FormatException('OSRM returned no routes');
  }
  final route = routes.first as Map<String, dynamic>;
  final geometry = route['geometry'] as Map<String, dynamic>?;
  final coordinates = geometry?['coordinates'] as List<dynamic>?;
  if (geometry?['type'] != 'LineString' ||
      coordinates == null ||
      coordinates.length < 2) {
    throw const FormatException('OSRM returned invalid route geometry');
  }

  final points = [
    for (final coordinate in coordinates)
      if (coordinate is List && coordinate.length >= 2)
        LatLng(
          (coordinate[1] as num).toDouble(),
          (coordinate[0] as num).toDouble(),
        ),
  ];
  if (points.length < 2) {
    throw const FormatException('OSRM route geometry has too few points');
  }
  if (points.last != points.first) points.add(points.first);

  return List.unmodifiable(points);
}
