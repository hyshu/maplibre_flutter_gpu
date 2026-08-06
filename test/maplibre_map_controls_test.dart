import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/widgets/map_controls.dart';

void main() {
  test('control enum order matches maplibre_gl', () {
    expect(CompassViewPosition.values.map((value) => value.name), [
      'topLeft',
      'topRight',
      'bottomLeft',
      'bottomRight',
    ]);
    expect(AttributionButtonPosition.values.length, 4);
    expect(LogoViewPosition.values.length, 4);
    expect(ScaleControlPosition.values.length, 4);
    expect(ScaleControlUnit.values.map((value) => value.name), [
      'metric',
      'imperial',
      'nautical',
    ]);
  });

  test('distance and scale helpers produce geographic scale values', () {
    expect(
      distanceMeters(const LatLng(0, 0), const LatLng(0, 1)),
      closeTo(111195, 2),
    );

    final metric = scaleBarValue(1250, ScaleControlUnit.metric);
    expect(metric.label, '1 km');
    expect(metric.width, closeTo(64, 0.001));

    final imperial = scaleBarValue(1000, ScaleControlUnit.imperial);
    expect(imperial.label, '2000 ft');
    expect(imperial.width, closeTo(48.768, 0.01));

    final nautical = scaleBarValue(18520, ScaleControlUnit.nautical);
    expect(nautical.label, '10 nm');
    expect(nautical.width, 80);
  });

  test('scale helper rejects invalid distances and widths', () {
    const empty = ScaleBarValue(label: '', width: 0);

    expect(scaleBarValue(double.nan, ScaleControlUnit.metric), empty);
    expect(
      scaleBarValue(100, ScaleControlUnit.metric, maxWidth: double.nan),
      empty,
    );
    expect(scaleBarValue(100, ScaleControlUnit.metric, maxWidth: -1), empty);
    expect(
      scaleBarValue(100, ScaleControlUnit.metric, maxWidth: double.infinity),
      empty,
    );
  });

  test('style attributions include source labels and links', () {
    final attributions = parseStyleAttributions([
      '<a href="https://openstreetmap.org/copyright">'
          '&copy; OpenStreetMap contributors</a>',
      'Imagery provider',
      '<a href="https://openstreetmap.org/copyright">'
          '&copy; OpenStreetMap contributors</a>',
    ]);

    expect(attributions, [
      (
        label: '© OpenStreetMap contributors',
        url: 'https://openstreetmap.org/copyright',
      ),
      (label: 'Imagery provider', url: null),
    ]);
  });

  test('style attributions support quote styles and numeric entities', () {
    expect(
      parseStyleAttributions([
        "<a href='https://example.com'>&#169; Example</a>",
        '<a href=https://example.org>&#x00A9; Other</a>',
      ]),
      [
        (label: '© Example', url: 'https://example.com'),
        (label: '© Other', url: 'https://example.org'),
      ],
    );
    expect(parseStyleAttributions(const []), isEmpty);
  });

  testWidgets('logo and attribution controls honor configured corners', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: MapLibreMapControls(
            mapSize: Size(300, 200),
            controller: null,
            compassEnabled: false,
            logoEnabled: true,
            logoViewPosition: LogoViewPosition.topLeft,
            logoViewMargins: Point(12, 14),
            compassViewPosition: null,
            compassViewMargins: null,
            attributionButtonEnabled: true,
            attributionButtonPosition: AttributionButtonPosition.bottomRight,
            attributionButtonMargins: Point(9, 11),
            scaleControlEnabled: false,
            scaleControlPosition: ScaleControlPosition.bottomLeft,
            scaleControlUnit: ScaleControlUnit.metric,
          ),
        ),
      ),
    );

    final logoPosition = tester.widget<Positioned>(
      find.ancestor(
        of: find.text('MapLibre'),
        matching: find.byType(Positioned),
      ),
    );
    expect(logoPosition.left, 12);
    expect(logoPosition.top, 14);

    final attributionPosition = tester.widget<Positioned>(
      find.ancestor(
        of: find.byTooltip('Map attribution'),
        matching: find.byType(Positioned),
      ),
    );
    expect(attributionPosition.right, 9);
    expect(attributionPosition.bottom, 11);
    expect(tester.getSize(find.byType(IconButton)), const Size.square(24));

    await tester.tap(find.byTooltip('Map attribution'));
    await tester.pumpAndSettle();
    expect(find.text('Map attribution'), findsWidgets);
  });

  testWidgets('attribution control can be disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: MapLibreMapControls(
            mapSize: Size(300, 200),
            controller: null,
            compassEnabled: false,
            logoEnabled: false,
            logoViewPosition: null,
            logoViewMargins: null,
            compassViewPosition: null,
            compassViewMargins: null,
            attributionButtonEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomRight,
            attributionButtonMargins: null,
            scaleControlEnabled: false,
            scaleControlPosition: ScaleControlPosition.bottomLeft,
            scaleControlUnit: ScaleControlUnit.metric,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Map attribution'), findsNothing);
  });

  testWidgets('non-finite margins use the default position', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MapLibreMapControls(
          mapSize: Size(300, 200),
          controller: null,
          compassEnabled: false,
          logoEnabled: true,
          logoViewPosition: LogoViewPosition.topLeft,
          logoViewMargins: Point(double.nan, double.infinity),
          compassViewPosition: null,
          compassViewMargins: null,
          attributionButtonEnabled: false,
          attributionButtonPosition: null,
          attributionButtonMargins: null,
          scaleControlEnabled: false,
          scaleControlPosition: ScaleControlPosition.bottomLeft,
          scaleControlUnit: ScaleControlUnit.metric,
        ),
      ),
    );

    final position = tester.widget<Positioned>(
      find.ancestor(
        of: find.text('MapLibre'),
        matching: find.byType(Positioned),
      ),
    );
    expect(position.left, 8);
    expect(position.top, 8);
  });

  testWidgets('control builders replace default widgets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: MapLibreMapControls(
            mapSize: const Size(300, 200),
            controller: null,
            compassEnabled: true,
            logoEnabled: true,
            logoViewPosition: null,
            logoViewMargins: null,
            compassViewPosition: null,
            compassViewMargins: null,
            attributionButtonEnabled: true,
            attributionButtonPosition: null,
            attributionButtonMargins: null,
            scaleControlEnabled: false,
            scaleControlPosition: ScaleControlPosition.bottomLeft,
            scaleControlUnit: ScaleControlUnit.metric,
            compassBuilder: (context, bearing, onPressed) =>
                Text('compass:$bearing'),
            logoBuilder: (context) => const Text('custom logo'),
            attributionButtonBuilder: (context, onPressed) => TextButton(
              onPressed: onPressed,
              child: const Text('custom attribution'),
            ),
            attributionDialogBuilder: (context) =>
                const AlertDialog(content: Text('custom dialog')),
          ),
        ),
      ),
    );

    expect(find.text('compass:0.0'), findsOneWidget);
    expect(find.text('custom logo'), findsOneWidget);
    expect(find.text('MapLibre'), findsNothing);
    await tester.tap(find.text('custom attribution'));
    await tester.pumpAndSettle();
    expect(find.text('custom dialog'), findsOneWidget);
  });

  testWidgets('null control builders hide controls', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MapLibreMapControls(
          mapSize: Size(300, 200),
          controller: null,
          compassEnabled: true,
          logoEnabled: true,
          logoViewPosition: null,
          logoViewMargins: null,
          compassViewPosition: null,
          compassViewMargins: null,
          attributionButtonEnabled: true,
          attributionButtonPosition: null,
          attributionButtonMargins: null,
          scaleControlEnabled: false,
          scaleControlPosition: ScaleControlPosition.bottomLeft,
          scaleControlUnit: ScaleControlUnit.metric,
          compassBuilder: null,
          logoBuilder: null,
          attributionButtonBuilder: null,
          scaleControlBuilder: null,
        ),
      ),
    );

    expect(find.byType(IconButton), findsNothing);
    expect(find.text('MapLibre'), findsNothing);
  });
}
