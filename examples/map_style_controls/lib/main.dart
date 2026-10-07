import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'location_tracker.dart';
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

class _MapStyleControlsPageState extends State<MapStyleControlsPage>
    with WidgetsBindingObserver {
  final _location = LocationTracker();
  MapLibreMapController? _controller;
  Position? _pendingCameraPosition;
  var _following = false;
  var _movingCamera = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _location.addListener(_onLocationChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_location.resume());
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pendingCameraPosition = null;
      _location.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _location.removeListener(_onLocationChanged);
    _location.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    if (!mounted) return;
    setState(() {
      if (_location.position == null) {
        _pendingCameraPosition = null;
        if (_location.status != LocationStatus.checking &&
            _location.status != LocationStatus.waiting &&
            _location.status != LocationStatus.paused) {
          _following = false;
        }
      }
    });
    if (_location.position case final position? when _following) {
      _queueCamera(position);
    }
  }

  void _locate() {
    setState(() => _following = true);
    final position = _location.position;
    if (position != null) {
      _queueCamera(position);
    } else {
      unawaited(_location.enable());
    }
  }

  void _stopFollowing() {
    if (!_following) return;
    _pendingCameraPosition = null;
    setState(() => _following = false);
  }

  void _stopLocation() {
    _stopFollowing();
    _location.disable();
  }

  void _toggleLocation(bool enabled) {
    if (enabled) {
      unawaited(_location.enable());
    } else {
      _stopLocation();
    }
  }

  void _queueCamera(Position position) {
    _pendingCameraPosition = position;
    if (!_movingCamera) unawaited(_moveCameraToLocation());
  }

  Future<void> _moveCameraToLocation() async {
    _movingCamera = true;
    try {
      while (mounted && _following && _pendingCameraPosition != null) {
        final controller = _controller;
        if (controller == null) return;
        final position = _pendingCameraPosition!;
        _pendingCameraPosition = null;
        final currentZoom = controller.cameraPosition?.zoom ?? 15.2;
        await controller.moveCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            currentZoom < 14 ? 14 : currentZoom,
          ),
        );
      }
    } catch (_) {
      if (mounted) _stopFollowing();
    } finally {
      _movingCamera = false;
    }
  }

  Future<void> _openLocationSettings() async {
    try {
      final opened = _location.status == LocationStatus.serviceDisabled
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
      if (!opened && mounted) _showSettingsMessage();
    } catch (_) {
      if (mounted) _showSettingsMessage();
    }
  }

  void _showSettingsMessage() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Open system settings to allow location access.'),
    ),
  );

  MapUserLocation? get _userLocation {
    final position = _location.position;
    if (position == null) return null;
    final hasCourse =
        position.speed.isFinite &&
        position.speed > 0.5 &&
        position.heading.isFinite &&
        position.heading >= 0 &&
        position.heading < 360 &&
        position.headingAccuracy.isFinite &&
        position.headingAccuracy >= 0 &&
        position.headingAccuracy <= 45;

    return MapUserLocation(
      position: LatLng(position.latitude, position.longitude),
      headingDegrees: hasCourse ? position.heading : null,
      accuracyMeters: position.accuracy.isFinite && position.accuracy >= 0
          ? position.accuracy
          : null,
    );
  }

  String get _locationStatusText => switch (_location.status) {
    LocationStatus.idle => 'Show current location',
    LocationStatus.checking => 'Checking location access…',
    LocationStatus.waiting => 'Finding your location…',
    LocationStatus.active =>
      _following ? 'Following your location' : 'Location visible',
    LocationStatus.paused => 'Location paused',
    LocationStatus.serviceDisabled => 'Location services are off',
    LocationStatus.permissionDenied => 'Location permission denied',
    LocationStatus.permissionDeniedForever =>
      'Allow location in system settings',
    LocationStatus.failed => 'Could not find location. Try again.',
  };

  bool get _locationBusy =>
      _location.status == LocationStatus.checking ||
      _location.status == LocationStatus.waiting;

  bool get _locationNeedsSettings =>
      _location.status == LocationStatus.serviceDisabled ||
      _location.status == LocationStatus.permissionDeniedForever;

  bool get _locationNeedsRetry =>
      _locationNeedsSettings ||
      _location.status == LocationStatus.permissionDenied ||
      _location.status == LocationStatus.failed;

  StyleLayerCatalog? _catalog;
  final _visible = {for (final group in StyleLayerGroup.values) group: true};
  final _busy = <StyleLayerGroup>{};
  String? _error;
  var _styleDidLoad = false;

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    if (_location.position case final position? when _following) {
      _queueCamera(position);
    }
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
        preferredSize: Size.fromHeight(
          56 + (_location.enabled ? 40 : 0) + (_error == null ? 0 : 32),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              SingleChildScrollView(
                scrollDirection: .horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      avatar: _locationBusy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location, size: 18),
                      label: const Text('Current location'),
                      selected: _location.enabled,
                      onSelected: _toggleLocation,
                      tooltip: 'Show or hide your current location',
                    ),
                    if (_location.enabled) ...[
                      const SizedBox(width: 8),
                      FilterChip(
                        avatar: const Icon(Icons.gps_fixed, size: 18),
                        label: const Text('Follow location'),
                        selected: _following,
                        onSelected: !_following && _location.position == null
                            ? null
                            : (selected) {
                                if (selected) {
                                  _locate();
                                } else {
                                  _stopFollowing();
                                }
                              },
                        tooltip: 'Keep the map centered on your location',
                      ),
                    ],
                    const SizedBox(width: 8),
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
              if (_location.enabled)
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _locationStatusText,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (_locationNeedsSettings)
                        TextButton(
                          onPressed: () => unawaited(_openLocationSettings()),
                          child: const Text('Settings'),
                        ),
                      if (_locationNeedsRetry)
                        TextButton(
                          onPressed: () => unawaited(_location.enable()),
                          child: const Text('Retry'),
                        ),
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
    body: Stack(
      children: [
        Listener(
          onPointerMove: (event) {
            if (event.delta.distanceSquared > 0) _stopFollowing();
          },
          onPointerSignal: (_) => _stopFollowing(),
          onPointerPanZoomStart: (_) => _stopFollowing(),
          child: MapLibreMap(
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
            userLocation: _userLocation,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 72,
          child: FloatingActionButton.small(
            heroTag: 'current-location',
            tooltip: _following
                ? 'Following current location'
                : 'Follow current location',
            onPressed: _locationBusy ? null : _locate,
            child: _locationBusy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _following ? Icons.my_location : Icons.location_searching,
                  ),
          ),
        ),
      ],
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
