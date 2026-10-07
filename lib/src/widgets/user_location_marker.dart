import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../geo/map_user_location.dart';

/// Builds a marker centered automatically on the projected location.
///
/// Returning null hides the overlay. Custom widgets may receive pointer
/// events. The default [MapUserLocationMarker] ignores them.
typedef MapUserLocationWidgetBuilder = Widget? Function(
  BuildContext context,
  MapUserLocationRenderState state,
);

/// A location dot, heading arrow, and projected horizontal accuracy area.
///
/// Return this widget from `MapLibreMap.userLocationBuilder` to
/// customize the standard appearance. The dot uses logical pixels independent
/// of zoom and display density. Its vertical scale follows camera pitch.
/// Accuracy areas are hidden when their diameter is no larger than the outer
/// dot diameter plus 15 logical pixels.
/// Geometry comes entirely from [state], without camera queries or sensors.
class MapUserLocationMarker extends StatelessWidget {
  /// Creates a standard location marker.
  const MapUserLocationMarker({
    required this.state,
    this.color = const Color(0xFF0088FF),
    this.dotRadius = 8.5,
    this.borderColor = const Color(0xFFFFFFFF),
    this.borderWidth = 2.5,
    this.accuracyColor,
    this.headingColor,
    super.key,
  }) : assert(dotRadius > 0 && dotRadius < double.infinity),
       assert(borderWidth >= 0 && borderWidth < double.infinity);

  /// The projected location and adopted camera snapshot.
  final MapUserLocationRenderState state;

  /// Dot color and the default color of the heading and accuracy area.
  final Color color;

  /// Radius of the colored dot in logical pixels, before pitch scaling.
  final double dotRadius;

  /// Color of the ring around the dot and outline around its heading arrow.
  final Color borderColor;

  /// Width of the dot's border in logical pixels.
  final double borderWidth;

  /// Accuracy fill color, defaulting to [color] at ten percent opacity.
  final Color? accuracyColor;

  /// Heading arrow fill color, defaulting to [color].
  final Color? headingColor;

  @override
  Widget build(BuildContext context) {
    final radius = dotRadius + borderWidth + 12;

    return IgnorePointer(
      child: SizedBox.square(
        dimension: radius * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: radius - state.screenPosition.dx,
              top: radius - state.screenPosition.dy,
              width: state.viewportSize.width,
              height: state.viewportSize.height,
              child: CustomPaint(
                painter: _AccuracyPainter(
                  state: state,
                  color:
                      accuracyColor ?? color.withValues(alpha: color.a * 0.1),
                  minimumDiameter: (dotRadius + borderWidth) * 2 + 15,
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _UserLocationPainter(
                  state: state,
                  color: color,
                  dotRadius: dotRadius,
                  borderColor: borderColor,
                  borderWidth: borderWidth,
                  headingColor: headingColor ?? color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserLocationPainter extends CustomPainter {
  const _UserLocationPainter({
    required this.state,
    required this.color,
    required this.dotRadius,
    required this.borderColor,
    required this.borderWidth,
    required this.headingColor,
  });

  final MapUserLocationRenderState state;
  final Color color;
  final double dotRadius;
  final Color borderColor;
  final double borderWidth;
  final Color headingColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = state.screenPosition;
    if (!center.dx.isFinite || !center.dy.isFinite) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final localCenter = size.center(Offset.zero);
    canvas.translate(localCenter.dx, localCenter.dy);
    final pitch = state.frame.camera.tilt * math.pi / 180;
    final pitchScale = math.cos(pitch).abs();
    canvas.save();
    canvas.scale(1, pitchScale);
    final outerRadius = dotRadius + borderWidth;
    final paint = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(pitch * 5, 3));
    canvas.drawCircle(Offset(0, pitch * 10), outerRadius, paint);
    paint
      ..maskFilter = null
      ..color = borderColor;
    canvas.drawCircle(Offset.zero, outerRadius, paint);
    canvas.restore();
    canvas.save();
    canvas.translate(0, -pitch * 2 * math.sin(pitch));
    canvas.scale(1, pitchScale);
    canvas.drawCircle(Offset.zero, dotRadius, paint..color = color);
    canvas.restore();
    final heading = state.headingRadians;
    if (heading != null) {
      canvas.save();
      canvas.translate(0, -math.sin(pitch));
      canvas.scale(1, pitchScale);
      canvas.rotate(
        math.atan2(math.sin(heading) * pitchScale, math.cos(heading)),
      );
      const arrowSize = 8.0;
      final top = -outerRadius - arrowSize / 2;
      final arrow = Path()
        ..moveTo(0, top)
        ..lineTo(-arrowSize, top + arrowSize)
        ..quadraticBezierTo(
          0,
          top + arrowSize / math.pi,
          arrowSize,
          top + arrowSize,
        )
        ..close();
      canvas.drawPath(arrow, paint..color = headingColor);
      canvas.drawPath(
        arrow,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UserLocationPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.color != color ||
      oldDelegate.dotRadius != dotRadius ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.borderWidth != borderWidth ||
      oldDelegate.headingColor != headingColor;
}

class _AccuracyPainter extends CustomPainter {
  const _AccuracyPainter({
    required this.state,
    required this.color,
    required this.minimumDiameter,
  });

  final MapUserLocationRenderState state;
  final Color color;
  final double minimumDiameter;

  @override
  void paint(Canvas canvas, Size size) {
    if (state.accuracyPolygon.length < 3) return;
    var left = double.infinity;
    var right = double.negativeInfinity;
    for (final point in state.accuracyPolygon) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
    }
    final nativeDiameter =
        (right - left) *
        state.frame.logicalSize.width /
        state.viewportSize.width;
    // The native location dot suppresses accuracy areas close to its size.
    if (nativeDiameter <= minimumDiameter) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
      Path()..addPolygon(state.accuracyPolygon, true),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AccuracyPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.color != color ||
      oldDelegate.minimumDiameter != minimumDiameter;
}
