import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'support/symbol_finders.dart';
import 'support/symbol_fixtures.dart';

void main() {
  testWidgets('muted symbols defer data and timer-driven text reshaping', (
    tester,
  ) async {
    final relayout = ChangeNotifier();
    addTearDown(relayout.dispose);
    MapSymbol symbol(String text, double size) => MapSymbol(
      key: 'label',
      data: symbolLabel(text, size),
      textPos: const Offset(100, 100),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    Widget view(bool active, String text, double size) => MaterialApp(
      home: TickerMode(
        enabled: active,
        child: MapSymbolOverlay(
          symbols: [symbol(text, size)],
          screenSize: const Size(200, 200),
          relayout: relayout,
          onFadedOut: (_) {},
        ),
      ),
    );

    await tester.pumpWidget(view(true, 'before', 16));
    await tester.pumpWidget(view(true, 'before', 17));
    await tester.pumpWidget(view(false, 'latest', 30));
    relayout.notifyListeners();
    await tester.pump(const Duration(seconds: 1));
    expect(symbolTextBlock('before'), findsOneWidget);
    expect(symbolTextBlock('latest'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(view(true, 'latest', 30));
    expect(symbolTextBlock('latest'), findsOneWidget);
    expect(symbolTextBlock('before'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
