import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'style_layer_groups.dart';

void main() => runApp(const MapStyleControlsApp());

class MapStyleControlsApp extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(context) => MaterialApp(
    title: 'Map Style Controls',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b5b)),
      useMaterial3: true,
    ),
    home: const MapStyleControlsPage(),
  );
}

class MapStyleControlsPage extends StatefulWidget {
  const new({super.key});

  @override
  State<MapStyleControlsPage> createState() => _MapStyleControlsPageState();
}

class _MapStyleControlsPageState extends State<MapStyleControlsPage> {
  MapLibreMapController? _controller;
  StyleLayerCatalog? _catalog;
  final _visible = {for (final group in StyleLayerGroup.values) group: true};
  final _busy = <StyleLayerGroup>{};
  String? _error;
  var _styleDidLoad = false;

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    if (_styleDidLoad) unawaited(_loadSemanticGroups());
  }

  void _onStyleLoaded() {
    _styleDidLoad = true;
    unawaited(_loadSemanticGroups());
  }

  Future<void> _loadSemanticGroups() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final style = await controller.getStyle();
      if (style == null) throw StateError('The map style is unavailable');
      final catalog = StyleLayerCatalog.fromStyle(style);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not prepare display controls: $error');
    }
  }

  Future<void> _toggleGroup(StyleLayerGroup group) async {
    final controller = _controller;
    final catalog = _catalog;
    if (controller == null || catalog == null || _busy.contains(group)) return;
    final layerIds = catalog[group];
    if (layerIds.isEmpty) return;

    final next = !_visible[group]!;
    setState(() {
      _busy.add(group);
      _error = null;
    });
    try {
      for (final layerId in layerIds) {
        await controller.setLayerVisibility(layerId, next);
      }
      if (!mounted) return;
      setState(() => _visible[group] = next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not change map display: $error');
    } finally {
      if (mounted) setState(() => _busy.remove(group));
    }
  }

  @override
  Widget build(context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: .start,
        children: [
          const Text('Map display', overflow: .ellipsis),
          Text(
            _catalog == null
                ? 'Loading map style…'
                : 'Choose what appears on the map',
            maxLines: 1,
            overflow: .ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: .normal),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(_error == null ? 56 : 88),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              SingleChildScrollView(
                scrollDirection: .horizontal,
                child: Row(
                  children: [
                    for (final descriptor in _descriptors) ...[
                      _StyleToggleChip(
                        descriptor: descriptor,
                        selected: _visible[descriptor.group] ?? false,
                        enabled:
                            _catalog != null &&
                            _catalog![descriptor.group].isNotEmpty &&
                            !_busy.contains(descriptor.group),
                        busy: _busy.contains(descriptor.group),
                        onSelected: () =>
                            unawaited(_toggleGroup(descriptor.group)),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 4),
                Text(
                  error,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    body: MapLibreMap(
      styleString: MapLibreStyles.openfreemapLiberty,
      initialCameraPosition: const CameraPosition(
        target: LatLng(35.6814, 139.7667),
        zoom: 15.2,
        tilt: 50,
        bearing: -18,
      ),
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      scaleControlEnabled: true,
    ),
  );
}

class _StyleToggleChip extends StatelessWidget {
  const new({
    required this.descriptor,
    required this.selected,
    required this.enabled,
    required this.busy,
    required this.onSelected,
  });

  final _GroupDescriptor descriptor;
  final bool selected;
  final bool enabled;
  final bool busy;
  final VoidCallback onSelected;

  @override
  Widget build(context) => FilterChip(
    avatar: busy
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(descriptor.icon, size: 18),
    label: Text(descriptor.label),
    selected: selected,
    onSelected: enabled ? (_) => onSelected() : null,
    tooltip: 'Show or hide ${descriptor.label.toLowerCase()}',
  );
}

class _GroupDescriptor {
  const new(this.group, this.label, this.icon);

  final StyleLayerGroup group;
  final String label;
  final IconData icon;
}

const _descriptors = [
  _GroupDescriptor(.buildings3d, '3D buildings', Icons.apartment),
  _GroupDescriptor(.labels, 'Labels', Icons.label_outline),
  _GroupDescriptor(.symbols, 'Places & symbols', Icons.place_outlined),
  _GroupDescriptor(.roads, 'Roads', Icons.add_road),
  _GroupDescriptor(.water, 'Water', Icons.water_outlined),
];
