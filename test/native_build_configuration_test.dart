import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owner-thread coordinate projection is not a leaf FFI call', () {
    final bridge = File('lib/src/native/maplibre_ffi.dart').readAsStringSync();
    final lookup = bridge.indexOf(
      "_latLonToScreen = _lib.lookupFunction<LatLonToScreenN, LatLonToScreenD>",
    );
    expect(lookup, greaterThanOrEqualTo(0));
    expect(
      bridge.substring(lookup, bridge.indexOf(');', lookup) + 2),
      isNot(contains('isLeaf: true')),
    );
  });

  test(
    'native frame publication transfers command ownership without copying',
    () {
      final bridge = File('native/src/maplibre_bridge.cpp').readAsStringSync();
      expect(bridge, contains('g_snapshot.swap(fd.commands);'));
      expect(bridge, isNot(contains('g_snapshot = fd.commands;')));
    },
  );

  test('symbol anchors use one native batch projection call', () {
    final bridge = File('native/src/maplibre_bridge.cpp').readAsStringSync();
    final dart = File('lib/src/native/maplibre_ffi.dart').readAsStringSync();
    expect(bridge, contains('maplibre_project_coordinates('));
    expect(dart, contains("'maplibre_project_coordinates'"));
    final lookup = dart.indexOf("'maplibre_project_coordinates'");
    expect(
      dart.substring(lookup, dart.indexOf(');', lookup) + 2),
      isNot(contains('isLeaf: true')),
    );
  });

  test('owner teardown waits for an acquired frame lease', () {
    final bridge = File('native/src/maplibre_bridge.cpp').readAsStringSync();
    expect(bridge, contains('g_asyncFrame.leaseReleased.wait('));

    final releaseStart = bridge.indexOf(
      'MAPLIBRE_API void maplibre_frame_release',
    );
    final releaseEnd = bridge.indexOf(
      'MAPLIBRE_API void maplibre_set_camera',
      releaseStart,
    );
    final release = bridge.substring(releaseStart, releaseEnd);
    expect(release, contains('g_asyncFrame.leaseReleased.notify_all();'));
    expect(
      release.indexOf('leaseReleased.notify_all()'),
      lessThan(release.indexOf('if (!ownerActive) return;')),
    );
  });

  test('Android session activation is published by the owner init task', () {
    final bridge = File('native/src/maplibre_bridge.cpp').readAsStringSync();
    final initStart = bridge.indexOf('MAPLIBRE_API int maplibre_init');
    final initEnd = bridge.indexOf(
      'MAPLIBRE_API int maplibre_is_idle',
      initStart,
    );
    final init = bridge.substring(initStart, initEnd);
    final ownerTaskStart = init.indexOf('bridge_runOnOwnerSync([&] {');
    final ownerTaskEnd = init.indexOf('\n        });', ownerTaskStart);
    final ownerTask = init.substring(ownerTaskStart, ownerTaskEnd);
    expect(
      ownerTask,
      contains('g_sessionActive.store(true, std::memory_order_release);'),
    );
  });

  test('dropped owner tasks break synchronous waiters', () {
    final state = File('native/src/bridge_state.hpp').readAsStringSync();
    final post = state.indexOf('if (!bridge_postOwnerTask(');
    final wait = state.indexOf('result.get();', post);
    final reset = state.indexOf('task.reset();', post);
    expect(post, greaterThanOrEqualTo(0));
    expect(reset, greaterThan(post));
    expect(reset, lessThan(wait));
  });

  test('all native targets use the shared owner runtime', () {
    final sharedSources = File(
      'native/cmake/bridge_sources.cmake',
    ).readAsStringSync();
    expect(sharedSources, contains('src/bridge_owner_thread.cpp'));

    const cmakeBuildFiles = <String>['native/platforms/android/CMakeLists.txt'];
    for (final path in cmakeBuildFiles) {
      expect(
        File(path).readAsStringSync(),
        contains('MAPLIBRE_FLUTTERGPU_BRIDGE_SOURCES'),
        reason: '$path must compile the shared bridge source manifest',
      );
    }

    const darwinBuildManifest = 'native/scripts/packaging/darwin_common.sh';
    expect(
      File(darwinBuildManifest).readAsStringSync(),
      contains('bridge_owner_thread.cpp'),
      reason: '$darwinBuildManifest must compile the shared owner runtime',
    );

    final runtime = File(
      'native/src/bridge_owner_thread.cpp',
    ).readAsStringSync();
    expect(runtime, contains('std::unordered_set<void*> sessions;'));
    expect(runtime, contains('sessions.insert(session);'));
    expect(runtime, contains('sessions.erase(session);'));
    expect(runtime, contains('g_run_loop->run();'));
  });

  test('macOS stops the native runtime before process teardown', () {
    final plugin = File(
      'darwin/maplibre_flutter_gpu/Sources/maplibre_flutter_gpu/'
      'MaplibreFlutterGpuPlugin.swift',
    ).readAsStringSync();
    final runtime = File(
      'native/src/bridge_owner_thread.cpp',
    ).readAsStringSync();
    expect(plugin, contains('NSApplication.willTerminateNotification'));
    expect(plugin, contains('maplibre_shutdown_all()'));
    expect(runtime, contains('void bridge_shutdownOwnerRuntime()'));
    expect(runtime, contains('worker.join();'));
  });

  test('Android reuses one process DSO for every map session', () {
    final plugin = File(
      'android/src/main/java/dev/maplibre/fluttergpu/'
      'MaplibreFlutterGpuPlugin.java',
    ).readAsStringSync();
    expect(plugin, contains('System.loadLibrary("maplibre_bridge")'));
    expect(plugin, isNot(contains('System.nanoTime()')));
    expect(plugin, isNot(contains('StandardCopyOption')));
    expect(plugin, isNot(contains('libmaplibre_bridge_session_')));
  });

  test('native session handles are checked before selection and release', () {
    final bridge = File('native/src/maplibre_bridge.cpp').readAsStringSync();
    expect(
      bridge,
      contains('g_sessionRegistry.contains(candidate) ? candidate'),
    );
    expect(bridge, contains('g_sessionRegistry.erase(owned);'));
  });

  test('Apple bridge builds match the Release MapLibre ABI', () {
    final scripts = <String, String>{
      'native/scripts/build_macos.sh': '-DCMAKE_BUILD_TYPE=Release',
      'native/scripts/build_ios.sh': '--config Release',
    };

    for (final MapEntry(key: path, value: coreReleaseMarker)
        in scripts.entries) {
      final script = File(path).readAsStringSync();
      expect(
        script,
        contains(coreReleaseMarker),
        reason: '$path must link against a Release mbgl-core build',
      );
    }

    const commonPath = 'native/scripts/packaging/darwin_common.sh';
    expect(
      File(commonPath).readAsStringSync(),
      contains('-DNDEBUG'),
      reason:
          '$commonPath must use the same NDEBUG class layouts as mbgl-core '
          'Release',
    );
  });
}
