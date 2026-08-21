import 'dart:io';

/// Package sources that contract tests read as text.
///
/// Several tests assert on source content rather than behavior, because the
/// property under test is a contract with C++, a shader, or MapLibre's UBO
/// layout that has no reachable Dart seam yet. Those assertions are worth
/// keeping, but hard-coding a file path in each test makes the package
/// impossible to reorganize: moving one file breaks a dozen unrelated tests
/// for a reason that has nothing to do with the property being tested.
///
/// Each getter below names the *set* of files that implements one logical
/// unit, and returns their concatenated text. When a unit is split across
/// more files, extend its list here and the tests keep passing.
///
/// The sets are deliberately narrow. Reading the whole package would make
/// `isNot(contains(...))` assertions meaningless, since an unrelated file
/// could satisfy the match.
abstract final class SourceFiles {
  /// The Flutter GPU frame renderer and the libraries it is split across.
  static String get renderer => _join(rendererPaths);

  static const List<String> rendererPaths = <String>[
    'lib/src/gpu/renderer.dart',
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
  /// Tests that assert on declaration order within a single file must use
  /// [mapWidgetOnly] instead; offsets into a concatenation are meaningless.
  static String get mapWidget => _join(mapWidgetPaths);

  static const List<String> mapWidgetPaths = <String>[
    'lib/src/widgets/maplibre_map.dart',
    'lib/src/widgets/map_gpu_painter.dart',
    'lib/src/labels/label_source.dart',
    'lib/src/state/map_render_scheduler.dart',
    'lib/src/state/map_style_session.dart',
    'lib/src/state/gesture/gesture_coordinator.dart',
    'lib/src/state/gesture/multi_pointer_tracker.dart',
    'lib/src/state/gesture/pan_fling_tracker.dart',
    'lib/src/state/map_viewport.dart',
  ];

  /// Just `maplibre_map.dart`, for assertions about ordering inside it.
  static String get mapWidgetOnly => _read('lib/src/widgets/maplibre_map.dart');

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
