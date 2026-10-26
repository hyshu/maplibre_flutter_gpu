import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/widgets/map/map_render_freeze.dart';

Future<List<int>> pixelAt(
  WidgetTester tester,
  GlobalKey key,
  int x,
  int y,
) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      return data!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  });
  final offset = (y * boundary.size.width.toInt() + x) * 4;

  return bytes!.sublist(offset, offset + 4);
}

void main() {
  testWidgets('freezes painted layers across updates and proportional resize', (
    tester,
  ) async {
    final controller = MapRenderFreezeController();
    final color = ValueNotifier(const Color(0xffff0000));
    final output = GlobalKey();
    final childKey = GlobalKey();
    addTearDown(controller.dispose);
    addTearDown(color.dispose);

    Widget view(double width) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: output,
          child: ColoredBox(
            color: const Color(0xff000000),
            child: SizedBox(
              width: width,
              height: 100,
              child: MapRenderFreeze(
                controller: controller,
                child: RepaintBoundary(
                  key: childKey,
                  child: ValueListenableBuilder(
                    valueListenable: color,
                    builder: (_, value, _) => ColoredBox(color: value),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(view(100));
    final childElement = childKey.currentContext;
    expect(await pixelAt(tester, output, 50, 50), [255, 0, 0, 255]);

    color.value = const Color(0xff0000ff);
    controller.pause(1);
    await tester.pump();
    expect(await pixelAt(tester, output, 50, 50), [255, 0, 0, 255]);
    expect(childKey.currentContext, same(childElement));

    await tester.pumpWidget(view(200));
    expect(await pixelAt(tester, output, 100, 50), [255, 0, 0, 255]);
    expect(await pixelAt(tester, output, 10, 50), [0, 0, 0, 255]);

    controller.resume();
    await tester.pump();
    expect(await pixelAt(tester, output, 100, 50), [255, 0, 0, 255]);
    expect(await pixelAt(tester, output, 10, 50), [0, 0, 0, 255]);
    controller.reveal();
    await tester.pump();
    expect(await pixelAt(tester, output, 100, 50), [0, 0, 255, 255]);
    expect(childKey.currentContext, same(childElement));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final (name, color) in [
    ('transparent', const Color(0x00000000)),
    ('translucent', const Color(0x80ff0000)),
  ]) {
    testWidgets('resume preserves a $name display until reveal', (
      tester,
    ) async {
      final controller = MapRenderFreezeController();
      final output = GlobalKey();
      var paints = 0;
      addTearDown(controller.dispose);

      Widget view(Color color) => Center(
        child: RepaintBoundary(
          key: output,
          child: SizedBox(
            width: 100,
            height: 100,
            child: ColoredBox(
              color: const Color(0xff000000),
              child: MapRenderFreeze(
                controller: controller,
                child: CustomPaint(
                  painter: _FramePainter(color: color, onPaint: () => paints++),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(view(color));
      final original = await pixelAt(tester, output, 50, 50);
      controller.pause(1);
      await tester.pump();
      await tester.pumpWidget(view(const Color(0xff0000ff)));
      final pausedPaints = paints;
      expect(await pixelAt(tester, output, 50, 50), original);

      controller.resume();
      await tester.pump();
      expect(paints, greaterThan(pausedPaints));
      expect(await pixelAt(tester, output, 50, 50), original);

      controller.reveal();
      await tester.pump();
      expect(await pixelAt(tester, output, 50, 50), [0, 0, 255, 255]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pausing during a build retains the previous paint', (
    tester,
  ) async {
    final controller = MapRenderFreezeController();
    final output = GlobalKey();
    addTearDown(controller.dispose);

    Widget view(bool pause) => Center(
      child: RepaintBoundary(
        key: output,
        child: SizedBox(
          width: 100,
          height: 100,
          child: MapRenderFreeze(
            controller: controller,
            child: Builder(
              builder: (_) {
                if (pause) controller.pause(1);

                return ColoredBox(
                  color: pause
                      ? const Color(0xff0000ff)
                      : const Color(0xffff0000),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(view(false));
    await tester.pumpWidget(view(true));
    await tester.pump();
    expect(await pixelAt(tester, output, 50, 50), [255, 0, 0, 255]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a zero-size layout does not discard the paused image', (
    tester,
  ) async {
    final controller = MapRenderFreezeController();
    final output = GlobalKey();
    addTearDown(controller.dispose);

    Widget view(double width, Color color) => Center(
      child: RepaintBoundary(
        key: output,
        child: SizedBox(
          width: width,
          height: 100,
          child: MapRenderFreeze(
            controller: controller,
            child: LayoutBuilder(
              builder: (_, constraints) => constraints.maxWidth == 0
                  ? const SizedBox.shrink()
                  : ColoredBox(color: color),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(view(100, const Color(0xffff0000)));
    final surface = tester.renderObject(find.byType(MapRenderFreeze));
    controller.pause(1);
    await tester.pump();
    await tester.pumpWidget(view(0, const Color(0xff0000ff)));
    await tester.pumpWidget(view(100, const Color(0xff0000ff)));
    expect(tester.renderObject(find.byType(MapRenderFreeze)), same(surface));
    expect(await pixelAt(tester, output, 50, 50), [255, 0, 0, 255]);
    expect(controller.isPaused, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pause inside a paint callback fails before capturing layers', (
    tester,
  ) async {
    final controller = MapRenderFreezeController();
    final output = GlobalKey();
    StateError? rejected;
    addTearDown(controller.dispose);

    Widget view(bool pauseInPaint) => Center(
      child: RepaintBoundary(
        key: output,
        child: SizedBox(
          width: 100,
          height: 100,
          child: MapRenderFreeze(
            controller: controller,
            child: CustomPaint(
              painter: _FramePainter(
                color: pauseInPaint
                    ? const Color(0xff0000ff)
                    : const Color(0xffff0000),
                onPaint: () {
                  if (!pauseInPaint) return;
                  try {
                    controller.pause(1);
                  } on StateError catch (error) {
                    rejected = error;
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(view(false));
    await tester.pumpWidget(view(true));
    expect(rejected, isA<StateError>());
    expect(controller.isPaused, isFalse);
    expect(await pixelAt(tester, output, 50, 50), [0, 0, 255, 255]);
    controller.pause(1);
    await tester.pump();
    expect(controller.isPaused, isTrue);
    expect(await pixelAt(tester, output, 50, 50), [0, 0, 255, 255]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports pause before first paint and a rapid resume-pause', (
    tester,
  ) async {
    final controller = MapRenderFreezeController();
    final output = GlobalKey();
    addTearDown(controller.dispose);
    controller.pause(1);
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: output,
          child: SizedBox(
            width: 100,
            height: 100,
            child: ColoredBox(
              color: const Color(0xff000000),
              child: MapRenderFreeze(
                controller: controller,
                child: const ColoredBox(color: Color(0xffff0000)),
              ),
            ),
          ),
        ),
      ),
    );
    expect(await pixelAt(tester, output, 50, 50), [0, 0, 0, 255]);
    controller.resume();
    await tester.pump();
    expect(await pixelAt(tester, output, 50, 50), [255, 0, 0, 255]);
    controller.pause(1);
    controller.resume();
    controller.pause(1);
    controller.reveal();
    await tester.pump();
    expect(controller.isPaused, isTrue);
    expect(await pixelAt(tester, output, 50, 50), [255, 0, 0, 255]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a painted replacement reveals safely after the paint phase', (
    tester,
  ) async {
    final controller = MapRenderFreezeController();
    final output = GlobalKey();
    var replacementReady = false;
    addTearDown(controller.dispose);

    Widget view() => Center(
      child: RepaintBoundary(
        key: output,
        child: SizedBox(
          width: 100,
          height: 100,
          child: MapRenderFreeze(
            controller: controller,
            child: CustomPaint(
              painter: _FramePainter(
                color: replacementReady
                    ? const Color(0xff0000ff)
                    : const Color(0xffff0000),
                onPaint: () {
                  if (replacementReady) controller.reveal();
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(view());
    controller.pause(1);
    await tester.pump();
    replacementReady = true;
    await tester.pumpWidget(view());
    controller.resume();
    await tester.pump();
    await tester.pump();
    expect(await pixelAt(tester, output, 50, 50), [0, 0, 255, 255]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('muting and pointer suppression apply only to the frozen map', (
    tester,
  ) async {
    final controller = MapRenderFreezeController();
    var taps = 0;
    var ticks = 0;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 100,
          height: 100,
          child: MapRenderFreeze(
            controller: controller,
            child: GestureDetector(
              onTap: () => taps++,
              behavior: HitTestBehavior.opaque,
              child: _TickingChild(onTick: () => ticks++),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.byType(GestureDetector));
    expect(taps, 1);
    expect(ticks, greaterThan(0));

    controller.pause(1);
    await tester.pump();
    final pausedTicks = ticks;
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(GestureDetector), warnIfMissed: false);
    expect(ticks, pausedTicks);
    expect(taps, 1);
    controller.resume();
    controller.reveal();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.byType(GestureDetector));
    expect(ticks, greaterThan(pausedTicks));
    expect(taps, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _FramePainter extends CustomPainter {
  const _FramePainter({required this.color, required this.onPaint});

  final Color color;
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    onPaint();
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => color != oldDelegate.color;
}

class _TickingChild extends StatefulWidget {
  const _TickingChild({required this.onTick});

  final VoidCallback onTick;

  @override
  State<_TickingChild> createState() => _TickingChildState();
}

class _TickingChildState extends State<_TickingChild>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..addListener(widget.onTick);

  @override
  void initState() {
    super.initState();
    _animation.repeat();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }
}
