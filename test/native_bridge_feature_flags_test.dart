import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bridge feature marker is compiled and retained on every native path', () {
    final features = File('native/src/bridge_features.cpp').readAsStringSync();
    final cmake = File('native/cmake/bridge_sources.cmake').readAsStringSync();
    final darwin = File(
      'native/scripts/packaging/darwin_common.sh',
    ).readAsStringSync();
    final anchor = File(
      'darwin/maplibre_flutter_gpu/Packaging/maplibre_bridge_anchor.cpp',
    ).readAsStringSync();

    expect(features, contains('kFillExtrusionGpuReady = 1u << 0'));
    expect(features, contains('kBridgeBuildMarker = "fe-gpu-ready-v1"'));
    expect(features, contains('maplibre_bridge_feature_flags()'));
    expect(
      features,
      contains('[MapLibre] bridge features=0x%08x build=%s'),
    );
    expect(cmake, contains('/src/bridge_features.cpp'));
    expect(darwin, contains('/src/bridge_features.cpp'));
    expect(anchor, contains('X(maplibre_bridge_feature_flags)'));
    expect(
      anchor,
      contains('[MapLibre] bridge anchor build=fe-gpu-ready-v1'),
    );
  });
}
