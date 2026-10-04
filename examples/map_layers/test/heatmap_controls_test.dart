import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_map_layers_example/heatmap_controls.dart';
import 'package:maplibre_flutter_map_layers_example/heatmap_style.dart';

void main() {
  testWidgets(
    'sliders commit on release and switches preserve paint settings',
    (tester) async {
      var settings = const HeatmapSettings();
      final commits = <HeatmapSettings>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: HeatmapControls(
                    settings: settings,
                    enabled: true,
                    onChanged: (value) => setState(() => settings = value),
                    onCommitted: (value) {
                      commits.add(value);
                      setState(() => settings = value);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      final slider = find.byKey(const ValueKey('Radius'));
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(commits, isEmpty);
      await gesture.up();
      await tester.pump();
      expect(commits.single.radius, greaterThan(24));

      await tester.tap(find.text('Weight by magnitude'));
      await tester.pump();
      expect(commits.last.weighted, isFalse);
      expect(commits.last.radius, commits.first.radius);
      expect(commits.last.properties.heatmapWeight, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
