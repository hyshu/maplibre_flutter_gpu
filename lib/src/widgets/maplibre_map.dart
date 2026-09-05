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
import 'symbol_overlay.dart';

/// Signature for a callback that receives a newly created map controller.
///
/// The callback runs once after a [MapLibreMap] successfully initializes its
/// renderer. The initial style might not have loaded yet. The map owns the
/// controller and disposes it when the widget is removed.
typedef MapCreatedCallback = void Function(MapLibreMapController controller);

/// Signature for a callback that runs after the active style has loaded.
///
/// The callback runs for the initial style and for each later style
/// replacement.
typedef OnStyleLoadedCallback = void Function();

/// Signature for a callback that receives each observed camera position.
///
/// Positions can result from gestures or commands sent through
/// [MapLibreMapController].
typedef OnCameraMoveCallback = void Function(CameraPosition cameraPosition);

/// Signature for a callback that runs when camera movement ends.
///
/// The movement can result from a gesture or a command sent through
/// [MapLibreMapController]. Scroll-wheel zoom does not have a completion phase
/// and does not call this callback.
typedef OnCameraIdleCallback = void Function();

/// Signature for a callback that runs when the map is fully settled.
///
/// A settled map has a loaded style, no pending map work, no active camera
/// transition, and no Flutter fling animation.
typedef OnMapIdleCallback = void Function();

/// Signature for callbacks that receive a point selected on the map.
///
/// `point` is measured in logical pixels from the map's top-left corner.
/// `coordinates` is the geographic position at that point.
typedef OnMapClickCallback = void Function(
  math.Point<double> point,
  LatLng coordinates,
);

/// Signature for building the overlay displayed while a map style is loading.
///
/// `foregroundLoadColor` is the value configured by
/// [MapLibreMap.foregroundLoadColor] and can be null. The returned widget does
/// not receive pointer events.
typedef MapLoadingWidgetBuilder = Widget Function(
  BuildContext context,
  Color? foregroundLoadColor,
);

/// Signature for building the replacement shown when initialization fails.
///
/// `error` contains the initialization error message.
typedef MapErrorWidgetBuilder = Widget Function(
  BuildContext context,
  String error,
);

/// Controls how Flutter symbol widgets are composited with native style layers.
enum SymbolCompositingMode {
  /// Interleaves native GPU surfaces and symbol widgets in style layer order.
  ///
  /// This preserves the relative order of symbol and non-symbol style layers,
  /// but may require more than one full-size GPU surface.
  interleaved,

  /// Renders the native map once and places every symbol widget above it.
  ///
  /// This minimizes GPU surfaces and render passes. Symbol icons and text
  /// remain Flutter widgets and continue to use the configured builders. Their
  /// relative order with native layers above their style layer is not preserved.
  fastOverlay,
}

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
  /// Scroll-wheel zoom does not have a completion phase and does not call this
  /// callback. Camera idle does not imply that tiles or other map work have
  /// finished. Use [onMapIdle] to observe the fully settled state.
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

  /// Whether the controller notifies its listeners when the camera moves.
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

class _MapLibreMapState extends State<MapLibreMap>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver
    implements MapGestureHost {
  late final MaplibreBridge _bridge;
  var _hasBridge = false;
  GpuFrameRenderer? _gpuRenderer;
  final _gpuStratumResources = MapGpuResourcePool();
  MapLibreMapController? _controller;
  var _initializing = false;
  var _initialized = false;
  var _rendered = false;
  String? _initializationError;

  late final MapRenderScheduler _renders;
  final _labels = MapLabelSource();
  final _style = MapStyleSession<SpriteAtlas>(
    loadAtlas: SpriteAtlas.load,
    disposeAtlas: (atlas) => atlas.dispose(),
  );

  final _viewport = MapViewport();
  final _gpuFrame = ValueNotifier(0);
  final _symbolVersion = ValueNotifier(0);
  final _symbolLayoutVersion = ValueNotifier(0);
  final _controlsVersion = ValueNotifier(0);
  var _nativeCommandLayerIndices = const <int>{};
  var _symbolGpuStratumSlots = const <int>[0];
  NativeFrameSnapshotLease? _pendingFrameSnapshot;
  var _lastProcessedFrameGeneration = 0;
  var _applyingFrameSnapshot = false;
  var _releaseSnapshotAfterApply = false;
  Completer<void>? _styleMutationBarrier;

  late final MapGestureCoordinator _gestures;
  final _gestureRegionKey = GlobalKey();
  MacosTrackpadTiltRegistration? _macosTrackpadTilt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gestures = .new(vsync: this, host: this);
    _macosTrackpadTilt = MacosTrackpadTiltRegistration.register(
      onStart: _gestures.onMacosTrackpadTiltStart,
      onUpdate: _gestures.onMacosTrackpadTiltUpdate,
      onEnd: _gestures.onMacosTrackpadTiltEnd,
    );
    _renders = .new(
      isAlive: () => mounted && _initialized,
      hasPendingNativeWork: () => _hasBridge && _bridge.processEvents(),
      render: () {
        renderGesture();
        _finishScheduledRender();
      },
    );
  }

  Future<void> _initMap() async {
    if (_initializing || _initialized || _initializationError != null) return;
    _initializing = true;
    try {
      if (!mounted) return;

      final viewport = _viewport.applied;
      if (viewport == null) return;
      final shaderLibrary = await loadMapShaderLibrary();
      if (!mounted) return;
      if (!_hasBridge) {
        final bridge = await MaplibreBridge.create();
        if (!mounted) {
          bridge.destroy();

          return;
        }
        _bridge = bridge;
        _hasBridge = true;
      }

      final style = await resolveRequestedStyle(
        requestedStyle: () => widget.styleString,
        isAlive: () => mounted,
      );
      if (style == null) return;
      // Layout can change while shaders, the bridge, or the style are loading.
      final latestViewport = _viewport.applied!;
      _viewport.adoptForInitialization(
        latestViewport.logicalSize,
        latestViewport.dpr,
      );
      final gpuRenderer = GpuFrameRenderer(
        bridge: _bridge,
        shaders: shaderLibrary,
      );
      if (!_startNativeMap(style.resolved)) {
        gpuRenderer.dispose();

        return;
      }
      _bindNativeMap(
        requested: style.requested,
        resolved: style.resolved,
        gpuRenderer: gpuRenderer,
      );
      await _pumpUntilStyleLoaded();
      if (!mounted) return;

      // Register native render requests after synchronous startup completes.
      _rendered = true;
      _bridge.setRenderRequestHandler(_onNativeRenderRequested);
      renderGesture();
      setState(() {});
      scheduleRepaint();
    } catch (error, stackTrace) {
      debugPrint('[MapLibreMap] initialization failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _initializationError = error.toString());
      }
    } finally {
      _initializing = false;
    }
  }

  /// Starts the native map and records any initialization error.
  bool _startNativeMap(String resolvedStyle) {
    final result = _bridge.init(
      _viewport.logicalWidth,
      _viewport.logicalHeight,
      _viewport.devicePixelRatio,
      resolvedStyle,
    );
    if (result == MaplibreBridge.initSuccess) {
      _initialized = true;

      return true;
    }
    final message = result == MaplibreBridge.initBusy
        ? 'A native map session is already active. Dispose it before retrying.'
        : 'MapLibre native initialization failed (error $result).';
    debugPrint('[MapLibreMap] $message');
    if (mounted) {
      setState(() => _initializationError = message);
    }
    return false;
  }

  /// Connects the Dart controller and renderer to the native map.
  void _bindNativeMap({
    required String requested,
    required String resolved,
    required GpuFrameRenderer gpuRenderer,
  }) {
    _gpuRenderer = gpuRenderer;
    _bridge.devicePixelRatio = _viewport.devicePixelRatio;

    _loadSpriteAtlas(resolved, baseStyleUrl: requested);

    final initial = widget.initialCameraPosition;
    if (initial != null) {
      _bridge.setCameraFull(
        initial.target.latitude,
        initial.target.longitude,
        initial.zoom,
        initial.bearing,
        initial.tilt,
      );
    }

    _controller = MapLibreMapController.bind(
      _bridge,
      onCameraChangeRequested: _onProgrammaticCameraChange,
      onStyleChangeRequested: _onProgrammaticStyleChange,
      beforeStyleMutation: _releaseFrameSnapshotBeforeStyleMutation,
      onStyleMutationRequested: _onProgrammaticStyleMutation,
      placedLabelsProvider: _placedLabelsForController,
    );
    widget.onMapCreated?.call(_controller!);
  }

  /// Renders until the style is loaded across consecutive frames.
  ///
  /// Stops after a bounded number of attempts.
  Future<void> _pumpUntilStyleLoaded() async {
    for (var attempt = 0; attempt < 100; attempt++) {
      _bridge.frameBegin();
      _bridge.renderFrame();
      _bridge.frameEnd();
      final wasStyleLoaded = _style.isLoaded;
      _updateStyleLoadedState();
      if (_style.isLoaded && wasStyleLoaded) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
  }

  void _applyCameraConstraints() {
    final bounds = widget.cameraTargetBounds.bounds;
    final zoom = widget.minMaxZoomPreference;
    final tilt = widget.minMaxTiltPreference;
    // Widen each range first so both upward and downward changes are valid.
    _bridge.setBounds(
      south: bounds?.southwest.latitude,
      west: bounds?.west,
      north: bounds?.northeast.latitude,
      east: bounds?.east,
    );
    _bridge.setBounds(
      south: bounds?.southwest.latitude,
      west: bounds?.west,
      north: bounds?.northeast.latitude,
      east: bounds?.east,
      minZoom: zoom.minZoom,
      maxZoom: zoom.maxZoom,
    );
    _bridge.setMinPitch(0);
    _bridge.setMaxPitch(180);
    _bridge.setMinPitch(tilt.minTilt ?? 0);
    _bridge.setMaxPitch(tilt.maxTilt ?? 60);
  }

  void _updateStyleLoadedState() {
    if (_style.isLoaded || !_bridge.isStyleLoaded()) return;
    _style.markLoaded();
    _applyCameraConstraints();
    widget.onStyleLoadedCallback?.call();
  }

  void _loadSpriteAtlas(String styleSource, {String? baseStyleUrl}) {
    unawaited(
      _style
          .loadSpriteAtlas(
            styleSource,
            baseStyleUrl: baseStyleUrl,
            isAlive: () => mounted && _initialized,
          )
          .then((adopted) {
            if (!adopted) return;
            setState(() {
              _labels.cacheScreenPositions(_bridge, _style.spriteAtlas);
            });
          }),
    );
  }

  Future<void> _onProgrammaticStyleChange(
    String styleString,
    String resolvedStyle,
  ) async {
    if (!mounted || !_initialized) {
      throw StateError('MapLibreMap is not available for a style change');
    }
    setState(() {
      _style.beginStyleChange();
      _labels.reset();
    });
    _programmaticCameraIdlePending = false;
    _bridge.setStyle(resolvedStyle);
    _loadSpriteAtlas(resolvedStyle, baseStyleUrl: styleString);
    renderGesture();
    scheduleRepaint();
  }

  Future<void> _releaseFrameSnapshotBeforeStyleMutation() {
    if (_applyingFrameSnapshot) {
      _releaseSnapshotAfterApply = true;

      return (_styleMutationBarrier ??= .new()).future;
    }
    _releasePendingFrameSnapshot();

    return Future<void>.value();
  }

  void _releasePendingFrameSnapshot() {
    final snapshot = _pendingFrameSnapshot;
    _pendingFrameSnapshot = null;
    snapshot?.release();
  }

  void _finishApplyingFrameSnapshot() {
    _applyingFrameSnapshot = false;
    if (!_releaseSnapshotAfterApply) return;
    _releaseSnapshotAfterApply = false;
    final barrier = _styleMutationBarrier;
    _styleMutationBarrier = null;
    try {
      _releasePendingFrameSnapshot();
      barrier?.complete();
    } catch (error, stackTrace) {
      barrier?.completeError(error, stackTrace);
    }
  }

  List<LabelData> _placedLabelsForController() => _labels.placedLabels;

  bool _gpuRenderingAllowed() =>
      _initialized && _rendered && _renders.isAppActive;

  void _onProgrammaticStyleMutation() {
    if (!mounted || !_initialized) return;
    renderGesture();
    scheduleRepaint();
  }

  void _scheduleViewportUpdate(Size logicalSize, double dpr) {
    if (!_viewport.request(logicalSize, dpr)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _viewport.cancel();

        return;
      }
      final viewport = _viewport.takePending();
      if (viewport == null) return;
      _applyViewport(viewport.logicalSize, viewport.dpr);
    });
  }

  void _applyViewport(Size logicalSize, double observedDpr) {
    final resized = _viewport.applyLayout(
      logicalSize,
      observedDpr,
      initialized: _initialized,
    );
    if (!_initialized) {
      if (!_initializing) _initMap();

      return;
    }
    if (!resized) return;
    final bridge = _bridge;
    // Release the previous-size snapshot before rendering the resized map.
    final staleSnapshot =
        _pendingFrameSnapshot ?? bridge.acquireFrameSnapshot();
    _pendingFrameSnapshot = null;
    try {
      bridge.setSize(_viewport.logicalWidth, _viewport.logicalHeight);
    } finally {
      staleSnapshot?.release();
    }
    renderGesture();
    if (mounted) setState(() {});
    scheduleRepaint();
  }

  var _programmaticCameraIdlePending = false;

  @override
  void scheduleRepaint() {
    if (_renders.isRepaintPending || !_initialized || !_renders.isAppActive) {
      return;
    }
    final bridge = _bridge;
    final needsRepaint = bridge.frameNeedsRepaint;
    final cameraMoving = bridge.isCameraMoving();
    final flingAnimating = _gestures.isFlinging;
    final mapIdle = bridge.isMapIdle();
    if (isMapRenderSettled(
      styleLoaded: _style.isLoaded,
      mapIdle: mapIdle,
      cameraMoving: cameraMoving,
      flingAnimating: flingAnimating,
    )) {
      widget.onMapIdle?.call();

      return;
    }
    if (!shouldScheduleFrame(
      needsRepaint: needsRepaint,
      cameraMoving: cameraMoving,
      flingAnimating: flingAnimating,
      supportsEventDrivenRendering: bridge.supportsEventDrivenRendering,
      styleLoaded: _style.isLoaded,
      mapIdle: mapIdle,
    )) {
      return;
    }
    final needsContinuousFrame = needsRepaint || cameraMoving || flingAnimating;
    final interval = needsContinuousFrame
        ? const Duration(milliseconds: 16)
        : const Duration(milliseconds: 150);
    _renders.scheduleRepaint(interval);
  }

  void _onNativeRenderRequested() {
    if (!mounted || !_initialized) return;
    _renders.scheduleNativeRender();
  }

  void _finishScheduledRender() {
    _emitProgrammaticCameraIdleIfSettled();
    if (isMapRenderSettled(
      styleLoaded: _style.isLoaded,
      mapIdle: _bridge.isMapIdle(),
      cameraMoving: _bridge.isCameraMoving(),
      flingAnimating: _gestures.isFlinging,
    )) {
      widget.onMapIdle?.call();

      return;
    }
    scheduleRepaint();
  }

  void _onProgrammaticCameraChange() {
    if (!mounted || !_initialized) return;
    _gestures.stopFling();
    _programmaticCameraIdlePending = true;
    // Coalesce camera updates and native render requests into one frame.
    _renders.scheduleNativeRender(force: true);
  }

  void _emitProgrammaticCameraIdleIfSettled() {
    if (!_programmaticCameraIdlePending || _bridge.isCameraMoving()) return;
    _programmaticCameraIdlePending = false;
    widget.onCameraIdle?.call();
  }

  @override
  void renderGesture() {
    // Leave startup snapshots to the synchronous initialization pump.
    if (!_initialized || !_rendered) return;
    if (!_renders.isAppActive) {
      _renders.deferToResume();

      return;
    }
    final bridge = _bridge;
    final usesAsyncRendering = bridge.supportsAsyncRendering;
    NativeFrameSnapshotLease? acquiredSnapshot;
    if (usesAsyncRendering) {
      final pendingSnapshot = _pendingFrameSnapshot;
      if (pendingSnapshot?.isActive ?? false) {
        // Repaint an applied snapshot without advancing frame state again.
        _gpuFrame.value++;
        bridge.renderFrameAsync();

        return;
      }
      _pendingFrameSnapshot = null;
      acquiredSnapshot = bridge.acquireFrameSnapshot();
      if (acquiredSnapshot == null) {
        bridge.renderFrameAsync();

        return;
      }
      if (acquiredSnapshot.generation == _lastProcessedFrameGeneration) {
        acquiredSnapshot.release();
        bridge.renderFrameAsync();

        return;
      }
      _pendingFrameSnapshot = acquiredSnapshot;
    } else {
      bridge.frameBegin();
      bridge.renderFrame();
      bridge.frameEnd();
    }
    _applyingFrameSnapshot = true;
    try {
      final wasStyleLoaded = _style.isLoaded;
      final wasRendered = _rendered;
      _updateStyleLoadedState();
      final controller = _controller;
      final cameraChanged =
          controller?.notifyCameraChanged(
            notifyListeners: widget.trackCameraPosition,
          ) ??
          false;
      final nextZoom =
          controller?.cameraPosition?.zoom ?? _bridge.getCameraZoom();
      _gpuRenderer?.zoom = nextZoom;
      _gpuRenderer?.frameSeq++;
      _rendered = true;
      final labelsChanged = _labels.syncFromNative(bridge);
      final nextNativeCommandLayerIndices = _gpuRenderer!.commandLayerIndices(
        bridge.frameGetMetadata(),
      );
      final spriteAtlasChanged = _labels.hasDifferentSpriteAtlas(
        _style.spriteAtlas,
      );
      final labelsNeedProjection =
          labelsChanged ||
          spriteAtlasChanged ||
          (cameraChanged && _labels.entries.isNotEmpty);
      if (labelsNeedProjection) {
        _labels.cacheScreenPositions(bridge, _style.spriteAtlas);
      }
      final usesSingleGpuSurface =
          widget.gpuMapRenderCallback != null ||
          widget.gpuRenderCallback != null ||
          widget.symbolCompositingMode == .fastOverlay;
      final nextSymbolGpuStratumSlots = usesSingleGpuSurface
          ? const <int>[0]
          : symbolGpuStratumSlots(
              _labels.symbolLayerIndices,
              nativeCommandLayerIndices: nextNativeCommandLayerIndices,
            );
      final symbolGpuTopologyChanged = !listEquals(
        _symbolGpuStratumSlots,
        nextSymbolGpuStratumSlots,
      );
      _nativeCommandLayerIndices = nextNativeCommandLayerIndices;
      _symbolGpuStratumSlots = nextSymbolGpuStratumSlots;
      if (cameraChanged && widget.onCameraMove != null) {
        final pos = controller?.cameraPosition;
        if (pos != null) widget.onCameraMove?.call(pos);
      }
      if (acquiredSnapshot != null) {
        _lastProcessedFrameGeneration = acquiredSnapshot.generation;
      }
      _gpuFrame.value++;
      if (!wasRendered || (!wasStyleLoaded && _style.isLoaded)) {
        setState(() {});
      } else {
        if (labelsChanged || spriteAtlasChanged || symbolGpuTopologyChanged) {
          _symbolVersion.value++;
        } else if (labelsNeedProjection) {
          _symbolLayoutVersion.value++;
        }
        if (cameraChanged &&
            (widget.compassEnabled || widget.scaleControlEnabled)) {
          _controlsVersion.value++;
        }
      }
      // Queue native work after all synchronous frame state has been read.
      if (usesAsyncRendering) {
        bridge.renderFrameAsync();
      }
    } catch (_) {
      if (identical(_pendingFrameSnapshot, acquiredSnapshot)) {
        _pendingFrameSnapshot = null;
      }
      acquiredSnapshot?.release();
      rethrow;
    } finally {
      _finishApplyingFrameSnapshot();
    }
  }

  void _onFrameSnapshotReleased(NativeFrameSnapshotLease snapshot) {
    if (identical(_pendingFrameSnapshot, snapshot)) {
      _pendingFrameSnapshot = null;
    }
  }

  NativeFrameSnapshotLease? _frameSnapshotForPaint() => _pendingFrameSnapshot;

  @override
  void didUpdateWidget(covariant MapLibreMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final scaleGesturesDisabled =
        !widget.scrollGesturesEnabled &&
        !widget.zoomGesturesEnabled &&
        !widget.rotateGesturesEnabled &&
        !widget.tiltGesturesEnabled;
    final scaleGesturesWereEnabled =
        oldWidget.scrollGesturesEnabled ||
        oldWidget.zoomGesturesEnabled ||
        oldWidget.rotateGesturesEnabled ||
        oldWidget.tiltGesturesEnabled;
    final flingDisabled =
        !widget.scrollGesturesEnabled || !widget.gestureOptions.flingEnabled;
    if ((scaleGesturesWereEnabled && scaleGesturesDisabled) ||
        (flingDisabled && _gestures.isFlinging)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scaleGesturesStillDisabled =
            !widget.scrollGesturesEnabled &&
            !widget.zoomGesturesEnabled &&
            !widget.rotateGesturesEnabled &&
            !widget.tiltGesturesEnabled;
        if (scaleGesturesStillDisabled) {
          _gestures.cancelScaleGestureAndEndGesture();
        }
        if (!widget.scrollGesturesEnabled ||
            !widget.gestureOptions.flingEnabled) {
          _gestures.cancelFlingAndEndGesture();
        }
      });
    }
    if (_initialized && oldWidget.styleString != widget.styleString) {
      final controller = _controller;
      if (controller != null) {
        unawaited(
          controller.setStyle(widget.styleString).catchError((
            Object error,
            StackTrace stackTrace,
          ) {
            debugPrint(
              '[MapLibreMap] style update failed: $error\n$stackTrace',
            );
          }),
        );
      }
      return;
    }
    if (!_initialized || !_style.isLoaded) return;
    if (oldWidget.cameraTargetBounds == widget.cameraTargetBounds &&
        oldWidget.minMaxZoomPreference == widget.minMaxZoomPreference &&
        oldWidget.minMaxTiltPreference == widget.minMaxTiltPreference) {
      return;
    }
    _applyCameraConstraints();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_initialized) return;
      renderGesture();
      scheduleRepaint();
    });
  }

  @override
  void dispose() {
    _initialized = false;
    WidgetsBinding.instance.removeObserver(this);
    _macosTrackpadTilt?.dispose();
    _renders.dispose();
    _gestures.dispose();
    _controller?.dispose();
    _controller = null;
    _pendingFrameSnapshot?.release();
    _pendingFrameSnapshot = null;
    if (_hasBridge) {
      _hasBridge = false;
      _bridge.destroy();
    }
    _gpuRenderer?.dispose();
    _gpuRenderer = null;
    _gpuStratumResources.dispose();
    _gpuFrame.dispose();
    _symbolVersion.dispose();
    _symbolLayoutVersion.dispose();
    _controlsVersion.dispose();
    _labels.reset();
    _style.dispose();
    _viewport.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _renders.setAppActive(state == .resumed);

  Widget _buildSymbolOverlay(
    Size screenSize,
    SymbolWidgetStratum<MapSymbol> stratum,
  ) {
    List<MapSymbol> currentSymbols() =>
        _labels.liveSymbolsForLayer(stratum.layerIndex);

    return MapSymbolOverlay(
      key: ValueKey('symbols:${stratum.layerIndex}'),
      symbols: stratum.symbols,
      symbolsProvider: currentSymbols,
      relayout: _symbolLayoutVersion,
      screenSize: screenSize,
      iconBuilder: widget.symbolIconBuilder,
      textBuilder: widget.symbolTextBuilder,
      fadeDuration: widget.symbolFadeDuration,
      cullingPadding: widget.symbolCullingPadding,
      onFadedOut: _labels.onFadedOut,
    );
  }

  Widget _buildRenderedMap(Size screenSize) {
    if (!_rendered) return const SizedBox.expand();
    final preservesGpuCallbackOrder =
        widget.gpuMapRenderCallback != null || widget.gpuRenderCallback != null;
    final usesSingleGpuSurface =
        preservesGpuCallbackOrder ||
        widget.symbolCompositingMode == .fastOverlay;
    final composition = composeSymbolLayers(
      _labels.symbols,
      layerIndexOf: (symbol) => symbol.data.layerIndex,
      nativeCommandLayerIndices: _nativeCommandLayerIndices,
      singleGpuSurface: usesSingleGpuSurface,
    );
    final List<({int? maximumLayerIndex, int? minimumLayerIndex})>
    gpuLayerRanges = .unmodifiable([
      for (final stratum in composition.gpuStrata)
        (
          minimumLayerIndex: stratum.minimumLayerIndex,
          maximumLayerIndex: stratum.maximumLayerIndex,
        ),
    ]);
    final lastGpuIndex = composition.gpuStrata.length - 1;
    final repaint = Listenable.merge([
      _gpuFrame,
      if (widget.gpuRepaint != null) widget.gpuRepaint!,
    ]);
    final children = <Widget>[];
    if (preservesGpuCallbackOrder) {
      children.add(
        IgnorePointer(
          child: _MapGpuStratum(
            key: const ValueKey<String>('gpu:callbacks'),
            bridge: _bridge,
            gpuRenderer: _gpuRenderer!,
            resources: _gpuStratumResources.acquire(
              0,
              minimumLayerIndex: null,
              maximumLayerIndex: null,
              clearToTransparent: false,
            ),
            width: _viewport.physicalWidth,
            height: _viewport.physicalHeight,
            logicalWidth: _viewport.logicalWidth,
            logicalHeight: _viewport.logicalHeight,
            devicePixelRatio: _viewport.devicePixelRatio,
            frameSeq: _gpuRenderer!.frameSeq,
            gpuMapRenderCallback: widget.gpuMapRenderCallback,
            gpuRenderCallback: widget.gpuRenderCallback,
            gpuOverlayDepthMode: widget.gpuOverlayDepthMode,
            gpuRenderingAllowed: _gpuRenderingAllowed,
            frameSnapshotProvider: _frameSnapshotForPaint,
            onFrameSnapshotReleased: _onFrameSnapshotReleased,
            stratumIndex: 0,
            layerRanges: gpuLayerRanges,
            minimumLayerIndex: null,
            maximumLayerIndex: null,
            clearToTransparent: false,
            releaseFrameSnapshot: true,
            advanceResourceFrame: true,
            evictResourceCaches: true,
            repaint: repaint,
          ),
        ),
      );
      for (final stratum in composition.widgetStrata) {
        children.add(_buildSymbolOverlay(screenSize, stratum));
      }
      _gpuStratumResources.trimToActiveSlotCount(gpuLayerRanges.length);

      return Stack(fit: .expand, clipBehavior: .hardEdge, children: children);
    }

    void addGpuStratum(int index) {
      final stratum = composition.gpuStrata[index];
      final isFirst = index == 0;
      final isLast = index == lastGpuIndex;
      children.add(
        IgnorePointer(
          child: _MapGpuStratum(
            key: ValueKey('gpu:$index'),
            bridge: _bridge,
            gpuRenderer: _gpuRenderer!,
            resources: _gpuStratumResources.acquire(
              index,
              minimumLayerIndex: stratum.minimumLayerIndex,
              maximumLayerIndex: stratum.maximumLayerIndex,
              clearToTransparent: stratum.clearToTransparent,
            ),
            width: _viewport.physicalWidth,
            height: _viewport.physicalHeight,
            logicalWidth: _viewport.logicalWidth,
            logicalHeight: _viewport.logicalHeight,
            devicePixelRatio: _viewport.devicePixelRatio,
            frameSeq: _gpuRenderer!.frameSeq,
            gpuMapRenderCallback: null,
            gpuRenderCallback: null,
            gpuOverlayDepthMode: widget.gpuOverlayDepthMode,
            gpuRenderingAllowed: _gpuRenderingAllowed,
            frameSnapshotProvider: _frameSnapshotForPaint,
            onFrameSnapshotReleased: _onFrameSnapshotReleased,
            stratumIndex: index,
            layerRanges: gpuLayerRanges,
            minimumLayerIndex: stratum.minimumLayerIndex,
            maximumLayerIndex: stratum.maximumLayerIndex,
            clearToTransparent: stratum.clearToTransparent,
            releaseFrameSnapshot: isLast,
            advanceResourceFrame: isFirst,
            evictResourceCaches: isLast,
            repaint: repaint,
          ),
        ),
      );
    }

    var nextGpuIndex = 0;
    void addGpuStrataAfter(int widgetStrataCount) {
      while (nextGpuIndex < composition.gpuStrata.length &&
          composition.gpuStrata[nextGpuIndex].widgetStrataBefore ==
              widgetStrataCount) {
        addGpuStratum(nextGpuIndex++);
      }
    }

    addGpuStrataAfter(0);
    for (var index = 0; index < composition.widgetStrata.length; index += 1) {
      children.add(
        _buildSymbolOverlay(screenSize, composition.widgetStrata[index]),
      );
      addGpuStrataAfter(index + 1);
    }
    assert(nextGpuIndex == composition.gpuStrata.length);
    _gpuStratumResources.trimToActiveSlotCount(gpuLayerRanges.length);

    return Stack(fit: .expand, clipBehavior: .hardEdge, children: children);
  }

  void _emitMapClick(Offset localPosition, OnMapClickCallback? callback) {
    if (!_initialized || callback == null) return;
    try {
      final coordinate = _bridge.screenToLatLon(
        localPosition.dx,
        localPosition.dy,
      );
      callback(
        .new(localPosition.dx, localPosition.dy),
        .new(coordinate.latitude, coordinate.longitude),
      );
    } on UnsupportedError catch (error) {
      debugPrint('[MapLibreMap] map click unavailable: $error');
    }
  }

  @override
  MaplibreBridge? get gestureBridge =>
      mounted && _initialized && _rendered ? _bridge : null;

  @override
  MapGestureSettings get gestureSettings => (
    scrollEnabled: widget.scrollGesturesEnabled,
    zoomEnabled: widget.zoomGesturesEnabled,
    rotateEnabled: widget.rotateGesturesEnabled,
    tiltEnabled: widget.tiltGesturesEnabled,
    doubleClickZoomEnabled: widget.doubleClickZoomEnabled,
  );

  @override
  MapGestureOptions get gestureOptions => widget.gestureOptions;

  @override
  Size get logicalMapSize => _viewport.logicalSize;

  @override
  void beginCameraGesture() {
    _programmaticCameraIdlePending = false;
    _controller?.notifyCameraGestureStarted();
  }

  @override
  void endCameraGesture() {
    widget.onCameraIdle?.call();
    scheduleRepaint();
  }

  @override
  Widget build(context) => LayoutBuilder(
    builder: (context, constraints) {
      final logicalSize = mapLayoutSize(constraints);
      if (logicalSize == null) return const SizedBox.shrink();

      final initializationError = _initializationError;
      if (initializationError != null) {
        return widget.errorBuilder?.call(context, initializationError) ??
            const SizedBox.shrink();
      }

      final dpr = MediaQuery.devicePixelRatioOf(context);
      _scheduleViewportUpdate(logicalSize, dpr);
      final scaleGesturesEnabled =
          widget.scrollGesturesEnabled ||
          widget.zoomGesturesEnabled ||
          widget.rotateGesturesEnabled ||
          widget.tiltGesturesEnabled;
      _scheduleMacosTrackpadTiltRegionUpdate();

      return ClipRect(
        child: Stack(
          fit: .expand,
          clipBehavior: .hardEdge,
          children: [
            const SizedBox.expand(),
            Listener(
              key: _gestureRegionKey,
              onPointerDown: _gestures.onPointerDown,
              onPointerMove: _gestures.onPointerMove,
              onPointerUp: _gestures.onPointerEnd,
              onPointerCancel: _gestures.onPointerEnd,
              onPointerSignal: _gestures.onPointerSignal,
              child: GestureDetector(
                behavior: .opaque,
                onScaleStart: scaleGesturesEnabled
                    ? _gestures.onScaleStart
                    : null,
                onScaleUpdate: scaleGesturesEnabled
                    ? _gestures.onScaleUpdate
                    : null,
                onScaleEnd: scaleGesturesEnabled ? _gestures.onScaleEnd : null,
                onTapUp: widget.onMapClick == null
                    ? null
                    : (details) => _emitMapClick(
                        details.localPosition,
                        widget.onMapClick,
                      ),
                onLongPressStart: widget.onMapLongClick == null
                    ? null
                    : (details) => _emitMapClick(
                        details.localPosition,
                        widget.onMapLongClick,
                      ),
                onDoubleTapDown:
                    doubleClickZoomIsEnabled(
                      widget.doubleClickZoomEnabled,
                      widget.zoomGesturesEnabled,
                    )
                    ? _gestures.onDoubleTapDown
                    : null,
                onDoubleTap:
                    doubleClickZoomIsEnabled(
                      widget.doubleClickZoomEnabled,
                      widget.zoomGesturesEnabled,
                    )
                    ? _gestures.onDoubleTap
                    : null,
                child: ValueListenableBuilder(
                  valueListenable: _symbolVersion,
                  builder: (context, _, _) => _buildRenderedMap(logicalSize),
                ),
              ),
            ),
            if (!_style.isLoaded && widget.loadingBuilder != null)
              IgnorePointer(
                child: widget.loadingBuilder!(
                  context,
                  widget.foregroundLoadColor,
                ),
              ),
            ValueListenableBuilder(
              valueListenable: _controlsVersion,
              builder: (context, _, _) => MapLibreMapControls(
                mapSize: logicalSize,
                controller: _controller,
                compassEnabled: widget.compassEnabled,
                logoEnabled: widget.logoEnabled,
                logoViewPosition: widget.logoViewPosition,
                logoViewMargins: widget.logoViewMargins,
                compassViewPosition: widget.compassViewPosition,
                compassViewMargins: widget.compassViewMargins,
                attributionButtonEnabled: widget.attributionButtonEnabled,
                attributionButtonPosition: widget.attributionButtonPosition,
                attributionButtonMargins: widget.attributionButtonMargins,
                onAttributionLinkTap: widget.onAttributionLinkTap,
                scaleControlEnabled: widget.scaleControlEnabled,
                scaleControlPosition: widget.scaleControlPosition,
                scaleControlUnit: widget.scaleControlUnit,
                scaleControlMargins: widget.scaleControlMargins,
                scaleControlMaxWidth: widget.scaleControlMaxWidth,
                scaleControlAvoidLogo: widget.scaleControlAvoidLogo,
                scaleControlLogoOffset: widget.scaleControlLogoOffset,
                compassBuilder: widget.compassBuilder,
                logoBuilder: widget.logoBuilder,
                attributionButtonBuilder: widget.attributionButtonBuilder,
                attributionDialogBuilder: widget.attributionDialogBuilder,
                scaleControlBuilder: widget.scaleControlBuilder,
              ),
            ),
          ],
        ),
      );
    },
  );

  void _scheduleMacosTrackpadTiltRegionUpdate() {
    final registration = _macosTrackpadTilt;
    if (registration == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box =
          _gestureRegionKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero);
      registration.updateRegion(
        origin & box.size,
        enabled: widget.tiltGesturesEnabled,
      );
    });
  }
}

class _MapGpuStratum extends StatefulWidget {
  final MaplibreBridge bridge;
  final GpuFrameRenderer gpuRenderer;
  final MapGpuResources resources;
  final int width;
  final int height;
  final int logicalWidth;
  final int logicalHeight;
  final double devicePixelRatio;
  final int frameSeq;
  final MapLibreGpuRenderCallback? gpuMapRenderCallback;
  final MapLibreGpuRenderCallback? gpuRenderCallback;
  final MapLibreGpuDepthMode gpuOverlayDepthMode;
  final bool Function() gpuRenderingAllowed;
  final NativeFrameSnapshotLease? Function() frameSnapshotProvider;
  final ValueChanged<NativeFrameSnapshotLease>? onFrameSnapshotReleased;
  final int stratumIndex;
  final List<GpuStyleLayerRange> layerRanges;
  final int? minimumLayerIndex;
  final int? maximumLayerIndex;
  final bool clearToTransparent;
  final bool releaseFrameSnapshot;
  final bool advanceResourceFrame;
  final bool evictResourceCaches;
  final Listenable repaint;

  const new({
    super.key,
    required this.bridge,
    required this.gpuRenderer,
    required this.resources,
    required this.width,
    required this.height,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.devicePixelRatio,
    required this.frameSeq,
    required this.gpuMapRenderCallback,
    required this.gpuRenderCallback,
    required this.gpuOverlayDepthMode,
    required this.gpuRenderingAllowed,
    required this.frameSnapshotProvider,
    required this.onFrameSnapshotReleased,
    required this.stratumIndex,
    required this.layerRanges,
    required this.minimumLayerIndex,
    required this.maximumLayerIndex,
    required this.clearToTransparent,
    required this.releaseFrameSnapshot,
    required this.advanceResourceFrame,
    required this.evictResourceCaches,
    required this.repaint,
  });

  @override
  State<_MapGpuStratum> createState() => _MapGpuStratumState();
}

class _MapGpuStratumState extends State<_MapGpuStratum> {
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: MapGpuPainter(
        bridge: widget.bridge,
        gpuRenderer: widget.gpuRenderer,
        resources: widget.resources,
        width: widget.width,
        height: widget.height,
        logicalWidth: widget.logicalWidth,
        logicalHeight: widget.logicalHeight,
        devicePixelRatio: widget.devicePixelRatio,
        frameSeq: widget.frameSeq,
        gpuMapRenderCallback: widget.gpuMapRenderCallback,
        gpuRenderCallback: widget.gpuRenderCallback,
        gpuOverlayDepthMode: widget.gpuOverlayDepthMode,
        gpuRenderingAllowed: widget.gpuRenderingAllowed,
        frameSnapshotProvider: widget.frameSnapshotProvider,
        onFrameSnapshotReleased: widget.onFrameSnapshotReleased,
        stratumIndex: widget.stratumIndex,
        layerRanges: widget.layerRanges,
        minimumLayerIndex: widget.minimumLayerIndex,
        maximumLayerIndex: widget.maximumLayerIndex,
        clearToTransparent: widget.clearToTransparent,
        releaseFrameSnapshot: widget.releaseFrameSnapshot,
        advanceResourceFrame: widget.advanceResourceFrame,
        evictResourceCaches: widget.evictResourceCaches,
        repaint: widget.repaint,
      ),
      size: Size.infinite,
    ),
  );
}
