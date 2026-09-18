import 'dart:async' show Completer, unawaited;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../controller/maplibre_map_controller.dart';
import '../controller/style_resolver.dart';
import '../controller/styles.dart';
import '../geo/camera.dart';
import '../geo/camera_constraints.dart';
import '../gpu/render_context.dart';
import '../gpu/renderer.dart';
import '../gpu/shaders.dart';
import '../labels/label_source.dart';
import '../labels/symbol_layer_composition.dart';
import '../native/maplibre_ffi.dart';
import '../sprites/sprite_atlas.dart';
import '../state/gesture/gesture_coordinator.dart';
import '../state/gesture/gesture_math.dart';
import '../state/gesture/gesture_options.dart';
import '../state/gesture/macos_trackpad_tilt.dart';
import '../state/map_render_scheduler.dart';
import '../state/map_style_session.dart';
import '../state/map_viewport.dart';
import 'map_controls.dart';
import 'map_gpu_painter.dart';
import 'symbols/default_symbol_builders.dart';
import 'symbols/map_symbol.dart';
import 'symbols/symbol_overlay.dart';

part 'map/map_callbacks.dart';
part 'map/map_state.dart';
part 'map/map_initialization.dart';
part 'map/map_style.dart';
part 'map/map_rendering.dart';
part 'map/map_composition.dart';
part 'map/map_gesture_region.dart';

/// Displays a MapLibre map rendered with Flutter GPU.
///
/// The map expands to the largest size allowed by its parent. It requires
/// finite, non-zero width and height. It remains empty and does not initialize
/// while either dimension is unbounded or zero.
///
/// After the first valid layout, the map begins initializing its renderer. If
/// initialization succeeds, it creates a [MapLibreMapController] and calls
/// [onMapCreated]. [onStyleLoadedCallback] runs later, after the initial style
/// has loaded. The same callback runs again after each style replacement.
///
/// The map owns the controller passed to [onMapCreated] and disposes it with the
/// widget. Application code must not dispose the controller or use it after the
/// map has been removed from the tree.
///
/// A minimal map can be created as follows:
///
/// ```dart
/// MapLibreMap(
///   initialCameraPosition: const CameraPosition(
///     target: LatLng(35.6812, 139.7671),
///     zoom: 13,
///   ),
///   onMapCreated: (controller) {
///     // Keep the controller only while this map remains mounted.
///   },
/// );
/// ```
///
/// See also:
///
///  * [MapLibreMapController], which changes the camera and active style.
///  * [CameraPosition], which describes the initial camera.
///  * [MapGestureOptions], which configures detailed gesture behavior.
///  * [MapSymbol], which is passed to custom symbol builders.
class MapLibreMap extends StatefulWidget {
  /// Creates a MapLibre map.
  ///
  /// [scaleControlMaxWidth] must be finite and greater than zero.
  /// [scaleControlLogoOffset] must be finite and non-negative.
  /// [symbolFadeDuration] must be non-negative.
  const new({
    super.key,
    this.initialCameraPosition,
    this.styleString = MapLibreStyles.demo,
    this.onMapCreated,
    this.onStyleLoadedCallback,
    this.onCameraMove,
    this.onCameraIdle,
    this.onMapIdle,
    this.onMapClick,
    this.onMapLongClick,
    this.cameraTargetBounds = CameraTargetBounds.unbounded,
    this.minMaxZoomPreference = MinMaxZoomPreference.unbounded,
    this.minMaxTiltPreference = MinMaxTiltPreference.unbounded,
    this.rotateGesturesEnabled = true,
    this.scrollGesturesEnabled = true,
    this.zoomGesturesEnabled = true,
    this.tiltGesturesEnabled = true,
    this.doubleClickZoomEnabled,
    this.gestureOptions = const MapGestureOptions(),
    this.trackCameraPosition = false,
    this.compassEnabled = true,
    this.logoEnabled = false,
    this.logoViewPosition,
    this.logoViewMargins,
    this.compassViewPosition,
    this.compassViewMargins,
    this.attributionButtonEnabled = true,
    this.attributionButtonPosition = .bottomRight,
    this.attributionButtonMargins,
    this.onAttributionLinkTap,
    this.scaleControlEnabled = false,
    this.scaleControlPosition = .bottomLeft,
    this.scaleControlUnit = .metric,
    this.scaleControlMargins = const math.Point<num>(8, 8),
    this.scaleControlMaxWidth = 80,
    this.scaleControlAvoidLogo = true,
    this.scaleControlLogoOffset = 27,
    this.compassBuilder = MapLibreMap.defaultCompassBuilder,
    this.logoBuilder = MapLibreMap.defaultLogoBuilder,
    this.attributionButtonBuilder = MapLibreMap.defaultAttributionButtonBuilder,
    this.attributionDialogBuilder = MapLibreMap.defaultAttributionDialogBuilder,
    this.scaleControlBuilder = MapLibreMap.defaultScaleControlBuilder,
    this.foregroundLoadColor = Colors.transparent,
    this.loadingBuilder = MapLibreMap.defaultLoadingBuilder,
    this.errorBuilder = MapLibreMap.defaultErrorBuilder,
    this.symbolIconBuilder = MapLibreMap.defaultSymbolIconBuilder,
    this.symbolTextBuilder = MapLibreMap.defaultSymbolTextBuilder,
    this.symbolFadeDuration = const Duration(milliseconds: 150),
    this.symbolCullingPadding = const EdgeInsets.symmetric(
      horizontal: 120,
      vertical: 60,
    ),
    this.symbolCompositingMode = .interleaved,
    this.gpuMapRenderCallback,
    this.gpuRenderCallback,
    this.gpuRepaint,
    this.gpuOverlayDepthMode = .isolated,
  }) : assert(
         scaleControlMaxWidth > 0 && scaleControlMaxWidth < double.infinity,
       ),
       assert(
         scaleControlLogoOffset >= 0 &&
             scaleControlLogoOffset < double.infinity,
       );

  /// The camera position applied when the map is first created.
  ///
  /// If null, the camera declared by [styleString] is used. Changes to this
  /// property after [onMapCreated] do not move the camera. Use
  /// [MapLibreMapController.moveCamera] or
  /// [MapLibreMapController.animateCamera] for later changes.
  ///
  /// Defaults to null.
  final CameraPosition? initialCameraPosition;

  /// The style used to render the map.
  ///
  /// This can be a MapLibre style URL, a raw JSON document, an absolute file
  /// path, a file URI, or a Flutter asset path. Changing this property after
  /// initialization completes starts an asynchronous style replacement. A
  /// change made during initial style resolution becomes the initial style.
  ///
  /// [onStyleLoadedCallback] runs after each successfully loaded value.
  ///
  /// Defaults to [MapLibreStyles.demo].
  ///
  /// See the [MapLibre style spec](https://maplibre.org/maplibre-style-spec/).
  final String styleString;

  /// Called once after this map's renderer and controller have been created.
  ///
  /// The initial style might not be loaded when this callback runs. Use
  /// [onStyleLoadedCallback] for work that requires the style.
  ///
  /// The map owns the controller and disposes it when this widget is removed.
  /// The callback must not dispose the controller.
  ///
  /// Defaults to null.
  final MapCreatedCallback? onMapCreated;

  /// Called after the active style has loaded.
  ///
  /// This runs after [onMapCreated] for the initial style and runs again after
  /// each style replacement.
  ///
  /// Defaults to null.
  final OnStyleLoadedCallback? onStyleLoadedCallback;

  /// Called when a rendered frame has a different camera position.
  ///
  /// Camera changes can result from gestures or controller commands. This
  /// callback is independent of [trackCameraPosition], which only controls
  /// notifications sent to listeners of [MapLibreMapController].
  ///
  /// Defaults to null.
  final OnCameraMoveCallback? onCameraMove;

  /// Called after camera movement has ended.
  ///
  /// This runs after a touch gesture or programmatic camera change settles.
  /// Scroll-wheel zoom completes after 150 milliseconds without further
  /// vertical wheel input. A programmatic camera update that interrupts a
  /// gesture owns the subsequent idle notification.
  ///
  /// Camera idle does not imply that tiles or other map work have finished.
  /// Use [onMapIdle] to observe the fully settled state.
  ///
  /// Defaults to null.
  final OnCameraIdleCallback? onCameraIdle;

  /// Called when the style, camera, and pending map work have fully settled.
  ///
  /// The callback can run more than once during the map's lifetime. It must not
  /// be treated as a one-shot notification.
  ///
  /// Defaults to null.
  final OnMapIdleCallback? onMapIdle;

  /// Called after a tap on an initialized map.
  ///
  /// The callback receives the tap point in logical pixels from the map's
  /// top-left corner and the geographic coordinate at that point.
  ///
  /// Defaults to null.
  final OnMapClickCallback? onMapClick;

  /// Called after a long press begins on an initialized map.
  ///
  /// The callback receives the press point in logical pixels from the map's
  /// top-left corner and the geographic coordinate at that point.
  ///
  /// Defaults to null.
  final OnMapClickCallback? onMapLongClick;

  /// The geographical bounds that constrain the camera target.
  ///
  /// Updated bounds are applied after the active style has loaded.
  ///
  /// Defaults to [CameraTargetBounds.unbounded].
  final CameraTargetBounds cameraTargetBounds;

  /// The minimum and maximum zoom levels allowed for the camera.
  ///
  /// Updated limits are applied after the active style has loaded. An
  /// unspecified minimum defaults to zero, and an unspecified maximum defaults
  /// to 25.5.
  ///
  /// Defaults to [MinMaxZoomPreference.unbounded].
  final MinMaxZoomPreference minMaxZoomPreference;

  /// The minimum and maximum tilt angles allowed for the camera.
  ///
  /// Values are measured in degrees. Updated limits are applied after the
  /// active style has loaded. An unspecified minimum defaults to zero, and an
  /// unspecified maximum defaults to 60.
  ///
  /// Defaults to [MinMaxTiltPreference.unbounded].
  final MinMaxTiltPreference minMaxTiltPreference;

  /// Whether two-finger gestures and Ctrl with left-drag on Windows and Linux
  /// can rotate the camera.
  ///
  /// Defaults to true.
  final bool rotateGesturesEnabled;

  /// Whether one-finger drag gestures can pan the camera.
  ///
  /// Defaults to true.
  final bool scrollGesturesEnabled;

  /// Whether pinch and scroll-wheel gestures can zoom the camera.
  ///
  /// [doubleClickZoomEnabled] separately controls double-tap zoom.
  ///
  /// Defaults to true.
  final bool zoomGesturesEnabled;

  /// Whether three-finger vertical drag gestures and Shift with left-drag on
  /// Windows and Linux can tilt the camera.
  ///
  /// Defaults to true.
  final bool tiltGesturesEnabled;

  /// Whether double-tap zoom is enabled.
  ///
  /// If null, double-tap zoom follows [zoomGesturesEnabled].
  ///
  /// Defaults to null.
  final bool? doubleClickZoomEnabled;

  /// Animation, threshold, and sensitivity settings for map gestures.
  ///
  /// The gesture enablement properties still determine which gesture families
  /// can change the camera.
  ///
  /// Defaults to a const [MapGestureOptions] instance.
  final MapGestureOptions gestureOptions;

  /// Whether the controller notifies its listeners when the camera moves
  /// or the map viewport changes size.
  ///
  /// This does not control [onCameraMove], which runs whenever that callback is
  /// non-null and a camera change is observed.
  ///
  /// Defaults to false.
  final bool trackCameraPosition;

  /// Whether the compass builder is included in the map controls.
  ///
  /// The default compass fades out and ignores input while the camera faces
  /// north. A custom [compassBuilder] receives every current bearing.
  ///
  /// Defaults to true.
  final bool compassEnabled;

  /// Whether the MapLibre logo builder is included in the map controls.
  ///
  /// Defaults to false.
  final bool logoEnabled;

  /// The corner in which the MapLibre logo is positioned.
  ///
  /// If null, [LogoViewPosition.bottomLeft] is used.
  ///
  /// Defaults to null.
  final LogoViewPosition? logoViewPosition;

  /// The horizontal and vertical inset of the logo from its corner.
  ///
  /// The point's x and y values are measured in logical pixels. If this is null,
  /// an inset of 8 logical pixels is used on each axis. A non-finite component
  /// also falls back to 8 logical pixels.
  ///
  /// Defaults to null.
  final math.Point<num>? logoViewMargins;

  /// The corner in which the compass is positioned.
  ///
  /// If null, [CompassViewPosition.topRight] is used.
  ///
  /// Defaults to null.
  final CompassViewPosition? compassViewPosition;

  /// The horizontal and vertical inset of the compass from its corner.
  ///
  /// The point's x and y values are measured in logical pixels. If this is null,
  /// an inset of 8 logical pixels is used on each axis. A non-finite component
  /// also falls back to 8 logical pixels.
  ///
  /// Defaults to null.
  final math.Point<num>? compassViewMargins;

  /// Whether the attribution button builder is included in the map controls.
  ///
  /// Defaults to true.
  final bool attributionButtonEnabled;

  /// The corner in which the attribution button is positioned.
  ///
  /// If null, [AttributionButtonPosition.bottomRight] is used.
  ///
  /// Defaults to [AttributionButtonPosition.bottomRight].
  final AttributionButtonPosition? attributionButtonPosition;

  /// The horizontal and vertical inset of the attribution button from its
  /// corner.
  ///
  /// The point's x and y values are measured in logical pixels. If this is null,
  /// an inset of 8 logical pixels is used on each axis. A non-finite component
  /// also falls back to 8 logical pixels.
  ///
  /// Defaults to null.
  final math.Point<num>? attributionButtonMargins;

  /// Called when a URL in the default attribution dialog is tapped.
  ///
  /// When null, URLs remain visible and selectable but are not opened. This
  /// callback is not used by a custom [attributionDialogBuilder].
  ///
  /// Defaults to null.
  final AttributionLinkCallback? onAttributionLinkTap;

  /// Whether a scale control is displayed when its value can be calculated.
  ///
  /// Calculation begins after [onMapCreated] and requires a non-empty viewport.
  ///
  /// Defaults to false.
  final bool scaleControlEnabled;

  /// The corner in which the scale control is positioned.
  ///
  /// Defaults to [ScaleControlPosition.bottomLeft].
  final ScaleControlPosition scaleControlPosition;

  /// The distance unit displayed by the scale control.
  ///
  /// Defaults to [ScaleControlUnit.metric].
  final ScaleControlUnit scaleControlUnit;

  /// The horizontal and vertical inset of the scale control from its corner.
  ///
  /// The point's x and y values are measured in logical pixels. A non-finite
  /// component falls back to 8 logical pixels.
  ///
  /// Defaults to 8 logical pixels on each axis.
  final math.Point<num> scaleControlMargins;

  /// The maximum width of the scale control in logical pixels.
  ///
  /// This value must be finite and greater than zero. The rendered scale can be
  /// narrower to represent a readable rounded distance.
  ///
  /// Defaults to 80.
  final double scaleControlMaxWidth;

  /// Whether the scale control avoids a logo in the same bottom corner.
  ///
  /// When true, the logo is displayed, and both controls use the same bottom
  /// corner, the scale control moves upward by [scaleControlLogoOffset].
  ///
  /// Defaults to true.
  final bool scaleControlAvoidLogo;

  /// The distance used to move the scale control above the logo.
  ///
  /// This value is measured in logical pixels and must be finite and
  /// non-negative. It only applies when [scaleControlAvoidLogo] moves a scale
  /// control in a bottom corner.
  ///
  /// Defaults to 27.
  final double scaleControlLogoOffset;

  /// The builder used for the compass control.
  ///
  /// It receives the current bearing in degrees and a callback that resets the
  /// camera to north. The reset callback is null until the controller is ready.
  /// If this builder is null, no compass is displayed even when
  /// [compassEnabled] is true.
  ///
  /// Defaults to [defaultCompassBuilder].
  final CompassWidgetBuilder? compassBuilder;

  /// The builder used for the MapLibre logo.
  ///
  /// If null, no logo is displayed even when [logoEnabled] is true.
  ///
  /// Defaults to [defaultLogoBuilder].
  final WidgetBuilder? logoBuilder;

  /// The builder used for the attribution button.
  ///
  /// It receives a callback that opens the widget built by
  /// [attributionDialogBuilder]. If this builder is null, no button is displayed
  /// even when [attributionButtonEnabled] is true.
  ///
  /// Defaults to [defaultAttributionButtonBuilder].
  final AttributionButtonWidgetBuilder? attributionButtonBuilder;

  /// The builder used for the dialog opened by the attribution button.
  ///
  /// The widget is shown with [showDialog]. If this builder is null, the button
  /// can remain visible but its callback does not open a dialog.
  ///
  /// Defaults to [defaultAttributionDialogBuilder].
  final WidgetBuilder? attributionDialogBuilder;

  /// The builder used for the scale control.
  ///
  /// It receives the formatted distance and logical width in a [ScaleBarValue].
  /// If this builder is null, no scale is displayed even when
  /// [scaleControlEnabled] is true.
  ///
  /// Defaults to [defaultScaleControlBuilder].
  final ScaleControlWidgetBuilder? scaleControlBuilder;

  /// Builds the default compass for the supplied bearing.
  ///
  /// The compass rotates against the bearing, calls the supplied reset
  /// callback when pressed, and fades out while the bearing is north.
  static const CompassWidgetBuilder defaultCompassBuilder = buildDefaultCompass;

  /// Builds the default non-interactive MapLibre logo.
  static const WidgetBuilder defaultLogoBuilder = buildDefaultMapLibreLogo;

  /// Builds the default attribution button.
  ///
  /// Pressing the button calls the supplied callback.
  static const AttributionButtonWidgetBuilder defaultAttributionButtonBuilder =
      buildDefaultAttributionButton;

  /// Builds the default dialog from attribution declared by the active style.
  ///
  /// Source attribution links call [onAttributionLinkTap] when it is configured.
  static const WidgetBuilder defaultAttributionDialogBuilder =
      buildDefaultAttributionDialog;

  /// Builds the default non-interactive scale bar from a [ScaleBarValue].
  static const ScaleControlWidgetBuilder defaultScaleControlBuilder =
      buildDefaultScaleControl;

  /// The color passed to [loadingBuilder] while the active style is loading.
  ///
  /// [defaultLoadingBuilder] displays this color over the map. A custom builder
  /// can interpret or ignore it. If this is null, the default builder returns an
  /// empty widget.
  ///
  /// Defaults to [Colors.transparent].
  final Color? foregroundLoadColor;

  /// The builder used while the active style is loading.
  ///
  /// This builder is used for the initial style and for later style
  /// replacements. Its widget is displayed above the rendered map and symbols,
  /// below the map controls, and does not receive pointer events. If this
  /// builder is null, no loading overlay is displayed.
  ///
  /// Defaults to [defaultLoadingBuilder].
  final MapLoadingWidgetBuilder? loadingBuilder;

  /// The builder used when initial map creation fails.
  ///
  /// Initial style resolution and renderer startup are part of map creation.
  /// The returned widget replaces the map. If this builder is null,
  /// initialization failures produce an empty widget.
  ///
  /// Defaults to [defaultErrorBuilder].
  final MapErrorWidgetBuilder? errorBuilder;

  /// Builds the default loading overlay for `foregroundLoadColor`.
  ///
  /// A null color produces a [SizedBox.shrink]. Any other color produces a
  /// [ColoredBox] that fills the map.
  static Widget defaultLoadingBuilder(
    BuildContext context,
    Color? foregroundLoadColor,
  ) => foregroundLoadColor == null
      ? const SizedBox.shrink()
      : ColoredBox(color: foregroundLoadColor);

  /// Builds the default [ErrorWidget] for an initialization error message.
  static Widget defaultErrorBuilder(BuildContext context, String error) =>
      ErrorWidget(error);

  /// The builder used for the icon portion of each placed symbol.
  ///
  /// The returned widget is centered on [MapSymbol.iconPos] and does not receive
  /// pointer events. Returning null hides the icon for that symbol. If this
  /// builder is null, all symbol icons are hidden.
  ///
  /// When the same location appears more than once on screen, such as when
  /// zooming out, the same symbol may be placed multiple times. Each placement
  /// needs an independent widget and must not share a [GlobalKey].
  ///
  /// Defaults to [defaultSymbolIconBuilder].
  final SymbolWidgetBuilder? symbolIconBuilder;

  /// The builder used for the text portion of each placed symbol.
  ///
  /// The returned widget is centered on [MapSymbol.textPos] and does not receive
  /// pointer events. Returning null hides the text for that symbol. If this
  /// builder is null, all symbol text is hidden.
  ///
  /// When the same location appears more than once on screen, such as when
  /// zooming out, the same symbol may be placed multiple times. Each placement
  /// needs an independent widget and must not share a [GlobalKey].
  ///
  /// Defaults to [defaultSymbolTextBuilder].
  final SymbolWidgetBuilder? symbolTextBuilder;

  /// The duration of symbol fade-in and fade-out animations.
  ///
  /// This value must be non-negative. [Duration.zero] disables the transition.
  ///
  /// Defaults to 150 milliseconds.
  final Duration symbolFadeDuration;

  /// The area outside the viewport in which symbols remain built.
  ///
  /// This area is reevaluated when symbols move. Crossing its boundary rebuilds
  /// the affected overlay, while movement inside it only updates layout. Insets
  /// are measured in logical pixels. Every component must be finite and
  /// non-negative. If any component is invalid, [EdgeInsets.zero] is used.
  ///
  /// Defaults to 120 logical pixels horizontally and 60 logical pixels
  /// vertically.
  final EdgeInsets symbolCullingPadding;

  /// How symbol widgets are composited with native style layers.
  ///
  /// [SymbolCompositingMode.interleaved] preserves style layer order.
  /// [SymbolCompositingMode.fastOverlay] uses one native GPU surface and places
  /// all symbol widgets above it. Both modes keep symbol icons and text as
  /// Flutter widgets and use [symbolIconBuilder] and [symbolTextBuilder].
  ///
  /// Enabling [gpuMapRenderCallback] or [gpuRenderCallback] already requires
  /// one native surface and therefore produces the fast overlay ordering.
  ///
  /// Defaults to [SymbolCompositingMode.interleaved].
  final SymbolCompositingMode symbolCompositingMode;

  /// Builds the default style-derived sprite icon for a placed symbol.
  ///
  /// The result uses the evaluated icon scale, opacity, and color. It is null
  /// when the symbol has no resolved sprite.
  static const SymbolWidgetBuilder defaultSymbolIconBuilder =
      buildDefaultSymbolIcon;

  /// Builds the default style-derived text for a placed symbol.
  ///
  /// The result uses the evaluated font, size, color, halo, opacity, and
  /// placement angle. It is null when MapLibre did not place non-empty text.
  static const SymbolWidgetBuilder defaultSymbolTextBuilder =
      buildDefaultSymbolText;

  /// The callback that records geographic Flutter GPU geometry in the map.
  ///
  /// It runs synchronously after the last fill-extrusion pass and shares that
  /// pass's depth buffer. Nearer MapLibre buildings can occlude the custom
  /// geometry, while the custom geometry can occlude farther buildings. Later
  /// native style layers retain their normal order.
  ///
  /// Enabling either GPU callback uses one native GPU surface so final callback
  /// ordering remains stable. Flutter symbol widgets are composited above that
  /// surface instead of interleaving with native style layers.
  ///
  /// The callback must not submit or retain the supplied render pass. If null,
  /// no geometry is inserted into the map sequence.
  ///
  /// Defaults to null.
  final MapLibreGpuRenderCallback? gpuMapRenderCallback;

  /// The callback that records a final Flutter GPU overlay above the map.
  ///
  /// It runs synchronously during paint with the map's GPU context, color
  /// target, and the exact frame's geographic transform when the renderer
  /// provides one. The GPU overlay is painted below Flutter symbol and control
  /// widgets. Enabling either GPU callback uses the single-surface composition
  /// described by [gpuMapRenderCallback]. See
  /// [MapLibreGpuRenderContext.mapTransform].
  ///
  /// The callback must not submit or retain the supplied render pass. If null,
  /// no final GPU overlay is recorded. See [MapLibreGpuRenderContext].
  ///
  /// Defaults to null.
  final MapLibreGpuRenderCallback? gpuRenderCallback;

  /// A signal that requests repainting of custom GPU content.
  ///
  /// Each notification replays the current map frame into a fresh target and
  /// calls [gpuMapRenderCallback] and [gpuRenderCallback] without requiring
  /// a widget rebuild.
  ///
  /// The object that creates this listenable remains responsible for disposing
  /// it. The map only adds and removes its listener.
  ///
  /// Defaults to null.
  final Listenable? gpuRepaint;

  /// The depth initialization used by the final [gpuRenderCallback] overlay.
  ///
  /// This does not affect [gpuMapRenderCallback], which always shares MapLibre's
  /// depth buffer.
  ///
  /// Defaults to [MapLibreGpuDepthMode.isolated].
  final MapLibreGpuDepthMode gpuOverlayDepthMode;

  @override
  State<MapLibreMap> createState() => _MapLibreMapState();
}
