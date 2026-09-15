import 'dart:async' show Completer;

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'support/controller_fixtures.dart';

void main() {
  test('style inspection and mutation follow maplibre_gl contracts', () async {
    final bridge = FakeControllerBridge();
    var styleChangeCount = 0;
    var styleMutationCount = 0;
    final controller = MapLibreMapController.bind(
      bridge,
      onStyleChangeRequested: (styleString, resolvedStyle) async {
        styleChangeCount++;
        expect(resolvedStyle, styleString);
        bridge.setStyle(resolvedStyle);
      },
      onStyleMutationRequested: () => styleMutationCount++,
    );
    const style = '{"version":8,"sources":{},"layers":[]}';

    await controller.setStyle(style);
    expect(styleChangeCount, 1);
    expect(await controller.getStyle(), style);
    expect(await controller.getLayerIds(), <String>['background', 'roads']);
    expect(await controller.getSourceIds(), <String>['composite']);

    await controller.setLayerVisibility('roads', false);
    expect(await controller.getLayerVisibility('roads'), isFalse);
    expect(await controller.getLayerVisibility('missing'), isNull);
    expect(styleMutationCount, 1);

    final filter = <dynamic>[
      'all',
      <dynamic>[
        '==',
        <dynamic>['get', 'kind'],
        'park',
      ],
      <dynamic>[
        '>=',
        <dynamic>['get', 'rank'],
        3,
      ],
    ];
    await controller.setFilter('roads', filter);
    expect(await controller.getFilter('roads'), filter);
    expect(styleMutationCount, 2);
    // A rejected filter never requests a repaint. The raw JSON setter reports
    // rejection as false, while the decoded setter throws.
    expect(await controller.setLayerFilter('missing', '["==",1,1]'), isFalse);
    expect(styleMutationCount, 2);
    await expectLater(
      controller.setFilter('missing', const ['==', 1, 1]),
      throwsStateError,
    );
    expect(styleMutationCount, 2);
    controller.dispose();
  });

  test('style snapshot guard immediately precedes native mutation', () async {
    final bridge = FakeControllerBridge();
    final events = <String>[];
    bridge.onStyleNativeCall = (operation) {
      events.add('native:$operation');
    };
    final controller = MapLibreMapController.bind(
      bridge,
      beforeStyleMutation: () async => events.add('before'),
      onStyleChangeRequested: (_, resolvedStyle) async {
        bridge.setStyle(resolvedStyle);
      },
      onStyleMutationRequested: () => events.add('after'),
    );
    const style = '{"version":8,"sources":{},"layers":[]}';

    await controller.setStyle(style);
    expect(events, <String>['before', 'native:style']);

    events.clear();
    await controller.setLayerVisibility('roads', false);
    expect(events, <String>['before', 'native:visibility', 'after']);

    events.clear();
    await controller.setFilter('roads', const ['==', 1, 1]);
    expect(events, <String>['before', 'native:filter', 'after']);

    events.clear();
    expect(await controller.setLayerFilter('missing', '["==",1,1]'), isFalse);
    expect(events, <String>['before', 'native:filter']);
    controller.dispose();
  });

  test('style mutation awaits the frame snapshot barrier', () async {
    final bridge = FakeControllerBridge();
    final barrier = Completer<void>();
    final controller = MapLibreMapController.bind(
      bridge,
      beforeStyleMutation: () => barrier.future,
    );
    final visibilityBefore = bridge.layerVisibility['roads'];

    final mutation = controller.setLayerVisibility('roads', false);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.layerVisibility['roads'], visibilityBefore);

    barrier.complete();
    await mutation;
    expect(bridge.layerVisibility['roads'], isFalse);
    controller.dispose();
  });

  test('style mutation cannot resume through a disposed controller', () async {
    final bridge = FakeControllerBridge();
    final barrier = Completer<void>();
    final controller = MapLibreMapController.bind(
      bridge,
      beforeStyleMutation: () => barrier.future,
    );
    final visibilityBefore = bridge.layerVisibility['roads'];

    final mutation = controller.setLayerVisibility('roads', false);
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    barrier.complete();

    await expectLater(mutation, throwsStateError);
    expect(bridge.layerVisibility['roads'], visibilityBefore);
  });
}
