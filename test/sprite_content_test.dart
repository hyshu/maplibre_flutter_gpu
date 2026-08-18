import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/sprites/sprite_atlas.dart';

void main() {
  test('sprite atlas parses content and text-fit metadata', () async {
    final directory = await Directory.systemTemp.createTemp(
      'maplibre-sprite-content-',
    );
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/sprite.json').writeAsString(
      jsonEncode({
        'panel': {
          'x': 0,
          'y': 0,
          'width': 1,
          'height': 1,
          'pixelRatio': 1,
          'stretchX': [
            [0, 1],
          ],
          'stretchY': [
            [0, 1],
          ],
          'content': [0, 0, 1, 1],
          'textFitWidth': 'stretchOnly',
          'textFitHeight': 'proportional',
        },
      }),
    );
    await File('${directory.path}/sprite.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    final atlas = await SpriteAtlas.load(
      jsonEncode({'version': 8, 'sprite': '${directory.uri}sprite'}),
    );
    addTearDown(() => atlas?.dispose());

    final icon = atlas?['panel'];
    expect(icon?.content, const ui.Rect.fromLTRB(0, 0, 1, 1));
    expect(icon?.stretchX, const [(0.0, 1.0)]);
    expect(icon?.stretchY, const [(0.0, 1.0)]);
    expect(icon?.textFitWidth, SpriteTextFit.stretchOnly);
    expect(icon?.textFitHeight, SpriteTextFit.proportional);
  });

  test('sprite content maps fitted bounds while retaining outer borders', () {
    final segments = spriteAxisSegments(
      sourceExtent: 10,
      stretches: const [(2, 8)],
      destExtent: 20,
      pixelRatio: 1,
      scale: 1,
      contentStart: 3,
      contentEnd: 7,
    );

    double destination(double source) => segments
        .firstWhere(
          (segment) => segment.sourceStart == source,
          orElse: () => segments.last,
        )
        .destStart;

    expect(segments.first.destStart, -7);
    expect(destination(2), -5);
    expect(destination(3), 0);
    expect(destination(7), 20);
    expect(destination(8), 25);
    expect(segments.last.destEnd, 27);
  });

  test('content uses the full image as a stretch when ranges are absent', () {
    final segments = spriteAxisSegments(
      sourceExtent: 10,
      stretches: const [],
      destExtent: 12,
      pixelRatio: 1,
      scale: 1,
      contentStart: 2,
      contentEnd: 8,
    );

    expect(segments.first.destStart, -4);
    expect(segments[1].destStart, 0);
    expect(segments[1].destEnd, 12);
    expect(segments.last.destEnd, 16);
  });

  test('content cut mapping includes stretch zones outside its bounds', () {
    final segments = spriteAxisSegments(
      sourceExtent: 10,
      stretches: const [(0, 2), (4, 6), (8, 10)],
      destExtent: 20,
      pixelRatio: 1,
      scale: 4,
      contentStart: 3,
      contentEnd: 7,
    );

    double destination(double source) => segments
        .firstWhere(
          (segment) => segment.sourceStart == source,
          orElse: () => segments.last,
        )
        .destStart;

    expect(destination(3), closeTo(-2 / 3, 0.0001));
    expect(destination(4), closeTo(1 / 3, 0.0001));
    expect(destination(6), closeTo(59 / 3, 0.0001));
    expect(destination(7), closeTo(62 / 3, 0.0001));
  });

  test('text-fit fixed pixels ignore icon scale', () {
    List<SpriteAxisSegment> segments(double scale) => spriteAxisSegments(
      sourceExtent: 10,
      stretches: const [(2, 8)],
      destExtent: 20,
      pixelRatio: 1,
      scale: scale,
      contentStart: 3,
      contentEnd: 7,
    );

    expect(segments(4), segments(1));
  });

  test(
    'sprite proportional constraints adjust fitted content aspect ratio',
    () {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
      final image = recorder.endRecording().toImageSync(10, 10);
      addTearDown(image.dispose);
      final icon = SpriteIcon(
        atlas: image,
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        pixelRatio: 1,
        content: const ui.Rect.fromLTRB(1, 2, 9, 6),
        textFitWidth: SpriteTextFit.stretchOnly,
        textFitHeight: SpriteTextFit.proportional,
      );

      expect(
        icon.fittedContentSize(const ui.Size(10, 10)),
        const ui.Size(20, 10),
      );
    },
  );

  test('fitted content reports its fixed-pixel minimum', () {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final image = recorder.endRecording().toImageSync(10, 10);
    addTearDown(image.dispose);
    final icon = SpriteIcon(
      atlas: image,
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      pixelRatio: 1,
      stretchX: const [(4, 6)],
      stretchY: const [(0, 10)],
      content: const ui.Rect.fromLTRB(2, 0, 8, 10),
    );

    expect(icon.fittedContentSize(const ui.Size(2, 3)), const ui.Size(2, 3));
    expect(icon.minimumFittedContentSize, const ui.Size(4, 0));
  });
}
