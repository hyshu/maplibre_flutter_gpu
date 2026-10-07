import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'heatmap_controls.dart';
import 'heatmap_style.dart';
import 'hillshade_controls.dart';
import 'hillshade_style.dart';
import 'map_layers_style.dart';

enum _LayerDemo { heatmap, hillshade }

void main() => runApp(const MapLayersApp());

class MapLayersApp extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(context) => MaterialApp(
    title: 'Map Layers',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b5b)),
      useMaterial3: true,
    ),
    home: const MapLayersPage(),
  );
}

class MapLayersPage extends StatefulWidget {
  const new({super.key});

  @override
  State<MapLayersPage> createState() => _MapLayersPageState();
}

class _MapLayersPageState extends State<MapLayersPage> {
  static const _heatmapCamera = CameraPosition(
    target: LatLng(40, -120),
    zoom: 3,
  );
  static const _hillshadeCamera = CameraPosition(
    target: LatLng(47.274, 11.491),
    zoom: 10,
  );

  late var _style = loadMapLayersStyle();
  MapLibreMapController? _controller;
  var _demo = _LayerDemo.heatmap;
  var _settings = const HeatmapSettings();
  var _appliedSettings = const HeatmapSettings();
  var _hillshadeSettings = const HillshadeSettings();
  var _appliedHillshadeSettings = const HillshadeSettings();
  var _styleLoaded = false;
  var _controlsOpen = false;
  var _busy = false;
  String? _error;

  CameraPosition get _initialCamera =>
      _demo == _LayerDemo.heatmap ? _heatmapCamera : _hillshadeCamera;

  Future<void> _selectDemo(_LayerDemo demo) async {
    final controller = _controller;
    if (controller == null || !_styleLoaded || _busy || demo == _demo) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await controller.setLayerVisibility(
        heatmapLayerId,
        demo == _LayerDemo.heatmap && _settings.visible,
      );
      await controller.setLayerVisibility(
        pointLayerId,
        demo == _LayerDemo.heatmap && _settings.pointsVisible,
      );
      await controller.setLayerVisibility(
        hillshadeLayerId,
        demo == _LayerDemo.hillshade && _hillshadeSettings.visible,
      );
      await controller.moveCamera(
        CameraUpdate.newCameraPosition(
          demo == _LayerDemo.heatmap ? _heatmapCamera : _hillshadeCamera,
        ),
      );
      if (!mounted) return;
      setState(() => _demo = demo);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not switch the layer: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyHillshade(HillshadeSettings settings) async {
    final controller = _controller;
    if (controller == null || !_styleLoaded || _busy) return;
    setState(() {
      _hillshadeSettings = settings;
      _busy = true;
      _error = null;
    });
    try {
      await controller.setLayerProperties(
        hillshadeLayerId,
        settings.properties,
      );
      _appliedHillshadeSettings = settings;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _hillshadeSettings = _appliedHillshadeSettings;
        _error = 'Could not update the layer: $error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(HeatmapSettings settings) async {
    final controller = _controller;
    if (controller == null || !_styleLoaded || _busy) return;
    setState(() {
      _settings = settings;
      _busy = true;
      _error = null;
    });
    try {
      await controller.setLayerProperties(heatmapLayerId, settings.properties);
      await controller.setLayerVisibility(pointLayerId, settings.pointsVisible);
      _appliedSettings = settings;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _settings = _appliedSettings;
        _error = 'Could not update the layer: $error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retry() => setState(() {
    _controller = null;
    _styleLoaded = false;
    _demo = _LayerDemo.heatmap;
    _settings = const HeatmapSettings();
    _appliedSettings = _settings;
    _hillshadeSettings = const HillshadeSettings();
    _appliedHillshadeSettings = _hillshadeSettings;
    _error = null;
    _style = loadMapLayersStyle();
  });

  @override
  Widget build(context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: .start,
        children: [
          const Text('Map layers', overflow: .ellipsis),
          Text(
            _demo == _LayerDemo.heatmap
                ? 'Heatmap · Historical earthquakes'
                : 'Hillshade · Alpine elevation',
            maxLines: 1,
            overflow: .ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: .normal),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Reset view',
          onPressed: _styleLoaded && !_busy
              ? () => unawaited(
                  _controller?.animateCamera(
                    CameraUpdate.newCameraPosition(_initialCamera),
                  ),
                )
              : null,
          icon: const Icon(Icons.public),
        ),
        IconButton(
          tooltip: 'Layer controls',
          isSelected: _controlsOpen,
          onPressed: _styleLoaded
              ? () => setState(() => _controlsOpen = !_controlsOpen)
              : null,
          icon: const Icon(Icons.tune),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: FutureBuilder(
      future: _style,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Column(
              mainAxisSize: .min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading basemap and earthquake sample…'),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: .min,
                children: [
                  const Text('Could not load the map or earthquake data.'),
                  const SizedBox(height: 8),
                  Text('${snapshot.error}', textAlign: .center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        final data = snapshot.requireData;
        final map = MapLibreMap(
          styleString: data.style,
          initialCameraPosition: _initialCamera,
          onMapCreated: (controller) => _controller = controller,
          onStyleLoadedCallback: () => setState(() => _styleLoaded = true),
          scaleControlEnabled: true,
        );
        final controls = SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              SegmentedButton<_LayerDemo>(
                segments: const [
                  ButtonSegment(
                    value: _LayerDemo.heatmap,
                    label: Text('Heatmap'),
                  ),
                  ButtonSegment(
                    value: _LayerDemo.hillshade,
                    label: Text('Hillshade'),
                  ),
                ],
                selected: {_demo},
                showSelectedIcon: false,
                onSelectionChanged: _styleLoaded && !_busy
                    ? (value) => unawaited(_selectDemo(value.single))
                    : null,
              ),
              const SizedBox(height: 16),
              if (_demo == _LayerDemo.heatmap)
                HeatmapControls(
                  settings: _settings,
                  enabled: _styleLoaded && !_busy,
                  onChanged: (settings) => setState(() => _settings = settings),
                  onCommitted: (settings) => unawaited(_apply(settings)),
                )
              else
                HillshadeControls(
                  settings: _hillshadeSettings,
                  enabled: _styleLoaded && !_busy,
                  onChanged: (settings) =>
                      setState(() => _hillshadeSettings = settings),
                  onCommitted: (settings) =>
                      unawaited(_applyHillshade(settings)),
                ),
              const SizedBox(height: 20),
              Text(
                _demo == _LayerDemo.heatmap
                    ? '${data.pointCount} earthquakes · Historical USGS sample'
                    : 'Elevation sample · AW3D30 (JAXA)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        );

        return Stack(
          children: [
            Positioned.fill(child: map),
            if (_controlsOpen)
              Positioned.fill(
                child: _LayerControlsPanel(
                  title: 'Layers',
                  onClose: () => setState(() => _controlsOpen = false),
                  child: controls,
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _LayerControlsPanel extends StatelessWidget {
  const new({required this.title, required this.onClose, required this.child});

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(context) => SafeArea(
    minimum: const EdgeInsets.all(12),
    child: LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: .topRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(320, constraints.maxWidth),
            maxHeight: constraints.maxHeight * 0.7,
          ),
          child: Card(
            margin: .zero,
            child: Column(
              mainAxisSize: .min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20, right: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close layer controls',
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
