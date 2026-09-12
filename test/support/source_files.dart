import 'dart:io';

/// Narrow source sets for contracts shared with C++, shaders, and native ABI.
///
/// Each set follows one responsibility across its implementation files. Keeping
/// sets narrow prevents unrelated code from satisfying a contract assertion.
abstract final class SourceFiles {
  /// The Flutter GPU frame renderer and the libraries it is split across.
  static String get renderer => _join(rendererPaths);

  static const List<String> rendererPaths = <String>[
    'lib/src/gpu/renderer.dart',
    'lib/src/gpu/command_decoder.dart',
    'lib/src/gpu/command_resources.dart',
    'lib/src/gpu/frame_uniforms.dart',
    'lib/src/gpu/style_layer_partition.dart',
    'lib/src/gpu/renderer_diagnostics.dart',
    'lib/src/gpu/resource_cache_keys.dart',
    'lib/src/gpu/resource_cache_policy.dart',
    'lib/src/gpu/draw_entry.dart',
    'lib/src/gpu/frame_binder.dart',
    'lib/src/gpu/pass_executor.dart',
    'lib/src/gpu/pipeline_registry.dart',
    'lib/src/gpu/resource_cache.dart',
    'lib/src/frame/command_layout.dart',
    'lib/src/frame/draw_command_admission.dart',
    'lib/src/frame/draw_flags.dart',
    'lib/src/frame/gpu_state.dart',
    'lib/src/frame/pipeline_key.dart',
    'lib/src/frame/render_pass_plan.dart',
    'lib/src/frame/ubo_abi.dart',
    'lib/src/frame/uniform_packer.dart',
    'lib/src/frame/vertex_repack.dart',
  ];

  /// The map widget, its painter, and its extracted state helpers.
  ///
  /// Tests that assert on map lifecycle ordering use [mapWidgetOnly].
  static String get mapWidget => _join(mapWidgetPaths);

  static const List<String> mapWidgetPaths = <String>[
    ...mapWidgetLibraryPaths,
    'lib/src/widgets/map/map_gpu_resources.dart',
    'lib/src/widgets/map_gpu_painter.dart',
    'lib/src/labels/label_source.dart',
    'lib/src/state/map_render_scheduler.dart',
    'lib/src/state/map_style_session.dart',
    'lib/src/state/gesture/gesture_coordinator.dart',
    'lib/src/state/gesture/multi_pointer_tracker.dart',
    'lib/src/state/gesture/pan_fling_tracker.dart',
    'lib/src/state/map_viewport.dart',
  ];

  /// The map widget library in lifecycle order, without its state helpers.
  static String get mapWidgetOnly => _join(mapWidgetLibraryPaths);

  static const List<String> mapWidgetLibraryPaths = <String>[
    'lib/src/widgets/maplibre_map.dart',
    'lib/src/widgets/map/map_callbacks.dart',
    'lib/src/widgets/map/map_state.dart',
    'lib/src/widgets/map/map_composition.dart',
    'lib/src/widgets/map/map_gesture_region.dart',
  ];

  /// Just the render-pass executor, for assertions about pass state.
  ///
  /// This file holds nothing but the two pass helpers, so a test can slice it
  /// by method without the boundaries shifting when unrelated code moves.
  static String get passExecutorOnly => _read('lib/src/gpu/pass_executor.dart');

  /// Just the gesture coordinator, for assertions about gesture ordering.
  static String get gestureCoordinatorOnly =>
      _read('lib/src/state/gesture/gesture_coordinator.dart');

  /// Just `map_gpu_painter.dart`, for assertions about the painter alone.
  static String get gpuPainterOnly =>
      _read('lib/src/widgets/map_gpu_painter.dart');

  /// Native command post-processing immediately before frame publication.
  static String get bridgeMergeOnly => _read('native/src/bridge_merge.cpp');

  /// Native Command Export drawable implementation used by GPU contract tests.
  static String get commandExportDrawableOnly =>
      _read('vendor/maplibre-native/src/mbgl/command_export/drawable.cpp');

  /// Native session lifecycle, camera, projection, and frame operations.
  static String get nativeBridge => _join(nativeBridgePaths);

  static const List<String> nativeBridgePaths = <String>[
    'native/src/bridge_session.hpp',
    'native/src/bridge_camera_operation.hpp',
    'native/src/maplibre_bridge.cpp',
    'native/src/bridge_frame.cpp',
    'native/src/bridge_camera.cpp',
    'native/src/bridge_projection.cpp',
    'native/src/bridge_debug.cpp',
  ];

  /// Native symbol collection and binary label encoding.
  static String get nativeLabels => _join(nativeLabelPaths);

  static const List<String> nativeLabelPaths = <String>[
    'native/src/bridge_labels.cpp',
    'native/src/labels/label_session.cpp',
    'native/src/labels/label_encoding.cpp',
    'native/src/labels/label_export.hpp',
    'native/src/labels/label_encoding.hpp',
    'native/src/labels/label_session.hpp',
    'native/src/labels/label_paint.hpp',
  ];

  /// The Dart FFI bindings to the native bridge.
  static String get ffi => _join(ffiPaths);

  static const List<String> ffiPaths = <String>[
    'lib/src/native/maplibre_ffi.dart',
    'lib/src/native/bindings/camera_bindings.dart',
    'lib/src/native/bindings/label_bindings.dart',
    'lib/src/native/bindings/projection_bindings.dart',
    'lib/src/native/bindings/render_scheduling_bindings.dart',
    'lib/src/native/bindings/style_bindings.dart',
    'lib/src/native/label_export_decoder.dart',
    'lib/src/native/labels/blob_decoder.dart',
    'lib/src/native/labels/placement_decoder.dart',
    'lib/src/native/labels/record_decoder.dart',
    'lib/src/native/labels/static_decoder.dart',
    'lib/src/native/signatures.dart',
    'lib/src/native/symbol_table.dart',
  ];

  /// Exposes [_read] so `source_files_test.dart` can cover the failure path.
  static String readForTest(String relativePath) => _read(relativePath);

  static String _read(String relativePath) {
    final file = File(relativePath);
    if (!file.existsSync()) {
      throw StateError(
        'Missing source file "$relativePath". If it moved, update '
        'test/support/source_files.dart rather than individual tests.',
      );
    }
    return file.readAsStringSync();
  }

  // A newline between files stops a match from spanning a file boundary.
  static String _join(List<String> paths) => paths.map(_read).join('\n');
}
