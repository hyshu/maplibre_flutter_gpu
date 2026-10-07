import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

/// Preset camera positions for exploring cities with a TV remote.
enum TvCity {
  /// Midtown Manhattan near the Empire State Building.
  newYork(
    'New York',
    CameraPosition(target: LatLng(40.7484, -73.9857), zoom: 15.5),
  ),

  /// Westminster near Parliament Square.
  london(
    'London',
    CameraPosition(target: LatLng(51.5007, -0.1246), zoom: 15.5),
  ),

  /// The area around Notre-Dame on the Île de la Cité.
  paris('Paris', CameraPosition(target: LatLng(48.8531, 2.3489), zoom: 15.5)),

  /// The central business district of Sydney.
  sydney(
    'Sydney',
    CameraPosition(target: LatLng(-33.8688, 151.2093), zoom: 15.5),
  );

  const TvCity(this.label, this.camera);

  /// The city name shown in the controls.
  final String label;

  /// The north-facing, flat camera used when visiting this city.
  final CameraPosition camera;
}
