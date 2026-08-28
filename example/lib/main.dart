import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'landmarks.dart';

const _landmarkMarkerSize = 46.0;
const _selectedLandmarkMarkerSize = 54.0;
const _landmarkMarkerFontSize = 23.0;
const _selectedLandmarkMarkerFontSize = 27.0;
const _landmarkViewportPadding = EdgeInsets.fromLTRB(60, 70, 60, 60);

void main() => runApp(const WorldLandmarksApp());

class WorldLandmarksApp extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(context) => MaterialApp(
    title: 'World Landmarks',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b5b)),
      useMaterial3: true,
    ),
    home: const WorldLandmarksPage(),
  );
}

class WorldLandmarksPage extends StatefulWidget {
  const new({super.key});

  @override
  State<WorldLandmarksPage> createState() => _WorldLandmarksPageState();
}

class _WorldLandmarksPageState extends State<WorldLandmarksPage> {
  MapLibreMapController? _controller;
  WorldLandmark? _selected;
  var _positions = const <_LandmarkPosition>[];
  var _zoom = 1.35;
  var _styleReady = false;

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    controller.addListener(_projectLandmarks);
    _projectLandmarks();
  }

  void _onStyleLoaded() {
    if (!mounted) return;
    setState(() => _styleReady = true);
  }

  void _projectLandmarks() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    setState(() {
      _zoom = controller.cameraPosition?.zoom ?? _zoom;
      _positions = [
        for (final landmark in worldLandmarks)
          for (final offset in controller.toScreenOffsets(
            landmark.location,
            padding: _landmarkViewportPadding,
          ))
            _LandmarkPosition(landmark: landmark, offset: offset),
      ];
    });
  }

  Future<void> _visit(WorldLandmark landmark) async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _selected = landmark);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !identical(controller, _controller)) return;

    // Refresh the camera snapshot after overlays and pointer gestures settle.
    await controller.queryCameraPosition();
    final update = CameraUpdate.newLatLngZoom(landmark.location, landmark.zoom);
    await controller.animateCamera(
      update,
      duration: const Duration(milliseconds: 900),
    );
  }

  Future<void> _showLandmarkList() async {
    final landmark = await showModalBottomSheet<WorldLandmark>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.72,
          child: Column(
            crossAxisAlignment: .start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'World Landmarks',
                  style: TextStyle(fontSize: 22, fontWeight: .w700),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: worldLandmarks.length,
                  itemBuilder: (context, index) {
                    final landmark = worldLandmarks[index];

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: landmark.color.withValues(alpha: 0.14),
                        child: Text(
                          landmark.symbol,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      title: Text(landmark.name),
                      subtitle: Text(landmark.country),
                      trailing: const Icon(Icons.arrow_forward),
                      selected: _selected == landmark,
                      onTap: () => Navigator.pop(context, landmark),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (landmark != null && mounted) await _visit(landmark);
  }

  @override
  void dispose() {
    _controller?.removeListener(_projectLandmarks);
    super.dispose();
  }

  @override
  Widget build(context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: .start,
        children: [
          const Text('World Landmarks', overflow: .ellipsis),
          Text(
            _selected == null
                ? 'Choose a world landmark'
                : '${_selected!.symbol} ${_selected!.country}・'
                      '${_selected!.name}',
            maxLines: 1,
            overflow: .ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: .normal),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: _styleReady ? 'Open world landmark list' : 'Loading map',
          onPressed: _styleReady ? () => unawaited(_showLandmarkList()) : null,
          icon: const Icon(Icons.public),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(
            child: MapLibreMap(
              styleString: MapLibreStyles.openfreemapLiberty,
              initialCameraPosition: const CameraPosition(
                target: LatLng(20, 10),
                zoom: 1.35,
              ),
              trackCameraPosition: true,
              onMapCreated: _onMapCreated,
              onStyleLoadedCallback: _onStyleLoaded,
            ),
          ),
          for (final position in _positions)
            if (_isOnScreen(position.offset, constraints.biggest))
              _LandmarkMarker(
                position: position,
                selected: _selected == position.landmark,
                zoom: _zoom,
                onTap: () => unawaited(_visit(position.landmark)),
              ),
        ],
      ),
    ),
  );

  bool _isOnScreen(Offset offset, Size size) =>
      offset.dx >= -_landmarkViewportPadding.left &&
      offset.dx <= size.width + _landmarkViewportPadding.right &&
      offset.dy >= -_landmarkViewportPadding.top &&
      offset.dy <= size.height + _landmarkViewportPadding.bottom;
}

class _LandmarkMarker extends StatelessWidget {
  const new({
    required this.position,
    required this.selected,
    required this.zoom,
    required this.onTap,
  });

  final _LandmarkPosition position;
  final bool selected;
  final double zoom;
  final VoidCallback onTap;

  @override
  Widget build(context) {
    final landmark = position.landmark;
    final scale = landmarkMarkerScale(zoom);
    final size =
        (selected ? _selectedLandmarkMarkerSize : _landmarkMarkerSize) * scale;
    final fontSize =
        (selected ? _selectedLandmarkMarkerFontSize : _landmarkMarkerFontSize) *
        scale;

    return Positioned(
      left: position.offset.dx - size / 2,
      top: position.offset.dy - size,
      child: Semantics(
        button: true,
        label: 'Fly to ${landmark.name}, ${landmark.country}',
        child: Tooltip(
          message: '${landmark.country}・${landmark.name}',
          child: InkResponse(
            onTap: onTap,
            radius: size / 2,
            child: Container(
              width: size,
              height: size,
              alignment: .center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: .circle,
                border: Border.all(
                  color: landmark.color,
                  width: selected ? 4 : 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                landmark.symbol,
                style: TextStyle(fontSize: fontSize),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LandmarkPosition {
  const new({required this.landmark, required this.offset});

  final WorldLandmark landmark;
  final Offset offset;
}
