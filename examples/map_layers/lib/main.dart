import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'heatmap_controls.dart';
import 'heatmap_style.dart';

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
  static const _initialCamera = CameraPosition(
    target: LatLng(40, -120),
    zoom: 3,
  );

  late Future<({String style, int pointCount})> _style = loadHeatmapStyle();
  MapLibreMapController? _controller;
  var _settings = const HeatmapSettings();
  var _appliedSettings = const HeatmapSettings();
  var _styleLoaded = false;
  var _controlsOpen = false;
  var _busy = false;
  String? _error;

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

  void _retry() {
    setState(() {
      _controller = null;
      _styleLoaded = false;
      _settings = const HeatmapSettings();
      _appliedSettings = _settings;
      _error = null;
      _style = loadHeatmapStyle();
    });
  }

  @override
  Widget build(context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: .start,
        children: [
          Text('Map layers', overflow: .ellipsis),
          Text(
            'Heatmap · Historical earthquakes',
            maxLines: 1,
            overflow: .ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: .normal),
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
              HeatmapControls(
                settings: _settings,
                enabled: _styleLoaded && !_busy,
                onChanged: (settings) => setState(() => _settings = settings),
                onCommitted: (settings) => unawaited(_apply(settings)),
              ),
              const SizedBox(height: 20),
              Text(
                '${data.pointCount} earthquakes · Historical USGS sample',
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
                  title: 'Heatmap',
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
