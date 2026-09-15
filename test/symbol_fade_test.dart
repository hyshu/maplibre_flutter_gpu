import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';

import 'support/symbol_fixtures.dart';

void main() {
  testWidgets('default symbol fade uses the shared batch controller', (
    tester,
  ) async {
    final faded = <String>[];
    Future<void> pump(bool visible) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [
            MapSymbol(
              key: 'places:fade',
              data: symbolLabel('fade', 16),
              textPos: const Offset(100, 100),
              iconPos: null,
              icon: null,
              visible: visible,
            ),
          ],
          screenSize: const Size(200, 200),
          fadeDuration: const Duration(milliseconds: 150),
          onFadedOut: faded.add,
        ),
      ),
    );

    await pump(true);
    expect(find.byType(AnimatedOpacity), findsNothing);
    await tester.pump();
    await tester.pumpAndSettle();
    await pump(false);
    await tester.pump(const Duration(milliseconds: 151));
    await tester.pump();

    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(faded, ['places:fade']);
  });

  testWidgets('default batch fade changes painted opacity', (tester) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()..color = const Color(0xFFFF0000),
    );
    final image = recorder.endRecording().toImageSync(1, 1);
    addTearDown(image.dispose);
    final icon = SpriteIcon(
      atlas: image,
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      pixelRatio: 1,
    );
    final data = symbolLabel(
      '',
      12,
      textPlaced: false,
      iconPlaced: true,
      icon: 'red',
      iconScale: 20,
    );
    const boundaryKey = ValueKey('batch-fade-boundary');
    final faded = <String>[];

    Future<void> pumpScene(bool visible) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(
            color: Colors.white,
            child: SizedBox(
              width: 100,
              height: 100,
              child: MapSymbolOverlay(
                symbols: [
                  MapSymbol(
                    key: 'fade-icon',
                    data: data,
                    textPos: null,
                    iconPos: const Offset(50, 50),
                    icon: icon,
                    visible: visible,
                  ),
                ],
                screenSize: const Size(100, 100),
                fadeDuration: const Duration(milliseconds: 100),
                cullingPadding: EdgeInsets.zero,
                onFadedOut: faded.add,
              ),
            ),
          ),
        ),
      ),
    );

    Future<Color> centerPixel() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final color = await tester.runAsync(() async {
        final rendered = await boundary.toImage(pixelRatio: 1);
        final bytes = await rendered.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final offset = (50 * rendered.width + 50) * 4;
        final result = Color.fromARGB(
          bytes!.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
        rendered.dispose();

        return result;
      });

      return color!;
    }

    await pumpScene(true);
    expect((await centerPixel()).g, closeTo(1, 0.01));
    await tester.pump(const Duration(milliseconds: 50));
    final fadeInMiddle = await centerPixel();
    expect(fadeInMiddle.r, closeTo(1, 0.01));
    expect(fadeInMiddle.g, inExclusiveRange(0.2, 0.8));
    await tester.pump(const Duration(milliseconds: 50));
    expect((await centerPixel()).g, closeTo(0, 0.01));

    await pumpScene(false);
    await tester.pump(const Duration(milliseconds: 50));
    final fadeOutMiddle = await centerPixel();
    expect(fadeOutMiddle.r, closeTo(1, 0.01));
    expect(fadeOutMiddle.g, inExclusiveRange(0.2, 0.8));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect((await centerPixel()).g, closeTo(1, 0.01));
    expect(faded, ['fade-icon']);
  });

  testWidgets('new batch fades do not restart active symbols', (tester) async {
    final faded = <String>[];
    final data = symbolLabel('fade', 12);

    Future<void> pump({required bool first, required bool second}) =>
        tester.pumpWidget(
          MaterialApp(
            home: MapSymbolOverlay(
              symbols: [
                MapSymbol(
                  key: 'first',
                  data: data,
                  textPos: const Offset(40, 50),
                  iconPos: null,
                  icon: null,
                  visible: first,
                  fadeIn: false,
                ),
                MapSymbol(
                  key: 'second',
                  data: data,
                  textPos: const Offset(80, 50),
                  iconPos: null,
                  icon: null,
                  visible: second,
                  fadeIn: false,
                ),
              ],
              screenSize: const Size(120, 100),
              fadeDuration: const Duration(milliseconds: 100),
              onFadedOut: faded.add,
            ),
          ),
        );

    await pump(first: true, second: true);
    await pump(first: false, second: true);
    await tester.pump(const Duration(milliseconds: 50));
    await pump(first: false, second: false);
    await tester.pump(const Duration(milliseconds: 50));

    expect(faded, ['first']);

    await tester.pump(const Duration(milliseconds: 50));

    expect(faded, ['first', 'second']);
  });

  testWidgets('disposing a fading default batch cancels completion', (
    tester,
  ) async {
    final faded = <String>[];
    final data = symbolLabel('dispose', 12);

    Future<void> pump(bool visible) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [
            MapSymbol(
              key: 'dispose',
              data: data,
              textPos: const Offset(50, 50),
              iconPos: null,
              icon: null,
              visible: visible,
              fadeIn: false,
            ),
          ],
          screenSize: const Size(100, 100),
          fadeDuration: const Duration(seconds: 1),
          onFadedOut: faded.add,
        ),
      ),
    );

    await pump(true);
    await pump(false);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
    expect(faded, isEmpty);
  });

  testWidgets('switching from default batch to null completes hidden once', (
    tester,
  ) async {
    final faded = <String>[];
    final data = symbolLabel('mode switch', 12);

    Future<void> pump({required bool visible, required bool defaults}) =>
        tester.pumpWidget(
          MaterialApp(
            home: MapSymbolOverlay(
              symbols: [
                MapSymbol(
                  key: 'mode-switch',
                  data: data,
                  textPos: const Offset(50, 50),
                  iconPos: null,
                  icon: null,
                  visible: visible,
                  fadeIn: false,
                ),
              ],
              screenSize: const Size(100, 100),
              textBuilder: defaults ? buildDefaultSymbolText : null,
              fadeDuration: const Duration(milliseconds: 200),
              onFadedOut: faded.add,
            ),
          ),
        );

    await pump(visible: true, defaults: true);
    await pump(visible: false, defaults: true);
    await tester.pump(const Duration(milliseconds: 50));
    await pump(visible: false, defaults: false);
    await tester.pump();

    expect(faded, ['mode-switch']);

    await tester.pump(const Duration(seconds: 1));

    expect(faded, ['mode-switch']);
  });

  testWidgets('switching from default batch to custom completes hidden once', (
    tester,
  ) async {
    final faded = <String>[];
    final data = symbolLabel('custom switch', 12);
    var usesCustomBuilder = false;

    Future<void> pump(bool visible) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [
            MapSymbol(
              key: 'custom-switch',
              data: data,
              textPos: const Offset(50, 50),
              iconPos: null,
              icon: null,
              visible: visible,
              fadeIn: false,
            ),
          ],
          screenSize: const Size(100, 100),
          textBuilder: usesCustomBuilder
              ? (_, _) => const Text('custom switch')
              : buildDefaultSymbolText,
          fadeDuration: const Duration(milliseconds: 200),
          onFadedOut: faded.add,
        ),
      ),
    );

    await pump(true);
    await pump(false);
    await tester.pump(const Duration(milliseconds: 50));
    usesCustomBuilder = true;
    await pump(false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(faded, ['custom-switch']);
  });

  testWidgets('reviving a symbol cancels mode-switch fade completion', (
    tester,
  ) async {
    final faded = <String>[];
    final data = symbolLabel('revived', 12);

    Future<void> pump({required bool visible, required bool defaults}) =>
        tester.pumpWidget(
          MaterialApp(
            home: MapSymbolOverlay(
              symbols: [
                MapSymbol(
                  key: 'revived',
                  data: data,
                  textPos: const Offset(50, 50),
                  iconPos: null,
                  icon: null,
                  visible: visible,
                  fadeIn: false,
                ),
              ],
              screenSize: const Size(100, 100),
              textBuilder: defaults ? buildDefaultSymbolText : null,
              fadeDuration: const Duration(milliseconds: 200),
              onFadedOut: faded.add,
            ),
          ),
        );

    await pump(visible: true, defaults: true);
    await pump(visible: false, defaults: true);
    await tester.pump(const Duration(milliseconds: 50));
    await pump(visible: false, defaults: false);
    await pump(visible: true, defaults: false);
    await tester.pump();

    expect(faded, isEmpty);
  });
}
