import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/widgets/map/map_render_freeze.dart';

import 'support/symbol_finders.dart';
import 'support/symbol_fixtures.dart';

MapSymbol _symbol(
  String text, {
  double size = 16,
  Offset position = const Offset(100, 100),
}) => MapSymbol(
  key: 'label',
  data: symbolLabel(text, size),
  textPos: position,
  iconPos: null,
  icon: null,
  visible: true,
  fadeIn: false,
);

Widget _view(Widget child, {bool tickersEnabled = true}) => MaterialApp(
  home: TickerMode(enabled: tickersEnabled, child: child),
);

void main() {
  testWidgets('muted tickers still build initial static symbols', (
    tester,
  ) async {
    await tester.pumpWidget(
      _view(
        MapSymbolOverlay(
          symbols: [_symbol('initial')],
          screenSize: const Size(200, 200),
          onFadedOut: (_) {},
        ),
        tickersEnabled: false,
      ),
    );
    expect(symbolTextBlock('initial'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('ticker changes keep symbol data updates active', (tester) async {
    Widget view(bool tickersEnabled, String text) => _view(
      MapSymbolOverlay(
        symbols: [_symbol(text)],
        screenSize: const Size(200, 200),
        onFadedOut: (_) {},
      ),
      tickersEnabled: tickersEnabled,
    );

    await tester.pumpWidget(view(true, 'before'));
    await tester.pumpWidget(view(false, 'muted'));
    expect(symbolTextBlock('muted'), findsOneWidget);
    expect(symbolTextBlock('before'), findsNothing);
    await tester.pumpWidget(view(false, 'latest'));
    expect(symbolTextBlock('latest'), findsOneWidget);
    expect(symbolTextBlock('muted'), findsNothing);
    await tester.pumpWidget(view(true, 'resumed'));
    expect(symbolTextBlock('resumed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('muted tickers still relayout existing symbols', (tester) async {
    final relayout = ChangeNotifier();
    addTearDown(relayout.dispose);
    var position = const Offset(100, 100);
    final overlay = MapSymbolOverlay(
      symbols: [_symbol('label')],
      symbolsProvider: () => [_symbol('label', position: position)],
      screenSize: const Size(200, 200),
      relayout: relayout,
      onFadedOut: (_) {},
    );

    await tester.pumpWidget(_view(overlay));
    final before = tester.getCenter(symbolTextBlock('label'));
    await tester.pumpWidget(_view(overlay, tickersEnabled: false));
    position = const Offset(140, 120);
    relayout.notifyListeners();
    await tester.pump();
    expect(
      tester.getCenter(symbolTextBlock('label')),
      before + const Offset(40, 20),
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('muted tickers still settle text at its evaluated size', (
    tester,
  ) async {
    Widget view(double size) => _view(
      MapSymbolOverlay(
        symbols: [_symbol('label', size: size)],
        screenSize: const Size(200, 200),
        onFadedOut: (_) {},
      ),
      tickersEnabled: false,
    );

    await tester.pumpWidget(view(13.1));
    await tester.pumpWidget(view(13.11));
    expect(symbolTextStyle(tester, 'label')?.fontSize, 13.1);
    await tester.pump(const Duration(milliseconds: 150));
    expect(symbolTextStyle(tester, 'label')?.fontSize, 13.11);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final tickersEnabled in [true, false]) {
    testWidgets(
      'explicit pause defers symbol updates with tickers enabled $tickersEnabled',
      (tester) async {
        final controller = MapRenderFreezeController();
        final relayout = ChangeNotifier();
        addTearDown(controller.dispose);
        addTearDown(relayout.dispose);

        Widget view(
          String text,
          double size, {
          Offset position = const Offset(100, 100),
        }) => _view(
          MapRenderFreeze(
            controller: controller,
            child: MapSymbolOverlay(
              symbols: [_symbol(text, size: size, position: position)],
              screenSize: const Size(200, 200),
              relayout: relayout,
              onFadedOut: (_) {},
            ),
          ),
          tickersEnabled: tickersEnabled,
        );

        await tester.pumpWidget(view('before', 16));
        await tester.pumpWidget(view('before', 17));
        final before = tester.getCenter(symbolTextBlock('before'));
        controller.pause(1);
        await tester.pumpWidget(
          view('latest', 30, position: const Offset(140, 120)),
        );
        relayout.notifyListeners();
        await tester.pump(const Duration(seconds: 1));
        expect(symbolTextBlock('before'), findsOneWidget);
        expect(symbolTextBlock('latest'), findsNothing);
        expect(tester.getCenter(symbolTextBlock('before')), before);
        expect(tester.binding.hasScheduledFrame, isFalse);

        controller.resume();
        controller.reveal();
        await tester.pump();
        expect(symbolTextBlock('latest'), findsOneWidget);
        expect(symbolTextBlock('before'), findsNothing);
        expect(
          tester.getCenter(symbolTextBlock('latest')),
          before + const Offset(40, 20),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
