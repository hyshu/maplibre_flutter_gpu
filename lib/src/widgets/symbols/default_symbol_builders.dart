import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../labels/label_data.dart';
import '../../sprites/sprite_atlas.dart';
import 'map_symbol.dart';
import 'path_glyph_layout.dart';
import 'symbol_profile_counters.dart';

part 'default_symbol_icon.dart';
part 'default_symbol_text.dart';
part 'symbol_text_content.dart';
part 'symbol_path_text.dart';
part 'symbol_fonts.dart';
part 'symbol_glyph_atlas.dart';
part 'symbol_glyph_run.dart';
part 'symbol_text_block.dart';
part 'symbol_text_scale.dart';

Widget _applySymbolTranslation(Widget child, double x, double y) {
  if ((!x.isFinite || x == 0) && (!y.isFinite || y == 0)) return child;

  return Transform.translate(
    offset: Offset(x.isFinite ? x : 0, y.isFinite ? y : 0),
    child: child,
  );
}

// [ratio] scales shaped text to its evaluated size, as DefaultTextScale
// describes. With [stable], an identity transform still wraps the child, so a transform
// that starts changing later updates the wrapper instead of re-creating the
// subtree under it.
Widget _applyPointSymbolTransform(
  Widget child,
  LabelAffineTransform transform, {
  double ratio = 1,
  bool stable = false,
}) {
  if (!stable && ratio == 1 && _isIdentityTransform(transform)) return child;
  final matrix = Matrix4.identity()
    ..setEntry(0, 0, transform.xx * ratio)
    ..setEntry(1, 0, transform.xy * ratio)
    ..setEntry(0, 1, transform.yx * ratio)
    ..setEntry(1, 1, transform.yy * ratio);

  return Transform(
    alignment: Alignment.center,
    transform: matrix,
    child: child,
  );
}

bool _isIdentityTransform(LabelAffineTransform transform) =>
    transform.xx == 1 &&
    transform.xy == 0 &&
    transform.yx == 0 &&
    transform.yy == 1;

Widget _applyLineSymbolTransform(
  Widget child,
  LabelAffineTransform transform,
  double angle, [
  double ratio = 1,
]) {
  final scale = _lineSymbolScale(transform);
  final rotated = angle.isFinite && angle != 0
      ? Transform.rotate(angle: angle, child: child)
      : child;
  if (!scale.x.isFinite || !scale.y.isFinite) return rotated;

  return Transform.scale(
    scaleX: scale.x * ratio,
    scaleY: scale.y * ratio,
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
