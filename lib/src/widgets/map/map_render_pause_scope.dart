import 'package:flutter/widgets.dart';

/// Exposes the nearest map's explicit rendering pause independently of tickers.
class MapRenderPauseScope extends InheritedWidget {
  const MapRenderPauseScope({
    super.key,
    required this.paused,
    required super.child,
  });

  /// Whether descendants should defer map rendering updates.
  final bool paused;

  /// Whether the nearest map is paused, or false outside a map.
  static bool isPausedOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MapRenderPauseScope>()
          ?.paused ??
      false;

  @override
  bool updateShouldNotify(MapRenderPauseScope oldWidget) =>
      paused != oldWidget.paused;
}
