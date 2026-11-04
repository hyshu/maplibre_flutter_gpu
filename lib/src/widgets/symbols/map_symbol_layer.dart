import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../labels/label_data.dart';
import '../../labels/label_source.dart';
import 'default_symbol_builders.dart';
import 'map_symbol.dart';
import 'symbol_overlay.dart';
import 'symbol_profile_counters.dart';

/// Whether Android symbol strata may retain an unchanged default overlay.
@internal
bool get symbolLayerReuseEnabled =>
    const bool.fromEnvironment('MAPLIBRE_REUSE_SYMBOL_LAYERS') &&
    defaultTargetPlatform == TargetPlatform.android;

bool get _diagnosticsEnabled =>
    const bool.fromEnvironment('MAPLIBRE_SYMBOL_LAYER_REUSE_DIAGNOSTICS') &&
    symbolLayerReuseEnabled &&
    SymbolProfileCounters.enabled;

/// Owns one symbol overlay and its live position notifications. Internal.
///
/// Symbols must be immutable snapshots from [labels] for [layerIndex]. A reused
/// child keeps its original snapshot. Only anchors may come from newer frames.
/// Custom builders always receive a normally updated overlay.
@internal
class const MapSymbolLayer({
  super.key,

  /// Source of live anchors and visibility-aware fade completion.
  required final MapLabelSource labels,

  /// Native style layer represented by this stratum.
  required final int layerIndex,

  /// Ordered immutable placements for the current composition.
  required final List<MapSymbol> symbols,

  /// Notifies the child to read the source's latest projected anchors.
  required final Listenable relayout,

  /// Logical viewport used for independent icon and text culling.
  required final Size screenSize,

  /// Icon builder. Only the exact default builder permits reuse.
  final SymbolWidgetBuilder? iconBuilder = buildDefaultSymbolIcon,

  /// Text builder. Only the exact default builder permits reuse.
  final SymbolWidgetBuilder? textBuilder = buildDefaultSymbolText,

  /// Duration of appearing and disappearing symbol transitions.
  final Duration fadeDuration = const Duration(milliseconds: 150),

  /// Additional viewport area retaining symbol anchors.
  final EdgeInsets cullingPadding = const EdgeInsets.symmetric(
    horizontal: 120,
    vertical: 60,
  ),

  /// How default labels contribute to the semantics tree.
  final SymbolSemanticsMode semanticsMode = SymbolSemanticsMode.labels,
}) extends StatefulWidget {
  this : assert(fadeDuration >= Duration.zero);

  @override
  State<MapSymbolLayer> createState() => _MapSymbolLayerState();
}

class _MapSymbolLayerState extends State<MapSymbolLayer> {
  final _relayout = ValueNotifier<int>(0);
  late MapSymbolLayer _baseline;
  late MapSymbolOverlay _child;
  var _replacementPending = true;

  List<MapSymbol> _currentSymbols() =>
      widget.labels.liveSymbolsForLayer(widget.layerIndex);

  void _onFadedOut(String key) => widget.labels.onFadedOut(key);

  @override
  void initState() {
    super.initState();
    _replaceChild();
    widget.relayout.addListener(_forwardRelayout);
    if (_diagnosticsEnabled) {
      SymbolProfileCounters.add(
        SymbolProfileCounters.symbolLayerReuseBaselines,
      );
      SymbolProfileCounters.add(
        SymbolProfileCounters.symbolLayerReuseBaselineEntries,
        widget.symbols.length,
      );
    }
  }

  @override
  void didUpdateWidget(covariant MapSymbolLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _replacementPending = true;
    if (!identical(oldWidget.relayout, widget.relayout)) {
      oldWidget.relayout.removeListener(_forwardRelayout);
      widget.relayout.addListener(_forwardRelayout);
    }
    final diagnostics = _diagnosticsEnabled;
    final watch = diagnostics ? (Stopwatch()..start()) : null;
    final miss = _reuseMiss(_baseline, widget);
    watch?.stop();
    if (diagnostics) _recordDecision(miss, watch!.elapsedMicroseconds);
    if (miss != null) {
      _replaceChild();

      return;
    }
    _replacementPending = false;
    _relayout.value++;
  }

  void _replaceChild() {
    _baseline = widget;
    _child = MapSymbolOverlay(
      symbols: widget.symbols,
      symbolsProvider: _currentSymbols,
      relayout: _relayout,
      screenSize: widget.screenSize,
      onFadedOut: _onFadedOut,
      iconBuilder: widget.iconBuilder,
      textBuilder: widget.textBuilder,
      fadeDuration: widget.fadeDuration,
      cullingPadding: widget.cullingPadding,
      semanticsMode: widget.semanticsMode,
    );
  }

  void _forwardRelayout() {
    // A replacement reads current anchors when its widget is updated. The old
    // child must not observe a new source or incompatible placement snapshot.
    if (_replacementPending) return;
    if (_diagnosticsEnabled) {
      SymbolProfileCounters.add(
        SymbolProfileCounters.symbolLayerReuseRelayouts,
      );
    }
    _relayout.value++;
  }

  void _recordDecision(_ReuseMiss? miss, int elapsedMicros) {
    SymbolProfileCounters.add(SymbolProfileCounters.symbolLayerReuseChecks);
    SymbolProfileCounters.add(
      SymbolProfileCounters.symbolLayerReuseCheckMicros,
      elapsedMicros,
    );
    if (miss == null) {
      SymbolProfileCounters.add(SymbolProfileCounters.symbolLayerReuseHits);
      SymbolProfileCounters.add(
        SymbolProfileCounters.symbolLayerReuseHitEntries,
        widget.symbols.length,
      );

      return;
    }
    SymbolProfileCounters.add(SymbolProfileCounters.symbolLayerReuseMisses);
    SymbolProfileCounters.add(
      SymbolProfileCounters.symbolLayerReuseMissEntries,
      widget.symbols.length,
    );
    SymbolProfileCounters.add(switch (miss) {
      _ReuseMiss.customBuilder =>
        SymbolProfileCounters.symbolLayerReuseCustomBuilderMisses,
      _ReuseMiss.configuration || _ReuseMiss.disabled =>
        SymbolProfileCounters.symbolLayerReuseConfigurationMisses,
      _ReuseMiss.symbols => SymbolProfileCounters.symbolLayerReuseSymbolMisses,
    });
  }

  @override
  Widget build(BuildContext context) {
    _replacementPending = false;

    return _child;
  }

  @override
  void dispose() {
    widget.relayout.removeListener(_forwardRelayout);
    _relayout.dispose();
    super.dispose();
  }
}

enum _ReuseMiss { disabled, customBuilder, configuration, symbols }

_ReuseMiss? _reuseMiss(MapSymbolLayer previous, MapSymbolLayer current) {
  if (!symbolLayerReuseEnabled) return _ReuseMiss.disabled;
  if (!identical(previous.iconBuilder, buildDefaultSymbolIcon) ||
      !identical(current.iconBuilder, buildDefaultSymbolIcon) ||
      !identical(previous.textBuilder, buildDefaultSymbolText) ||
      !identical(current.textBuilder, buildDefaultSymbolText)) {
    return _ReuseMiss.customBuilder;
  }
  if (!identical(previous.labels, current.labels) ||
      previous.layerIndex != current.layerIndex ||
      !identical(previous.relayout, current.relayout) ||
      previous.screenSize != current.screenSize ||
      previous.fadeDuration != current.fadeDuration ||
      previous.cullingPadding != current.cullingPadding ||
      previous.semanticsMode != current.semanticsMode) {
    return _ReuseMiss.configuration;
  }
  final before = previous.symbols;
  final after = current.symbols;
  if (before.length != after.length) return _ReuseMiss.symbols;
  for (var index = 0; index < before.length; index++) {
    final left = before[index];
    final right = after[index];
    if (left.key != right.key ||
        left.visible != right.visible ||
        left.fadeIn != right.fadeIn ||
        (left.textPos == null) != (right.textPos == null) ||
        (left.iconPos == null) != (right.iconPos == null) ||
        !identical(left.icon, right.icon) ||
        !identical(left.spriteAtlas, right.spriteAtlas) ||
        !_sameContent(left.data, right.data)) {
      return _ReuseMiss.symbols;
    }
  }

  return null;
}

// Native snapshots own immutable placement data. Geographic anchors and native
// center offsets are read through the live source rather than this content.
bool _sameContent(LabelData a, LabelData b) =>
    identical(a, b) ||
    a.crossTileId == b.crossTileId &&
        a.tileWrap == b.tileWrap &&
        a.layer == b.layer &&
        a.layerIndex == b.layerIndex &&
        a.renderGroup == b.renderGroup &&
        a.renderOrder == b.renderOrder &&
        a.textPlaced == b.textPlaced &&
        a.iconPlaced == b.iconPlaced &&
        a.alongLine == b.alongLine &&
        a.iconAlongLine == b.iconAlongLine &&
        a.vertical == b.vertical &&
        a.iconSdf == b.iconSdf &&
        a.textPitchWithMap == b.textPitchWithMap &&
        a.textRotationWithMap == b.textRotationWithMap &&
        a.iconPitchWithMap == b.iconPitchWithMap &&
        a.iconRotationWithMap == b.iconRotationWithMap &&
        a.textKeepUpright == b.textKeepUpright &&
        a.iconKeepUpright == b.iconKeepUpright &&
        a.textJustify == b.textJustify &&
        a.textDirection == b.textDirection &&
        a.text == b.text &&
        a.visualText == b.visualText &&
        a.icon == b.icon &&
        a.textFont == b.textFont &&
        _sameNumber(a.fontSize, b.fontSize) &&
        _sameNumber(a.textR, b.textR) &&
        _sameNumber(a.textG, b.textG) &&
        _sameNumber(a.textB, b.textB) &&
        _sameNumber(a.textA, b.textA) &&
        _sameNumber(a.haloR, b.haloR) &&
        _sameNumber(a.haloG, b.haloG) &&
        _sameNumber(a.haloB, b.haloB) &&
        _sameNumber(a.haloA, b.haloA) &&
        _sameNumber(a.haloWidth, b.haloWidth) &&
        _sameNumber(a.textOpacity, b.textOpacity) &&
        _sameNumber(a.haloBlur, b.haloBlur) &&
        _sameNumber(a.letterSpacing, b.letterSpacing) &&
        _sameNumber(a.lineHeight, b.lineHeight) &&
        _sameNumber(a.maxWidth, b.maxWidth) &&
        _sameNumber(a.textW, b.textW) &&
        _sameNumber(a.textH, b.textH) &&
        _sameNumber(a.iconW, b.iconW) &&
        _sameNumber(a.iconH, b.iconH) &&
        _sameNumber(a.iconScale, b.iconScale) &&
        _sameNumber(a.iconOpacity, b.iconOpacity) &&
        _sameNumber(a.iconR, b.iconR) &&
        _sameNumber(a.iconG, b.iconG) &&
        _sameNumber(a.iconB, b.iconB) &&
        _sameNumber(a.iconA, b.iconA) &&
        _sameNumber(a.iconHaloR, b.iconHaloR) &&
        _sameNumber(a.iconHaloG, b.iconHaloG) &&
        _sameNumber(a.iconHaloB, b.iconHaloB) &&
        _sameNumber(a.iconHaloA, b.iconHaloA) &&
        _sameNumber(a.iconHaloWidth, b.iconHaloWidth) &&
        _sameNumber(a.iconHaloBlur, b.iconHaloBlur) &&
        _sameNumber(a.iconFitWidth, b.iconFitWidth) &&
        _sameNumber(a.iconFitHeight, b.iconFitHeight) &&
        _sameNumber(a.angle, b.angle) &&
        _sameNumber(a.iconAngle, b.iconAngle) &&
        _sameNumber(a.textRotation, b.textRotation) &&
        _sameNumber(a.iconRotation, b.iconRotation) &&
        _sameNumber(a.textTranslateX, b.textTranslateX) &&
        _sameNumber(a.textTranslateY, b.textTranslateY) &&
        _sameNumber(a.iconTranslateX, b.iconTranslateX) &&
        _sameNumber(a.iconTranslateY, b.iconTranslateY) &&
        _sameTransform(a.textTransform, b.textTransform) &&
        _sameTransform(a.iconTransform, b.iconTransform) &&
        listEquals(a.textFonts, b.textFonts) &&
        _sameSections(a.textSections, b.textSections) &&
        _sameSections(a.visualTextSections, b.visualTextSections) &&
        _samePath(a.textPath, b.textPath) &&
        _samePath(a.iconPath, b.iconPath);

bool _sameNumber(double a, double b) =>
    a == b && (a != 0 || a.isNegative == b.isNegative);

bool _sameTransform(LabelAffineTransform a, LabelAffineTransform b) =>
    identical(a, b) ||
    _sameNumber(a.xx, b.xx) &&
        _sameNumber(a.xy, b.xy) &&
        _sameNumber(a.yx, b.yx) &&
        _sameNumber(a.yy, b.yy);

bool _samePath(List<LabelPathPoint> a, List<LabelPathPoint> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (!_sameNumber(a[index].x, b[index].x) ||
        !_sameNumber(a[index].y, b[index].y)) {
      return false;
    }
  }

  return true;
}

bool _sameSections(List<LabelTextSection> a, List<LabelTextSection> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    final left = a[index];
    final right = b[index];
    if (left.start != right.start ||
        left.end != right.end ||
        !_sameNumber(left.fontScale, right.fontScale) ||
        !listEquals(left.fonts, right.fonts) ||
        !_sameColor(left.color, right.color) ||
        left.imageId != right.imageId) {
      return false;
    }
  }

  return true;
}

bool _sameColor(Color? a, Color? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;

  return a.colorSpace == b.colorSpace &&
      _sameNumber(a.a, b.a) &&
      _sameNumber(a.r, b.r) &&
      _sameNumber(a.g, b.g) &&
      _sameNumber(a.b, b.b);
}
