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

  test('wrapped projection converts native y coordinates to screen space', () {
    final bridge = File('native/src/maplibre_bridge.cpp').readAsStringSync();
    final projectionStart = bridge.indexOf(
      'MAPLIBRE_API void maplibre_project_wrapped_coordinates',
    );
    final projectionEnd = bridge.indexOf(
      'MAPLIBRE_API void maplibre_screen_to_lat_lon',
      projectionStart,
    );
    expect(projectionStart, greaterThanOrEqualTo(0));
    expect(projectionEnd, greaterThan(projectionStart));
    expect(
      bridge.substring(projectionStart, projectionEnd),
      contains('state.getSize().height - screen.y'),
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
    final sharedSources = File('native/cmake/bridge_sources.cmake')
        .readAsStringSync();
    expect(sharedSources, contains('src/bridge_owner_thread.cpp'));

    const cmakeBuildFiles = <String>[
      'native/platforms/android/CMakeLists.txt',
      'native/platforms/linux/CMakeLists.txt',
      'native/platforms/windows/CMakeLists.txt',
    ];
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

    final runtime = File('native/src/bridge_owner_thread.cpp')
        .readAsStringSync();
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
    final runtime = File('native/src/bridge_owner_thread.cpp')
        .readAsStringSync();
    expect(plugin, contains('NSApplication.willTerminateNotification'));
    expect(plugin, contains('maplibre_shutdown_all()'));
    expect(runtime, contains('void bridge_shutdownOwnerRuntime()'));
    expect(runtime, contains('worker.join();'));
  });

  test('macOS separates three-finger drag from two-finger scrolling', () {
    final plugin = File(
      'darwin/maplibre_flutter_gpu/Sources/maplibre_flutter_gpu/'
      'MaplibreFlutterGpuPlugin.swift',
    ).readAsStringSync();
    expect(plugin, contains('.leftMouseDragged'));
    expect(plugin, contains('event.subtype == .touch'));
    expect(plugin, isNot(contains('touches(matching:')));
    expect(plugin, isNot(contains('.scrollWheel')));
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

  test(
    'desktop native builds select the matching 64-bit host architecture',
    () {
      final linuxScript = File('native/scripts/build_linux.sh')
          .readAsStringSync();
      final windowsScript = File('native/scripts/build_windows.ps1')
          .readAsStringSync();

      expect(
        linuxScript,
        contains("aarch64 | arm64) ARCHITECTURE_DIR='arm64'"),
      );
      expect(
        linuxScript,
        contains(r'build-linux-fluttergpu-${ARCHITECTURE_DIR}'),
      );
      expect(
        linuxScript,
        contains(r'-DMAPLIBRE_TARGET_ARCHITECTURE="${ARCHITECTURE_DIR}"'),
      );
      expect(windowsScript, contains('[ValidateSet("x64", "arm64")]'));
      expect(windowsScript, contains(r'[string] $Architecture'));
      expect(windowsScript, contains('RuntimeInformation]::OSArchitecture'));
      expect(windowsScript, contains(r'$Triplet = "x64-windows-static"'));
      expect(windowsScript, contains(r'$Triplet = "arm64-windows-static"'));
      expect(windowsScript, contains(r'$RequiredMsvcComponent = '));
      expect(windowsScript, contains(r'$ArchitectureDirectory'));
      expect(windowsScript, contains('Cross-building from'));
      expect(
        windowsScript,
        contains(r'-DMAPLIBRE_TARGET_ARCHITECTURE=$ArchitectureDirectory'),
      );
      expect(
        windowsScript,
        contains(r'"build-windows-fluttergpu-$ArchitectureDirectory"'),
      );
    },
  );

  test('desktop build hook bundles x64 and ARM64 targets', () {
    final hook = File('lib/src/native/desktop_artifacts.dart')
        .readAsStringSync();
    final manifest = File('hook/desktop_artifacts.json').readAsStringSync();

    expect(hook, contains('DynamicLoadingBundled()'));
    expect(hook, contains('Architecture.x64'));
    expect(hook, contains('Architecture.arm64'));
    expect(hook, contains("targetOS != OS.linux"));
    expect(hook, contains("targetOS != OS.windows"));
    expect(manifest, contains('linux/x64/libmaplibre_bridge.so'));
    expect(manifest, contains('linux/arm64/libmaplibre_bridge.so'));
    expect(manifest, contains('windows/x64/maplibre_bridge.dll'));
    expect(manifest, contains('windows/arm64/maplibre_bridge.dll'));
  });

  test('PNG decoding delegates runtime compatibility checks to libpng', () {
    final reader = File(
      'vendor/maplibre-native/platform/default/src/mbgl/util/png_reader.cpp',
    ).readAsStringSync();

    expect(reader, contains('png_create_read_struct(PNG_LIBPNG_VER_STRING'));
    expect(reader, isNot(contains('png_access_version_number')));
  });

  test('native desktop projects reject unsupported and 32-bit targets', () {
    for (final path in <String>[
      'native/platforms/linux/CMakeLists.txt',
      'native/platforms/windows/CMakeLists.txt',
    ]) {
      final cmake = File(path).readAsStringSync();

      expect(cmake, contains('CMAKE_SIZEOF_VOID_P EQUAL 8'));
      expect(cmake, contains('aarch64|arm64'));
      expect(cmake, contains('Unsupported'));
    }
  });
}
