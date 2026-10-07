import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// The foreground location states presented by the sample.
enum LocationStatus {
  idle,
  checking,
  waiting,
  active,
  paused,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  failed,
}

/// Supplies location services without owning the sample's tracking lifecycle.
abstract interface class LocationSource {
  /// Whether the system currently allows location services.
  Future<bool> isServiceEnabled();

  /// Reads authorization without displaying a permission prompt.
  Future<LocationPermission> checkPermission();

  /// Requests authorization in response to an explicit user action.
  Future<LocationPermission> requestPermission();

  /// Supplies position fixes until the subscription is cancelled.
  Stream<Position> positions();

  /// Reports changes to the system location service.
  Stream<ServiceStatus> serviceChanges();
}

/// Reads foreground GPS fixes using the platform's location provider.
class DeviceLocationSource implements LocationSource {
  const DeviceLocationSource();

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Stream<Position> positions() => Geolocator.getPositionStream(
    locationSettings:
        defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            allowBackgroundLocationUpdates: false,
            showBackgroundLocationIndicator: false,
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
  );

  @override
  Stream<ServiceStatus> serviceChanges() => Geolocator.getServiceStatusStream();
}

/// Owns foreground subscriptions and ignores results from cancelled requests.
///
/// Tracking starts only through [enable]. Resuming checks existing permission
/// without opening another permission prompt. [dispose] releases subscriptions.
class LocationTracker extends ChangeNotifier {
  LocationTracker({
    this.source = const DeviceLocationSource(),
    this.initialFixTimeout = const Duration(seconds: 30),
  });

  /// The maximum wait for the first valid fix after starting a subscription.
  final Duration initialFixTimeout;

  /// The provider whose subscriptions are owned by this tracker.
  final LocationSource source;
  StreamSubscription<Position>? _positions;
  StreamSubscription<ServiceStatus>? _services;
  Future<void> _cancelling = Future<void>.value();
  Future<LocationPermission>? _permissionRequest;
  Timer? _delivery;
  Timer? _firstFixTimeout;
  Position? _pending;
  DateTime? _latestTime;
  var _generation = 0;
  var _foreground = true;
  var _disposed = false;
  var _enabled = false;
  var _status = LocationStatus.idle;
  Position? _position;

  /// Whether the user has enabled tracking, including while paused.
  bool get enabled => _enabled;

  /// The current acquisition or error state.
  LocationStatus get status => _status;

  /// The latest valid fix, or null while inactive or unable to locate the user.
  Position? get position => _position;

  /// Starts or retries tracking and requests permission when needed.
  Future<void> enable() async {
    _enabled = true;
    await _start(requestPermission: true);
  }

  /// Stops tracking until the next explicit [enable] call.
  void disable() {
    _enabled = false;
    _stop(LocationStatus.idle);
  }

  /// Releases platform subscriptions while the app is hidden or paused.
  void pause() {
    _foreground = false;
    if (_enabled) _stop(LocationStatus.paused);
  }

  /// Restarts an enabled tracker without requesting additional permission.
  Future<void> resume() async {
    if (_foreground) return;
    _foreground = true;
    if (_enabled) await _start(requestPermission: false);
  }

  bool _isCurrent(int generation) =>
      !_disposed && _enabled && _foreground && generation == _generation;

  Future<void> _start({required bool requestPermission}) async {
    if (_disposed || !_foreground) return;
    final generation = ++_generation;
    _cancelSubscriptions();
    _position = null;
    _status = LocationStatus.checking;
    notifyListeners();
    try {
      await _cancelling;
      if (!_isCurrent(generation)) return;
      final serviceEnabled = await source.isServiceEnabled();
      if (!_isCurrent(generation)) return;
      if (!serviceEnabled) {
        _stop(LocationStatus.serviceDisabled);

        return;
      }
      var permission = await source.checkPermission();
      if (!_isCurrent(generation)) return;
      if (_permissionRequest != null ||
          (permission == LocationPermission.denied && requestPermission)) {
        final request = _permissionRequest ??= source.requestPermission();
        try {
          permission = await request;
        } finally {
          if (identical(_permissionRequest, request)) _permissionRequest = null;
        }
      }
      if (!_isCurrent(generation)) return;
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        _stop(
          permission == LocationPermission.deniedForever
              ? LocationStatus.permissionDeniedForever
              : LocationStatus.permissionDenied,
        );

        return;
      }
      _status = LocationStatus.waiting;
      _firstFixTimeout = Timer(initialFixTimeout, () {
        if (_isCurrent(generation)) _stop(LocationStatus.failed);
      });
      _services = source.serviceChanges().listen(
        (service) {
          if (_isCurrent(generation) && service == ServiceStatus.disabled) {
            _stop(LocationStatus.serviceDisabled);
          }
        },
        onError: (Object error) {
          if (_isCurrent(generation)) _handleError(error);
        },
      );
      _positions = source.positions().listen(
        (position) => _acceptPosition(position, generation),
        onError: (Object error) {
          if (_isCurrent(generation)) _handleError(error);
        },
        onDone: () {
          if (_isCurrent(generation)) _stop(LocationStatus.failed);
        },
      );
      notifyListeners();
    } catch (error) {
      if (_isCurrent(generation)) _handleError(error);
    }
  }

  void _acceptPosition(Position position, int generation) {
    if (!_isCurrent(generation) ||
        !position.latitude.isFinite ||
        !position.longitude.isFinite ||
        position.latitude.abs() > 90 ||
        position.longitude.abs() > 180 ||
        (_latestTime != null && position.timestamp.isBefore(_latestTime!))) {
      return;
    }
    _latestTime = position.timestamp;
    _pending = position;
    _firstFixTimeout?.cancel();
    _firstFixTimeout = null;
    _delivery ??= Timer(const Duration(milliseconds: 100), () {
      _delivery = null;
      if (!_isCurrent(generation)) return;
      _position = _pending;
      _pending = null;
      _status = LocationStatus.active;
      notifyListeners();
    });
  }

  void _handleError(Object error) => _stop(switch (error) {
    LocationServiceDisabledException() => LocationStatus.serviceDisabled,
    PermissionDeniedException() => LocationStatus.permissionDenied,
    _ => LocationStatus.failed,
  });

  void _stop(LocationStatus status) {
    ++_generation;
    _cancelSubscriptions();
    _position = null;
    _status = status;
    if (!_disposed) notifyListeners();
  }

  void _cancelSubscriptions() {
    _delivery?.cancel();
    _delivery = null;
    _firstFixTimeout?.cancel();
    _firstFixTimeout = null;
    _pending = null;
    final positions = _positions;
    final services = _services;
    _positions = null;
    _services = null;
    _cancelling = _cancelling
        .then((_) async {
          try {
            await positions?.cancel();
          } finally {
            await services?.cancel();
          }
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _cancelSubscriptions();
    super.dispose();
  }
}
