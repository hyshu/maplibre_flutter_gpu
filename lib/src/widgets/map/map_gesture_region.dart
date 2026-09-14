part of '../maplibre_map.dart';

class const _MapGestureRegion({
  required final Key regionKey,
  required final MapGestureCoordinator gestures,
  required final MapGestureSettings settings,
  required final ValueChanged<Offset>? onTap,
  required final ValueChanged<Offset>? onLongPress,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scaleEnabled =
        settings.scrollEnabled ||
        settings.zoomEnabled ||
        settings.rotateEnabled ||
        settings.tiltEnabled;
    final doubleTapEnabled = doubleClickZoomIsEnabled(
      settings.doubleClickZoomEnabled,
      settings.zoomEnabled,
    );
    final tap = onTap;
    final longPress = onLongPress;

    return Listener(
      key: regionKey,
      onPointerDown: gestures.onPointerDown,
      onPointerMove: gestures.onPointerMove,
      onPointerUp: gestures.onPointerEnd,
      onPointerCancel: gestures.onPointerEnd,
      onPointerSignal: gestures.onPointerSignal,
      child: GestureDetector(
        behavior: .opaque,
        onScaleStart: scaleEnabled ? gestures.onScaleStart : null,
        onScaleUpdate: scaleEnabled ? gestures.onScaleUpdate : null,
        onScaleEnd: scaleEnabled ? gestures.onScaleEnd : null,
        onTapUp: tap == null ? null : (details) => tap(details.localPosition),
        onLongPressStart: longPress == null
            ? null
            : (details) => longPress(details.localPosition),
        onDoubleTapDown: doubleTapEnabled ? gestures.onDoubleTapDown : null,
        onDoubleTap: doubleTapEnabled ? gestures.onDoubleTap : null,
        child: child,
      ),
    );
  }
}
