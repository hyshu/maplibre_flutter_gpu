import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'gpu/map_scene_renderer.dart';
import 'gpu/overlay_shader_library.dart';
import 'osrm_route_service.dart';
import 'road_scene.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final shaderLibrary = await loadOverlayShaderLibrary();
  runApp(GpuMapSceneApp(shaderLibrary: shaderLibrary));
}

class GpuMapSceneApp extends StatelessWidget {
  const GpuMapSceneApp({required this.shaderLibrary, super.key});

  final gpu.ShaderLibrary shaderLibrary;

  @override
  Widget build(context) => MaterialApp(
    title: 'Flutter GPU Map Scene',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b5b)),
      useMaterial3: true,
    ),
    home: GpuMapScenePage(shaderLibrary: shaderLibrary),
  );
}

class GpuMapScenePage extends StatefulWidget {
  const GpuMapScenePage({required this.shaderLibrary, super.key});

  final gpu.ShaderLibrary shaderLibrary;

  @override
  State<GpuMapScenePage> createState() => _GpuMapScenePageState();
}

class _GpuMapScenePageState extends State<GpuMapScenePage>
    with SingleTickerProviderStateMixin {
  static const _overviewCamera = CameraPosition(
    target: LatLng(35.6806, 139.7664),
    zoom: 15.2,
    bearing: -18,
    tilt: 45,
  );

  late final AnimationController _animation;
  MapLibreMapController? _mapController;
  late final MapSceneRenderer _renderer;
  final _buildings = <LatLng>[];
  var _thirdPersonView = false;
  List<LatLng>? _roadLoop;
  Object? _routeError;
  var _routeLoading = true;

  @override
  void initState() {
    super.initState();
    _renderer = MapSceneRenderer(widget.shaderLibrary);
    _animation = AnimationController(vsync: this, duration: carLoopDuration);
    _animation.addListener(_updateThirdPersonCamera);
    unawaited(_loadRoadLoop());
  }

  Future<void> _loadRoadLoop() async {
    _animation.stop();
    setState(() {
      _roadLoop = null;
      _routeError = null;
      _routeLoading = true;
    });
    try {
      final route = await fetchTokyoStationRoadLoop();
      if (!mounted) return;
      setState(() {
        _roadLoop = route;
        _routeLoading = false;
      });
      _animation
        ..reset()
        ..repeat();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _routeError = error;
        _routeLoading = false;
      });
    }
  }

  void _addBuilding(LatLng coordinates) {
    setState(() {
      if (_buildings.length == 20) _buildings.removeAt(0);
      _buildings.add(coordinates);
    });
  }

  Future<void> _confirmClearBuildings() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove all buildings?'),
        content: Text(
          'This removes all ${_buildings.length} buildings from the map.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (shouldClear == true && mounted) setState(_buildings.clear);
  }

  List<MapSceneObject> _sceneObjects() {
    final objects = <MapSceneObject>[];

    final roadLoop = _roadLoop;
    if (roadLoop != null) {
      for (var index = 0; index < 4; index++) {
        final progress = _animation.value + index / 4;
        final location = sampleClosedRoute(roadLoop, progress);
        final ahead = sampleClosedRoute(roadLoop, progress + 0.002);
        objects.add(
          MapSceneObject(
            kind: MapSceneObjectKind.car,
            position: location,
            headingRadians: _mapHeading(location, ahead),
          ),
        );
      }
    }

    for (final building in _buildings) {
      objects.add(
        MapSceneObject(kind: MapSceneObjectKind.building, position: building),
      );
    }
    return objects;
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    _updateThirdPersonCamera();
  }

  void _toggleThirdPersonView() {
    final enabled = !_thirdPersonView;
    setState(() => _thirdPersonView = enabled);
    if (enabled) {
      _updateThirdPersonCamera();

      return;
    }
    final controller = _mapController;
    if (controller != null) {
      unawaited(
        controller.animateCamera(
          CameraUpdate.newCameraPosition(_overviewCamera),
        ),
      );
    }
  }

  void _updateThirdPersonCamera() {
    if (!_thirdPersonView) return;
    final controller = _mapController;
    final roadLoop = _roadLoop;
    if (controller == null || roadLoop == null) return;
    final carPosition = sampleClosedRoute(roadLoop, _animation.value);
    final ahead = sampleClosedRoute(roadLoop, _animation.value + 0.002);
    unawaited(
      controller.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: carPosition,
            zoom: 18,
            bearing: _cameraBearing(carPosition, ahead),
            tilt: 60,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animation.dispose();
    _renderer.releaseReferences();
    super.dispose();
  }

  @override
  Widget build(context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kenney GPU Street', overflow: TextOverflow.ellipsis),
          Text(
            'Tap the map to place a Kenney building',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: _thirdPersonView
              ? 'Return to overview'
              : 'Follow the lead car',
          onPressed: _roadLoop == null ? null : _toggleThirdPersonView,
          icon: Icon(
            _thirdPersonView ? Icons.map_outlined : Icons.drive_eta_outlined,
          ),
        ),
        IconButton(
          tooltip: 'Remove placed buildings',
          onPressed: _buildings.isEmpty
              ? null
              : () => unawaited(_confirmClearBuildings()),
          icon: Badge(
            isLabelVisible: _buildings.isNotEmpty,
            label: Text('${_buildings.length}'),
            child: const Icon(Icons.delete_outline),
          ),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: Stack(
      children: [
        Positioned.fill(
          child: MapLibreMap(
            styleString: MapLibreStyles.openfreemapLiberty,
            initialCameraPosition: _overviewCamera,
            onMapCreated: _onMapCreated,
            onMapClick: (_, coordinates) => _addBuilding(coordinates),
            gpuRepaint: _animation,
            gpuMapRenderCallback: (frame) {
              _renderer.draw(frame, objects: _sceneObjects());
            },
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: _RouteStatus(
                  loading: _routeLoading,
                  error: _routeError,
                  thirdPersonView: _thirdPersonView,
                  buildingCount: _buildings.length,
                  onRetry: () => unawaited(_loadRoadLoop()),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _RouteStatus extends StatelessWidget {
  const _RouteStatus({
    required this.loading,
    required this.error,
    required this.thirdPersonView,
    required this.buildingCount,
    required this.onRetry,
  });

  final bool loading;
  final Object? error;
  final bool thirdPersonView;
  final int buildingCount;
  final VoidCallback onRetry;

  @override
  Widget build(context) {
    if (loading) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Calculating road route…'),
        ],
      );
    }
    if (error != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 18),
          const SizedBox(width: 6),
          const Text('Road routing failed'),
          const SizedBox(width: 4),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    }
    return Text(
      'OSRM cars 4 driving  •  '
      'Buildings $buildingCount',
      style: Theme.of(context).textTheme.labelLarge,
    );
  }
}

double _mapHeading(LatLng start, LatLng end) {
  final meanLatitude = (start.latitude + end.latitude) * 0.5 * math.pi / 180;
  final east = (end.longitude - start.longitude) * math.cos(meanLatitude);
  final north = end.latitude - start.latitude;

  return math.atan2(north, east);
}

double _cameraBearing(LatLng start, LatLng end) =>
    90 - _mapHeading(start, end) * 180 / math.pi;
