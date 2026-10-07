import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_map_layers_example/hillshade_controls.dart';
import 'package:maplibre_flutter_map_layers_example/hillshade_style.dart';

void main() => testWidgets(
  'lighting controls commit without discarding the shading method',
  (tester) async {
    var settings = const HillshadeSettings();
    final commits = <HillshadeSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: HillshadeControls(
                settings: settings,
                enabled: true,
                onChanged: (value) => setState(() => settings = value),
                onCommitted: (value) {
                  commits.add(value);
                  setState(() => settings = value);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Multidirectional').last);
    await tester.pumpAndSettle();
    expect(commits.single.method, 'multidirectional');

    final slider = find.byKey(const ValueKey('Exaggeration'));
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(commits, hasLength(1));
    await gesture.up();
    await tester.pump();
    expect(commits.last.exaggeration, greaterThan(0.5));
    expect(commits.last.method, 'multidirectional');

    await tester.ensureVisible(find.text('Anchor light to map'));
    await tester.tap(find.text('Anchor light to map'));
    await tester.pump();
    expect(commits.last.properties.hillshadeIlluminationAnchor, 'viewport');
    expect(commits.last.exaggeration, commits[1].exaggeration);
    expect(tester.takeException(), isNull);
  },
);
