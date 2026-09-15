import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../labels/label_data.dart';
import '../../sprites/sprite_atlas.dart';
import 'map_symbol.dart';
import 'path_glyph_layout.dart';

part 'default_symbol_icon.dart';
part 'default_symbol_text.dart';
part 'symbol_path_text.dart';
part 'symbol_fonts.dart';

Widget _applySymbolTranslation(Widget child, double x, double y) {
  if ((!x.isFinite || x == 0) && (!y.isFinite || y == 0)) return child;

  return Transform.translate(
    offset: Offset(x.isFinite ? x : 0, y.isFinite ? y : 0),
    child: child,
  );
}

Widget _applyPointSymbolTransform(
  Widget child,
  LabelAffineTransform transform,
) {
  if (transform.xx == 1 &&
      transform.xy == 0 &&
      transform.yx == 0 &&
      transform.yy == 1) {
    return child;
  }
  final matrix = Matrix4.identity()
    ..setEntry(0, 0, transform.xx)
    ..setEntry(1, 0, transform.xy)
    ..setEntry(0, 1, transform.yx)
    ..setEntry(1, 1, transform.yy);

  return Transform(
    alignment: Alignment.center,
    transform: matrix,
    child: child,
  );
}

Widget _applyLineSymbolTransform(
  Widget child,
  LabelAffineTransform transform,
  double angle,
) {
  final scale = _lineSymbolScale(transform);
  final rotated = angle.isFinite && angle != 0
      ? Transform.rotate(angle: angle, child: child)
      : child;
  if (!scale.x.isFinite || !scale.y.isFinite) return rotated;

  return Transform.scale(
    scaleX: scale.x,
    scaleY: scale.y,
    alignment: Alignment.center,
    child: rotated,
  );
}

// Line paths already use screen coordinates, so pitch scaling must remain tied
// to screen axes when the glyph rotates to follow its path.
({double x, double y}) _lineSymbolScale(LabelAffineTransform transform) => (
  x: math.sqrt(transform.xx * transform.xx + transform.yx * transform.yx),
  y: math.sqrt(transform.xy * transform.xy + transform.yy * transform.yy),
);

double _lineAdvanceScale(({double x, double y}) scale, double angle) {
  if (!scale.x.isFinite || !scale.y.isFinite || !angle.isFinite) return 1;
  final x = scale.x * math.cos(angle);
  final y = scale.y * math.sin(angle);

  return math.sqrt(x * x + y * y);
}

double _pathAngle(
  List<LabelPathPoint> path,
  double fallback, {
  required bool keepUpright,
}) {
  var angle = fallback;
  if (path.length >= 2) {
    final middle = (path.length - 1) ~/ 2;
    final from = path[middle];
    final to = path[middle + 1];
    if (from.x != to.x || from.y != to.y) {
      angle = math.atan2(to.y - from.y, to.x - from.x);
    }
  }
  if (!angle.isFinite) return 0;
  if (keepUpright) {
    if (angle > math.pi / 2) angle -= math.pi;
    if (angle < -math.pi / 2) angle += math.pi;
  }

  return angle;
}
