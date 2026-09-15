import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

LabelData symbolLabel(
  String text,
  double fontSize, {
  String? visualText,
  TextDirection textDirection = TextDirection.ltr,
  int crossTileId = 0,
  String textFont = '',
  double letterSpacing = 0,
  double lineHeight = 1.2,
  double maxWidth = 10,
  List<String> textFonts = const [],
  List<LabelTextSection> textSections = const [],
  List<LabelTextSection> visualTextSections = const [],
  List<LabelPathPoint> textPath = const [],
  List<LabelPathPoint> iconPath = const [],
  LabelTextJustify textJustify = LabelTextJustify.center,
  LabelAffineTransform textTransform = const LabelAffineTransform(),
  LabelAffineTransform iconTransform = const LabelAffineTransform(),
  bool vertical = false,
  bool alongLine = false,
  bool iconAlongLine = false,
  bool iconRotationWithMap = false,
  bool textKeepUpright = true,
  bool iconKeepUpright = false,
  double textRotation = 0,
  double iconRotation = 0,
  double textTranslateX = 0,
  double textTranslateY = 0,
  double iconTranslateX = 0,
  double iconTranslateY = 0,
  double haloR = 0,
  double haloG = 0,
  double haloB = 0,
  double haloA = 0,
  double haloWidth = 0,
  double haloBlur = 0,
  bool textPlaced = true,
  bool iconPlaced = false,
  String icon = '',
  double iconScale = 1,
  double iconOpacity = 1,
  double textOpacity = 1,
  double iconHaloR = 0,
  double iconHaloG = 0,
  double iconHaloB = 0,
  double iconHaloA = 0,
  double iconHaloWidth = 0,
  double iconHaloBlur = 0,
  double iconFitWidth = 0,
  double iconFitHeight = 0,
  double textW = 0,
  int layerIndex = 0,
  int renderGroup = 0,
  int renderOrder = 0,
}) => LabelData(
  crossTileId: crossTileId,
  lat: 0,
  lon: 0,
  fontSize: fontSize,
  textR: 0,
  textG: 0,
  textB: 0,
  textA: 1,
  haloR: haloR,
  haloG: haloG,
  haloB: haloB,
  haloA: haloA,
  haloWidth: haloWidth,
  haloBlur: haloBlur,
  textFont: textFont,
  textFonts: textFonts,
  textSections: textSections,
  visualTextSections: visualTextSections,
  textPath: textPath,
  iconPath: iconPath,
  letterSpacing: letterSpacing,
  lineHeight: lineHeight,
  maxWidth: maxWidth,
  textJustify: textJustify,
  textTransform: textTransform,
  iconTransform: iconTransform,
  vertical: vertical,
  alongLine: alongLine,
  iconAlongLine: iconAlongLine,
  iconRotationWithMap: iconRotationWithMap,
  textKeepUpright: textKeepUpright,
  iconKeepUpright: iconKeepUpright,
  textRotation: textRotation,
  iconRotation: iconRotation,
  textTranslateX: textTranslateX,
  textTranslateY: textTranslateY,
  iconTranslateX: iconTranslateX,
  iconTranslateY: iconTranslateY,
  textPlaced: textPlaced,
  iconPlaced: iconPlaced,
  icon: icon,
  iconScale: iconScale,
  iconOpacity: iconOpacity,
  textOpacity: textOpacity,
  iconHaloR: iconHaloR,
  iconHaloG: iconHaloG,
  iconHaloB: iconHaloB,
  iconHaloA: iconHaloA,
  iconHaloWidth: iconHaloWidth,
  iconHaloBlur: iconHaloBlur,
  iconFitWidth: iconFitWidth,
  iconFitHeight: iconFitHeight,
  textW: textW,
  text: text,
  visualText: visualText,
  textDirection: textDirection,
  layer: 'labels',
  layerIndex: layerIndex,
  renderGroup: renderGroup,
  renderOrder: renderOrder,
);

Future<({SpriteAtlas atlas, Directory directory})> loadTestSpriteAtlas({
  bool sdf = false,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'maplibre-symbol-widget-',
  );
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  await File('${directory.path}/sprite.json').writeAsString(
    jsonEncode({
      'pin': {
        'x': 0,
        'y': 0,
        'width': 1,
        'height': 1,
        'pixelRatio': 1,
        'sdf': sdf,
      },
    }),
  );
  await File('${directory.path}/sprite.png').writeAsBytes(png);
  final atlas = await SpriteAtlas.load(
    jsonEncode({'version': 8, 'sprite': '${directory.uri}sprite'}),
  );
  if (atlas == null) {
    await directory.delete(recursive: true);
    throw StateError('test sprite atlas did not load');
  }

  return (atlas: atlas, directory: directory);
}
