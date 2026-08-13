import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

void main() {
  test('camera constraints widen ranges before applying new endpoints', () {
    final source = SourceFiles.mapWidgetOnly;
    final start = source.indexOf('void _applyCameraConstraints()');
    final end = source.indexOf('void _updateStyleLoadedState()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);

    final resetZoom = body.indexOf('_bridge.setBounds(');
    final applyZoom = body.indexOf('_bridge.setBounds(', resetZoom + 1);
    expect(resetZoom, greaterThanOrEqualTo(0));
    expect(applyZoom, greaterThan(resetZoom));
    expect(body.substring(resetZoom, applyZoom), isNot(contains('minZoom:')));
    expect(body.substring(applyZoom), contains('minZoom: zoom.minZoom'));

    final resetMinPitch = body.indexOf('_bridge.setMinPitch(0)');
    final resetMaxPitch = body.indexOf('_bridge.setMaxPitch(180)');
    final applyMinPitch = body.indexOf(
      '_bridge.setMinPitch(tilt.minTilt ?? 0)',
    );
    final applyMaxPitch = body.indexOf(
      '_bridge.setMaxPitch(tilt.maxTilt ?? 60)',
    );
    expect(resetMinPitch, greaterThan(applyZoom));
    expect(resetMaxPitch, greaterThan(resetMinPitch));
    expect(applyMinPitch, greaterThan(resetMaxPitch));
    expect(applyMaxPitch, greaterThan(applyMinPitch));
  });

  test(
    'runtime style reload resets dependent state and restarts rendering',
    () {
      final source = SourceFiles.mapWidgetOnly;
      final reloadStart = source.indexOf(
        'Future<void> _onProgrammaticStyleChange(',
      );
      final mutationStart = source.indexOf(
        'void _onProgrammaticStyleMutation()',
        reloadStart,
      );
      expect(reloadStart, greaterThanOrEqualTo(0));
      expect(mutationStart, greaterThan(reloadStart));

      final reload = source.substring(reloadStart, mutationStart);
      for (final reset in <String>[
        // The loaded latch, the sprite atlas and the in-flight load generation
        // are one object now; those resets are covered in
        // test/map_style_session_test.dart. Version, generation, entries and
        // cached symbols likewise live in test/label_source_test.dart.
        '_style.beginStyleChange()',
        '_labels.reset()',
        '_bridge.setStyle(resolvedStyle)',
        '_loadSpriteAtlas(resolvedStyle, baseStyleUrl: styleString)',
        'renderGesture()',
        'scheduleRepaint()',
      ]) {
        expect(reload, contains(reset));
      }

      final updateStart = source.indexOf(
        'void didUpdateWidget(covariant MapLibreMap oldWidget)',
      );
      final disposeStart = source.indexOf('void dispose() {', updateStart);
      final update = source.substring(updateStart, disposeStart);
      expect(
        update.indexOf('oldWidget.styleString != widget.styleString'),
        lessThan(
          update.indexOf('if (!_initialized || !_style.isLoaded) return'),
        ),
      );
      expect(update, contains('controller.setStyle(widget.styleString)'));
      expect(update, contains('.catchError('));

      final initialization = source.substring(
        source.indexOf('Future<void> _initMap()'),
        source.indexOf('void _applyCameraConstraints()'),
      );
      // Native must not come up against a style the widget has already
      // stopped asking for. The retry itself is resolveRequestedStyle's, and
      // test/map_style_resolver_test.dart covers it; what matters here is that
      // initialization hands it a live read of the current request rather than
      // a value captured before the await.
      expect(initialization, contains('resolveRequestedStyle('));
      expect(
        initialization,
        contains('requestedStyle: () => widget.styleString'),
      );
      final styleResolution = initialization.indexOf('resolveRequestedStyle(');
      final nativeStart = initialization.indexOf('_startNativeMap(');
      final shaderLoad = initialization.indexOf('await loadMapShaderLibrary()');
      final bridgeCreation = initialization.indexOf('MaplibreBridge.create()');
      final mountedGuard = initialization.indexOf(
        'if (!mounted) return;',
        shaderLoad,
      );
      final rendererCreation = initialization.indexOf('GpuFrameRenderer(');
      expect(styleResolution, greaterThanOrEqualTo(0));
      expect(nativeStart, greaterThan(styleResolution));
      expect(shaderLoad, greaterThanOrEqualTo(0));
      expect(styleResolution, greaterThan(shaderLoad));
      expect(bridgeCreation, greaterThan(shaderLoad));
      expect(mountedGuard, greaterThan(shaderLoad));
      expect(bridgeCreation, greaterThan(mountedGuard));
      expect(rendererCreation, greaterThan(styleResolution));
      expect(nativeStart, greaterThan(rendererCreation));
    },
  );

  test(
    'style bridge preserves filters and is wired into every native build',
    () {
      final bridge = File('native/src/bridge_style.cpp').readAsStringSync();
      expect(bridge, contains('filter.serialize()'));
      expect(bridge, contains('filterJSON(layer->getFilter())'));
      expect(bridge, contains('convertJSON<mbgl::style::Filter>'));
      expect(bridge, contains('static_cast<const mbgl::Map'));
      expect(bridge, contains('>(*g_map)'));
      expect(bridge, contains('bridge_isStyleLoaded()'));
      expect(bridge, contains('isFilterLayer(*layer)'));

      final cmake = File('native/cmake/bridge_sources.cmake')
          .readAsStringSync();
      final darwin = File('native/scripts/packaging/darwin_common.sh')
          .readAsStringSync();
      expect(cmake, contains('src/bridge_style.cpp'));
      expect(darwin, contains('bridge_style.cpp'));
      for (final symbol in <String>[
        'maplibre_style_last_error',
        'maplibre_style_set',
        'maplibre_style_get_json',
        'maplibre_style_get_layer_ids',
        'maplibre_style_get_source_ids',
        'maplibre_style_get_source_attributions',
        'maplibre_style_set_layer_visibility',
        'maplibre_style_get_layer_visibility',
        'maplibre_style_set_filter',
        'maplibre_style_get_filter',
        'maplibre_style_add_layer',
        'maplibre_style_set_layer_properties',
        'maplibre_style_remove_layer',
      ]) {
        expect(bridge, contains(symbol));
      }
    },
  );
}
