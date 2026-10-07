import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_tv_map_explorer_example/tv_city.dart';
import 'package:maplibre_flutter_tv_map_explorer_example/tv_map_controls.dart';

class _Commands {
  final visits = <TvCity>[];
  final pans = <Offset>[];
  final actions = <TvMapAction>[];
}

Future<_Commands> _pumpControls(
  WidgetTester tester, {
  bool ready = true,
  bool is3d = false,
  Size? size,
  GlobalKey<NavigatorState>? navigatorKey,
  ValueChanged<TvMapAction>? onAction,
}) async {
  if (size != null) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }
  final commands = _Commands();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: TvMapControls(
          ready: ready,
          is3d: is3d,
          onVisit: commands.visits.add,
          onPan: commands.pans.add,
          onAction: (action) {
            commands.actions.add(action);
            onAction?.call(action);
          },
          child: const ColoredBox(color: Colors.grey),
        ),
      ),
    ),
  );
  await tester.pump();

  return commands;
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  int times = 1,
}) async {
  for (var index = 0; index < times; index++) {
    await tester.sendKeyEvent(key, platform: 'android');
    await tester.pumpAndSettle();
  }
}

Future<void> _openCities(
  WidgetTester tester, {
  LogicalKeyboardKey key = LogicalKeyboardKey.select,
}) async {
  await _press(tester, key);
  await _press(tester, LogicalKeyboardKey.arrowRight, times: 4);
  await _press(tester, key);
}

Finder _selectedButton(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.focused == true,
  ),
  matching: find.widgetWithText(OutlinedButton, label),
);

void _expectControlsFocus() {
  final focus = FocusManager.instance.primaryFocus;
  expect(focus, isNotNull);
  expect(
    find.descendant(
      of: find.byType(TvMapControls),
      matching: find.byElementPredicate(
        (element) => identical(element, focus!.context),
      ),
    ),
    findsOneWidget,
  );
}

void main() {
  testWidgets('startup opens New York with keyboard focus ready to pan', (
    tester,
  ) async {
    final commands = await _pumpControls(tester);
    expect(find.text('Choose a city'), findsNothing);
    expect(find.text('New York'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    _expectControlsFocus();

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(commands.pans, [const Offset(64, 0)]);
    await _press(tester, LogicalKeyboardKey.select);
    expect(_selectedButton('Move map'), findsOneWidget);
    expect(commands.visits, isEmpty);
    _expectControlsFocus();
  });

  testWidgets('closing attribution returns keyboard focus to the menu', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final commands = await _pumpControls(
      tester,
      navigatorKey: navigatorKey,
      onAction: (action) {
        if (action != TvMapAction.attribution) return;
        unawaited(
          showDialog<void>(
            context: navigatorKey.currentContext!,
            builder: (context) => AlertDialog(
              title: const Text('Map data'),
              actions: [
                TextButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowRight, times: 5);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(commands.actions, [TvMapAction.attribution]);

    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byType(AlertDialog), findsNothing);
    _expectControlsFocus();
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_selectedButton('Cities'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Choose a city'), findsOneWidget);
  });

  for (final key in [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ]) {
    testWidgets('${key.debugName} activates cities and map controls', (
      tester,
    ) async {
      final commands = await _pumpControls(tester);
      await _openCities(tester, key: key);
      expect(_selectedButton('New York'), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_selectedButton('London'), findsOneWidget);
      await _press(tester, key);
      expect(commands.visits, [TvCity.london]);
      expect(find.byType(OutlinedButton), findsNothing);

      await _press(tester, key);
      expect(_selectedButton('Move map'), findsOneWidget);
      await _press(tester, key);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(commands.visits, [TvCity.london]);
    });

    testWidgets('${key.debugName} repeats cannot switch modes twice', (
      tester,
    ) async {
      final commands = await _pumpControls(tester);
      await tester.sendKeyDownEvent(key, platform: 'android');
      await tester.pump();
      await tester.sendKeyRepeatEvent(key, platform: 'android');
      await tester.sendKeyRepeatEvent(key, platform: 'android');
      await tester.sendKeyUpEvent(key, platform: 'android');
      await tester.pumpAndSettle();
      expect(commands.visits, isEmpty);
      expect(_selectedButton('Move map'), findsOneWidget);

      await tester.sendKeyDownEvent(key, platform: 'android');
      await tester.pump();
      await tester.sendKeyRepeatEvent(key, platform: 'android');
      await tester.sendKeyUpEvent(key, platform: 'android');
      await tester.pumpAndSettle();
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('Move map'), findsNothing);
      expect(commands.visits, isEmpty);
      expect(commands.actions, isEmpty);
    });
  }

  testWidgets('only map mode pans and direction keys repeat', (tester) async {
    final commands = await _pumpControls(tester);
    await _openCities(tester);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(commands.pans, isEmpty);
    await _press(tester, LogicalKeyboardKey.select);

    final directions = {
      LogicalKeyboardKey.arrowLeft: const Offset(-64, 0),
      LogicalKeyboardKey.arrowRight: const Offset(64, 0),
      LogicalKeyboardKey.arrowUp: const Offset(0, -64),
      LogicalKeyboardKey.arrowDown: const Offset(0, 64),
    };
    for (final entry in directions.entries) {
      await tester.sendKeyDownEvent(entry.key, platform: 'android');
      await tester.sendKeyRepeatEvent(entry.key, platform: 'android');
      await tester.sendKeyUpEvent(entry.key, platform: 'android');
      await tester.pump();
    }
    expect(commands.pans, [
      for (final offset in directions.values) ...[offset, offset],
    ]);

    await _press(tester, LogicalKeyboardKey.enter);
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.arrowRight,
      platform: 'android',
    );
    await tester.sendKeyRepeatEvent(
      LogicalKeyboardKey.arrowRight,
      platform: 'android',
    );
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.arrowRight,
      platform: 'android',
    );
    await tester.pumpAndSettle();
    expect(_selectedButton('Zoom out'), findsOneWidget);
    expect(commands.pans, hasLength(8));
    expect(commands.actions, isEmpty);
  });

  testWidgets('all menu actions and city return need only arrows and OK', (
    tester,
  ) async {
    final commands = await _pumpControls(tester);
    await _openCities(tester);
    await _press(tester, LogicalKeyboardKey.arrowRight, times: 3);
    await _press(tester, LogicalKeyboardKey.select);
    expect(commands.visits, [TvCity.sydney]);
    await _press(tester, LogicalKeyboardKey.select);

    for (final label in ['Zoom in', 'Zoom out', '3D view']) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_selectedButton(label), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.select);
    }
    await _press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    expect(_selectedButton('Map data'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    expect(commands.actions, [
      TvMapAction.zoomIn,
      TvMapAction.zoomOut,
      TvMapAction.toggle3d,
      TvMapAction.attribution,
    ]);

    await _press(tester, LogicalKeyboardKey.arrowLeft, times: 5);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byType(OutlinedButton), findsNothing);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowRight, times: 4);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Choose a city'), findsOneWidget);
    expect(_selectedButton('Sydney'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    expect(commands.visits, [TvCity.sydney, TvCity.sydney]);
    expect(commands.pans, isEmpty);
  });

  testWidgets(
    'city navigation reaches all four presets and stops at each end',
    (tester) async {
      final commands = await _pumpControls(tester);
      await _openCities(tester);
      expect(find.byType(OutlinedButton), findsNWidgets(4));
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(_selectedButton('New York'), findsOneWidget);

      for (final city in TvCity.values.skip(1)) {
        await _press(tester, LogicalKeyboardKey.arrowRight);
        expect(_selectedButton(city.label), findsOneWidget);
      }
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_selectedButton('Sydney'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.select);
      expect(commands.visits, [TvCity.sydney]);
    },
  );

  testWidgets('tilted view offers a return to 2D', (tester) async {
    final commands = await _pumpControls(tester, is3d: true);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowRight, times: 3);
    expect(_selectedButton('2D view'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    expect(commands.actions, [TvMapAction.toggle3d]);
  });

  testWidgets(
    'Escape returns through modes and leaves remote Back to Android',
    (tester) async {
      final commands = await _pumpControls(tester);
      await _openCities(tester);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.select, times: 2);
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(OutlinedButton), findsNothing);
      final backHandled = HardwareKeyboard.instance.handleKeyEvent(
        const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.goBack,
          physicalKey: PhysicalKeyboardKey.browserBack,
          timeStamp: Duration.zero,
        ),
      );
      final backUpHandled = HardwareKeyboard.instance.handleKeyEvent(
        const KeyUpEvent(
          logicalKey: LogicalKeyboardKey.goBack,
          physicalKey: PhysicalKeyboardKey.browserBack,
          timeStamp: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();
      expect(backHandled, isFalse);
      expect(backUpHandled, isFalse);
      expect(find.byType(OutlinedButton), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Choose a city'), findsOneWidget);
      expect(_selectedButton('London'), findsOneWidget);
      expect(commands.visits, [TvCity.london]);
      expect(commands.actions, isEmpty);
    },
  );

  testWidgets('Android route Back closes menu before returning to cities', (
    tester,
  ) async {
    await _pumpControls(tester);
    await _press(tester, LogicalKeyboardKey.select);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(OutlinedButton), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Choose a city'), findsOneWidget);
    expect(_selectedButton('New York'), findsOneWidget);
  });

  testWidgets('loading map cannot receive commands', (tester) async {
    final commands = await _pumpControls(tester, ready: false);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.enter);
    await _press(tester, LogicalKeyboardKey.numpadEnter);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(find.text('Loading map…'), findsOneWidget);
    expect(find.text('New York'), findsOneWidget);
    expect(find.text('Choose a city'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(commands.visits, isEmpty);
    expect(commands.pans, isEmpty);
    expect(commands.actions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small landscape keeps selected controls visible', (
    tester,
  ) async {
    await _pumpControls(tester, size: const Size(480, 270));
    await _openCities(tester);
    await _press(tester, LogicalKeyboardKey.arrowRight, times: 3);
    final cityViewport = tester.getRect(find.byType(SingleChildScrollView));
    final selectedCity = tester.getRect(_selectedButton('Sydney'));
    expect(selectedCity.left, greaterThanOrEqualTo(cityViewport.left));
    expect(selectedCity.right, lessThanOrEqualTo(cityViewport.right));
    await _press(tester, LogicalKeyboardKey.select, times: 2);
    await _press(tester, LogicalKeyboardKey.arrowRight, times: 5);

    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    final selected = tester.getRect(_selectedButton('Map data'));
    expect(selected.left, greaterThanOrEqualTo(viewport.left));
    expect(selected.right, lessThanOrEqualTo(viewport.right));
    expect(selected.top, greaterThanOrEqualTo(0));
    expect(selected.bottom, lessThanOrEqualTo(270));
    expect(tester.takeException(), isNull);
  });
}
