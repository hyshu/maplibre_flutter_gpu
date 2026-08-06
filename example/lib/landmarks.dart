import 'package:flutter/material.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

/// World landmark displayed as a regular Flutter widget above the map.
class WorldLandmark {
  const WorldLandmark({
    required this.country,
    required this.name,
    required this.symbol,
    required this.location,
    required this.zoom,
    required this.color,
  });

  final String country;
  final String name;
  final String symbol;
  final LatLng location;
  final double zoom;
  final Color color;
}

const worldLandmarks = [
  WorldLandmark(
    country: 'Japan',
    name: 'Mount Fuji',
    symbol: '🗻',
    location: LatLng(35.3606, 138.7274),
    zoom: 9,
    color: Color(0xffd84a4a),
  ),
  WorldLandmark(
    country: 'France',
    name: 'Eiffel Tower',
    symbol: '🗼',
    location: LatLng(48.8584, 2.2945),
    zoom: 15.5,
    color: Color(0xff315ea8),
  ),
  WorldLandmark(
    country: 'United States',
    name: 'Statue of Liberty',
    symbol: '🗽',
    location: LatLng(40.6892, -74.0445),
    zoom: 15,
    color: Color(0xff258b78),
  ),
  WorldLandmark(
    country: 'Brazil',
    name: 'Christ the Redeemer',
    symbol: '✝️',
    location: LatLng(-22.9519, -43.2105),
    zoom: 14,
    color: Color(0xff298b48),
  ),
  WorldLandmark(
    country: 'Egypt',
    name: 'Pyramids of Giza',
    symbol: '🔺',
    location: LatLng(29.9792, 31.1342),
    zoom: 14,
    color: Color(0xffb47724),
  ),
  WorldLandmark(
    country: 'India',
    name: 'Taj Mahal',
    symbol: '🕌',
    location: LatLng(27.1751, 78.0421),
    zoom: 15,
    color: Color(0xffd06d32),
  ),
  WorldLandmark(
    country: 'Australia',
    name: 'Sydney Opera House',
    symbol: '🎭',
    location: LatLng(-33.8568, 151.2153),
    zoom: 15,
    color: Color(0xff147c91),
  ),
  WorldLandmark(
    country: 'United Kingdom',
    name: 'Big Ben',
    symbol: '🕰️',
    location: LatLng(51.5007, -0.1246),
    zoom: 16,
    color: Color(0xff70479b),
  ),
  WorldLandmark(
    country: 'Italy',
    name: 'Colosseum',
    symbol: '🏛️',
    location: LatLng(41.8902, 12.4922),
    zoom: 16,
    color: Color(0xffa84e34),
  ),
  WorldLandmark(
    country: 'United Arab Emirates',
    name: 'Burj Khalifa',
    symbol: '🏙️',
    location: LatLng(25.1972, 55.2744),
    zoom: 15.5,
    color: Color(0xff356e87),
  ),
  WorldLandmark(
    country: 'Singapore',
    name: 'Merlion',
    symbol: '🦁',
    location: LatLng(1.2868, 103.8545),
    zoom: 16,
    color: Color(0xffb64343),
  ),
  WorldLandmark(
    country: 'Mexico',
    name: 'Chichén Itzá',
    symbol: '🛕',
    location: LatLng(20.6843, -88.5678),
    zoom: 14,
    color: Color(0xff687c32),
  ),
];

/// Visual scale for a landmark marker at a map [zoom].
///
/// Markers stay tappable at world scale and grow gradually as the camera
/// approaches street level.
double landmarkMarkerScale(double zoom) =>
    (0.55 + (zoom - 1) * 0.04).clamp(0.55, 1.15);
