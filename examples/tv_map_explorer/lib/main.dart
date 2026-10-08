import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'tv_city.dart';
import 'tv_map_controls.dart';

void main() => runApp(const TvMapExplorerApp());

/// An Android TV map example operated with direction and select keys.
class TvMapExplorerApp extends StatelessWidget {
  const TvMapExplorerApp({super.key});

  @override
  Widget build(context) => MaterialApp(
    title: 'TV Map Explorer',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b5b)),
      useMaterial3: true,
    ),
    home: const _TvMapExplorerPage(),
  );
}

class _TvMapExplorerPage extends StatefulWidget {
  const _TvMapExplorerPage();

  @override
  State<_TvMapExplorerPage> createState() => _TvMapExplorerPageState();
}

class _TvMapExplorerPageState extends State<_TvMapExplorerPage> {
  MapLibreMapController? _controller;
  var _ready = false;
  var _is3d = false;
  var _cameraCommand = 0;
  String? _error;

  Future<void> _move(
    CameraUpdate update, {
    Duration duration = const Duration(milliseconds: 300),
    CameraAnimationInterpolation? interpolation,
  }) async {
    final controller = _controller;
    if (controller == null || !_ready) return;
    final command = ++_cameraCommand;
    try {
      final accepted = await controller.easeCamera(
        update,
        duration: duration,
        interpolation: interpolation,
      );
      if (!mounted || command != _cameraCommand) return;
      setState(() => _error = accepted == true ? null : 'Camera move stopped.');
    } catch (_) {
      if (mounted && command == _cameraCommand) {
        setState(() => _error = 'Could not move the camera.');
      }
    }
  }

  void _visit(TvCity city) =>
      unawaited(_move(CameraUpdate.newCameraPosition(city.camera)));

  // Map scrolling drags content opposite to the camera's screen direction.
  void _pan(Offset direction) => unawaited(
    _move(
      CameraUpdate.scrollBy(-direction.dx, -direction.dy),
      duration: const Duration(milliseconds: 160),
      interpolation: .linear,
    ),
  );

  void _act(TvMapAction action) {
    switch (action) {
      case .zoomIn:
        unawaited(
          _move(
            CameraUpdate.zoomBy(1),
            duration: const Duration(milliseconds: 400),
            interpolation: .easeOut,
          ),
        );
      case .zoomOut:
        unawaited(
          _move(
            CameraUpdate.zoomBy(-1),
            duration: const Duration(milliseconds: 400),
            interpolation: .easeOut,
          ),
        );
      case .toggle3d:
        unawaited(_move(CameraUpdate.tiltTo(_is3d ? 0 : 50)));
      case .attribution:
        unawaited(_showAttribution());
    }
  }

  Future<void> _showAttribution() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Map data'),
      content: const Text(
        'OpenFreeMap\nopenfreemap.org\n\n'
        '© OpenMapTiles\nopenmaptiles.org\n\n'
        '© OpenStreetMap contributors\nopenstreetmap.org/copyright',
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  @override
  Widget build(context) => Scaffold(
    body: TvMapControls(
      ready: _ready,
      is3d: _is3d,
      message: _error,
      onVisit: _visit,
      onPan: _pan,
      onAction: _act,
      child: MapLibreMap(
        styleString: MapLibreStyles.openfreemapLiberty,
        initialCameraPosition: TvCity.newYork.camera,
        minMaxZoomPreference: const MinMaxZoomPreference(2, 19),
        onMapCreated: (controller) => _controller = controller,
        onStyleLoadedCallback: () => setState(() => _ready = true),
        onCameraMove: (camera) {
          final is3d = camera.tilt > 0;
          if (_is3d != is3d) setState(() => _is3d = is3d);
        },
        scrollGesturesEnabled: false,
        zoomGesturesEnabled: false,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        compassEnabled: false,
        attributionButtonEnabled: false,
        errorBuilder: (context, error) => Center(
          child: Text('Could not load the map.\n$error', textAlign: .center),
        ),
      ),
    ),
  );
}
