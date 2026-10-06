import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_map_layers_example/heatmap_controls.dart';
import 'package:maplibre_flutter_map_layers_example/hillshade_controls.dart';
import 'package:maplibre_flutter_map_layers_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('public layers respond to controls and survive layout changes', (
    tester,
  ) async {
    tester.view.physicalSize =
        const Size(390, 844) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const MapLayersApp()),
    );
    await _wait(tester, () {
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.tune),
      );

      return button.onPressed != null;
    });
    await _pumpFor(tester, const Duration(seconds: 8));

    Future<void> toggle(String label) async {
      final finder = find.text(label);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await _wait(
        tester,
        () => tester
            .widget<HeatmapControls>(find.byType(HeatmapControls))
            .enabled,
      );
      await _pumpFor(tester, const Duration(seconds: 1));
    }

    final map = find.byType(MapLibreMap);
    final mapState = tester.state(map);
    final mapSize = tester.getSize(map);
    expect(mapSize.width, 390);
    expect(mapSize.height, greaterThan(750));
    expect(find.byType(HeatmapControls), findsNothing);
    final mapRect = tester.getRect(map).deflate(40);
    final visible = await _capture(tester, key, 'visible');
    await tester.tap(find.byTooltip('Layer controls'));
    await tester.pump();
    expect(tester.getSize(map), mapSize);
    expect(tester.state(map), same(mapState));
    await _capture(tester, key, 'controls');
    await toggle('Show heatmap');
    await tester.tap(find.byTooltip('Close layer controls'));
    await tester.pump();
    expect(tester.getSize(map), mapSize);
    final hidden = await _capture(tester, key, 'hidden');
    var changed = 0;
    for (var y = mapRect.top.ceil(); y < mapRect.bottom.floor(); y++) {
      for (var x = mapRect.left.ceil(); x < mapRect.right.floor(); x++) {
        final index = (y * visible.width + x) * 4;
        final difference = List.generate(
          3,
          (channel) =>
              (visible.bytes[index + channel] - hidden.bytes[index + channel])
                  .abs(),
        ).reduce((a, b) => a + b);
        if (difference > 50) changed++;
      }
    }
    expect(
      changed,
      greaterThan(500),
      reason: 'Density must change map pixels.',
    );

    tester.view.physicalSize =
        const Size(844, 390) * tester.view.devicePixelRatio;
    tester.view.padding = FakeViewPadding(
      left: 59 * tester.view.devicePixelRatio,
      right: 59 * tester.view.devicePixelRatio,
      bottom: 21 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetPadding);
    await tester.pump();
    expect(tester.state(map), same(mapState));
    await tester.tap(find.byTooltip('Layer controls'));
    await tester.pump();
    final close = tester.getRect(find.byTooltip('Close layer controls'));
    expect(close.right, lessThanOrEqualTo(844 - 59));
    expect(tester.getSize(map).width, 844);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<HeatmapControls>(find.byType(HeatmapControls))
          .settings
          .visible,
      isFalse,
    );
    tester.view.resetPhysicalSize();
    tester.view.resetPadding();
    await tester.pump();
    expect(tester.state(map), same(mapState));

    await toggle('Show heatmap');
    await toggle('Weight by magnitude');
    await toggle('Show earthquake points');
    final radius = find.byKey(const ValueKey('Radius'));
    await tester.ensureVisible(radius);
    await tester.drag(radius, const Offset(60, 0));
    await _pumpFor(tester, const Duration(seconds: 1));
    final controls = tester.widget<HeatmapControls>(
      find.byType(HeatmapControls),
    );
    expect(controls.settings.radius, greaterThan(24));
    expect(controls.settings.weighted, isFalse);
    expect(controls.settings.pointsVisible, isTrue);
    expect(find.textContaining('Could not'), findsNothing);
    expect(tester.takeException(), isNull);
    await _capture(tester, key, 'desktop-controls');

    await tester.ensureVisible(find.text('Hillshade'));
    await tester.tap(find.text('Hillshade'));
    await _wait(tester, () {
      final controls = find.byType(HillshadeControls);

      return controls.evaluate().isNotEmpty &&
          tester.widget<HillshadeControls>(controls).enabled;
    });
    await _pumpFor(tester, const Duration(seconds: 8));
    expect(tester.state(map), same(mapState));
    await tester.tap(find.byTooltip('Close layer controls'));
    await tester.pump();
    final hillshade = await _capture(tester, key, 'hillshade');
    await tester.tap(find.byTooltip('Layer controls'));
    await tester.pump();
    await tester.tap(find.text('Show hillshade'));
    await _wait(
      tester,
      () => tester
          .widget<HillshadeControls>(find.byType(HillshadeControls))
          .enabled,
    );
    await _pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Close layer controls'));
    await tester.pump();
    final hillshadeHidden = await _capture(tester, key, 'hillshade-hidden');
    final hillshadeRect = tester.getRect(map).deflate(40);
    var shadingPixels = 0;
    for (
      var y = hillshadeRect.top.ceil();
      y < hillshadeRect.bottom.floor();
      y++
    ) {
      for (
        var x = hillshadeRect.left.ceil();
        x < hillshadeRect.right.floor();
        x++
      ) {
        final index = (y * hillshade.width + x) * 4;
        var difference = 0;
        for (var channel = 0; channel < 3; channel++) {
          difference +=
              (hillshade.bytes[index + channel] -
                      hillshadeHidden.bytes[index + channel])
                  .abs();
        }
        if (difference > 30) shadingPixels++;
      }
    }
    expect(shadingPixels, greaterThan(500), reason: 'Hillshade must render.');

    await tester.tap(find.byTooltip('Layer controls'));
    await tester.pump();
    await tester.tap(find.text('Standard'));
    await _pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('Multidirectional').last);
    await _wait(tester, () {
      final controls = tester.widget<HillshadeControls>(
        find.byType(HillshadeControls),
      );

      return controls.enabled && controls.settings.method == 'multidirectional';
    });
    expect(
      tester
          .widget<HillshadeControls>(find.byType(HillshadeControls))
          .settings
          .method,
      'multidirectional',
    );
    await tester.ensureVisible(find.text('Heatmap'));
    await tester.tap(find.text('Heatmap'));
    await _wait(tester, () {
      final controls = find.byType(HeatmapControls);

      return controls.evaluate().isNotEmpty &&
          tester.widget<HeatmapControls>(controls).enabled;
    });
    final restored = tester.widget<HeatmapControls>(
      find.byType(HeatmapControls),
    );
    expect(restored.settings.radius, controls.settings.radius);
    expect(restored.settings.weighted, isFalse);
    expect(restored.settings.pointsVisible, isTrue);
    expect(tester.state(map), same(mapState));
    await tester.ensureVisible(find.text('Hillshade'));
    await tester.tap(find.text('Hillshade'));
    await _wait(tester, () {
      final controls = find.byType(HillshadeControls);

      return controls.evaluate().isNotEmpty &&
          tester.widget<HillshadeControls>(controls).enabled;
    });
    final restoredShading = tester.widget<HillshadeControls>(
      find.byType(HillshadeControls),
    );
    expect(restoredShading.settings.visible, isFalse);
    expect(restoredShading.settings.method, 'multidirectional');
    expect(find.textContaining('Could not'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Map controls did not become ready.');
    }
    await _pumpFor(tester, const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  }
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<({Uint8List bytes, int width})> _capture(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await _readback(tester, boundary.toImage());
  try {
    final bytes = await _readback(
      tester,
      image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    if (const bool.fromEnvironment('SAVE_SCREENSHOTS')) {
      final png = await _readback(
        tester,
        image.toByteData(format: ui.ImageByteFormat.png),
      );
      final file = File('${Directory.systemTemp.path}/map-layers-$name.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      debugPrint('Screenshot saved to ${file.path}');
    }

    return (bytes: bytes!.buffer.asUint8List(), width: image.width);
  } finally {
    image.dispose();
  }
}

Future<T> _readback<T>(WidgetTester tester, Future<T> future) async {
  var completed = false;
  final observed = future
      .timeout(const Duration(seconds: 10))
      .whenComplete(() => completed = true);
  while (!completed) {
    await _pumpFor(tester, const Duration(milliseconds: 20));
  }

  return observed;
}
