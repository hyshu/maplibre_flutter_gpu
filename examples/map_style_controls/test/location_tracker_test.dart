import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_flutter_map_style_controls_example/location_tracker.dart';

void main() {
  late _FakeLocationSource source;
  late LocationTracker tracker;

  setUp(() {
    source = _FakeLocationSource();
    tracker = LocationTracker(source: source);
  });

  tearDown(() async {
    tracker.dispose();
    await source.close();
  });

  test('stays idle until explicitly enabled', () {
    expect(tracker.status, LocationStatus.idle);
    expect(tracker.position, isNull);
    expect(source.permissionChecks, 0);
    expect(source.positionSubscriptions, 0);
  });

  test('does not request permission when location services are off', () async {
    source.serviceEnabled = false;
    await tracker.enable();
    expect(tracker.status, LocationStatus.serviceDisabled);
    expect(source.permissionRequests, 0);
    expect(source.positionSubscriptions, 0);
  });

  test('reports denied and permanently denied permissions', () async {
    source.permission = LocationPermission.denied;
    source.requestResult = LocationPermission.denied;
    await tracker.enable();
    expect(tracker.status, LocationStatus.permissionDenied);
    expect(source.permissionRequests, 1);
    source.permission = LocationPermission.deniedForever;
    await tracker.enable();
    expect(tracker.status, LocationStatus.permissionDeniedForever);
    expect(source.permissionRequests, 1);
    expect(source.positionSubscriptions, 0);
  });

  test(
    'coalesces fixes and rejects out-of-order or invalid coordinates',
    () async {
      await tracker.enable();
      final first = _position(1);
      final latest = _position(3);
      source.fixes.add(first);
      source.fixes.add(latest);
      source.fixes.add(_position(2));
      source.fixes.add(_position(4, latitude: double.nan));
      source.fixes.add(_position(5, latitude: 100));
      expect(tracker.position, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(tracker.status, LocationStatus.active);
      expect(tracker.position, same(latest));
    },
  );

  test(
    'pause cancels pending delivery and resume creates one subscription',
    () async {
      await tracker.enable();
      source.fixes.add(_position(1));
      tracker.pause();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(tracker.status, LocationStatus.paused);
      expect(tracker.position, isNull);
      expect(source.positionCancellations, 1);
      await tracker.resume();
      expect(source.positionSubscriptions, 2);
      await tracker.resume();
      expect(source.positionSubscriptions, 2);
      source.fixes.add(_position(2));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(tracker.position?.latitude, 2);
    },
  );

  test('resume rechecks permission without prompting', () async {
    await tracker.enable();
    tracker.pause();
    source.permission = LocationPermission.denied;
    await tracker.resume();
    expect(tracker.status, LocationStatus.permissionDenied);
    expect(source.permissionRequests, 0);
    expect(source.positionSubscriptions, 1);
  });

  test(
    'disabled service clears visible location and stops subscriptions',
    () async {
      await tracker.enable();
      source.fixes.add(_position(1));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      source.services.add(ServiceStatus.disabled);
      await Future<void>.delayed(Duration.zero);
      expect(tracker.status, LocationStatus.serviceDisabled);
      expect(tracker.position, isNull);
      expect(source.positionCancellations, 1);
    },
  );

  test('stream failures clear location and allow an explicit retry', () async {
    await tracker.enable();
    source.fixes.add(_position(1));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    source.fixes.addError(const PermissionDeniedException('Revoked'));
    await Future<void>.delayed(Duration.zero);
    expect(tracker.status, LocationStatus.permissionDenied);
    expect(tracker.position, isNull);
    await tracker.enable();
    expect(tracker.status, LocationStatus.waiting);
    expect(source.positionSubscriptions, 2);
  });

  test('initial fix timeout stops the provider', () async {
    tracker.dispose();
    tracker = LocationTracker(
      source: source,
      initialFixTimeout: const Duration(milliseconds: 20),
    );
    await tracker.enable();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(tracker.status, LocationStatus.failed);
    await Future<void>.delayed(Duration.zero);
    expect(source.positionCancellations, 1);
  });

  test('a stopped permission request cannot start a subscription', () async {
    source.permission = LocationPermission.denied;
    final permission = source.pendingPermission = Completer();
    final starting = tracker.enable();
    await Future<void>.delayed(Duration.zero);
    tracker.disable();
    permission.complete(LocationPermission.whileInUse);
    await starting;
    expect(tracker.status, LocationStatus.idle);
    expect(source.positionSubscriptions, 0);
  });

  test('dispose discards an unfinished permission response', () async {
    source.permission = LocationPermission.denied;
    final permission = source.pendingPermission = Completer();
    final disposedTracker = LocationTracker(source: source);
    final starting = disposedTracker.enable();
    await Future<void>.delayed(Duration.zero);
    disposedTracker.dispose();
    permission.complete(LocationPermission.whileInUse);
    await starting;
    expect(source.positionSubscriptions, 0);
  });

  test('dispose releases an active location subscription', () async {
    final disposedTracker = LocationTracker(source: source);
    await disposedTracker.enable();
    disposedTracker.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(source.positionCancellations, 1);
  });

  test('resume shares an unfinished permission prompt', () async {
    source.permission = LocationPermission.denied;
    final permission = source.pendingPermission = Completer();
    final starting = tracker.enable();
    await Future<void>.delayed(Duration.zero);
    tracker.pause();
    final resuming = tracker.resume();
    await Future<void>.delayed(Duration.zero);
    permission.complete(LocationPermission.whileInUse);
    await Future.wait([starting, resuming]);
    expect(source.permissionRequests, 1);
    expect(source.positionSubscriptions, 1);
    expect(tracker.status, LocationStatus.waiting);
  });
}

Position _position(int second, {double? latitude}) => Position(
  longitude: 139,
  latitude: latitude ?? second.toDouble(),
  timestamp: DateTime.utc(2026, 10, 7, 0, 0, second),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 5,
  speed: 1,
  speedAccuracy: 0,
);

class _FakeLocationSource implements LocationSource {
  _FakeLocationSource() {
    fixes = StreamController<Position>.broadcast(
      sync: true,
      onListen: () => positionSubscriptions++,
      onCancel: () => positionCancellations++,
    );
  }

  late final StreamController<Position> fixes;
  final services = StreamController<ServiceStatus>.broadcast(sync: true);
  var serviceEnabled = true;
  var permission = LocationPermission.whileInUse;
  var requestResult = LocationPermission.whileInUse;
  Completer<LocationPermission>? pendingPermission;
  var permissionChecks = 0;
  var permissionRequests = 0;
  var positionSubscriptions = 0;
  var positionCancellations = 0;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async {
    permissionChecks++;

    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;

    return pendingPermission?.future ?? requestResult;
  }

  @override
  Stream<Position> positions() => fixes.stream;

  @override
  Stream<ServiceStatus> serviceChanges() => services.stream;

  Future<void> close() async {
    await fixes.close();
    await services.close();
  }
}
