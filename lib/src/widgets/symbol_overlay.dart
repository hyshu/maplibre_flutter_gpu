/// @docImport 'maplibre_map.dart';
library;

// MapLibre places symbols while Flutter builds their visual representation.
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, listEquals, setEquals, visibleForTesting;
import 'package:flutter/material.dart';

import '../labels/label_data.dart';
import '../sprites/sprite_atlas.dart';

@visibleForTesting
/// Places glyph centers along a screen-space path using their advance widths.
List<({Offset position, double angle})> layoutSymbolGlyphsAlongPath(
  List<Offset> path,
  List<double> advances, {
  bool keepUpright = true,
}) {
  if (path.length < 2 || advances.isEmpty) return const [];
  final points = <Offset>[];
  for (final point in path) {
    if (!point.dx.isFinite || !point.dy.isFinite) continue;
    if (points.isEmpty || (point - points.last).distanceSquared > 0.0001) {
      points.add(point);
    }
  }
  if (points.length < 2) return const [];

  var sampler = _MonotonicPathSampler(points);
  var pathLength = sampler.length;
  if (pathLength <= 0) return const [];

  // Follow the path in the direction that keeps text upright.
  if (keepUpright && math.cos(sampler.sample(pathLength / 2).angle) < 0) {
    final reversed = points.reversed.toList(growable: false);
    points
      ..clear()
      ..addAll(reversed);
    sampler = _MonotonicPathSampler(points);
    pathLength = sampler.length;
  }

  final safeAdvances = [
    for (final advance in advances)
      advance.isFinite && advance > 0 ? advance : 0.0,
  ];
  final advanceTotal = safeAdvances.fold<double>(
    0,
    (sum, value) => sum + value,
  );
  if (advanceTotal <= 0) return const [];
  final positionScale = math.min(1.0, pathLength / advanceTotal);
  var distance = (pathLength - advanceTotal * positionScale) / 2;
  final placements = <({Offset position, double angle})>[];
  for (final advance in safeAdvances) {
    final positionedAdvance = advance * positionScale;
    placements.add(sampler.sample(distance + positionedAdvance / 2));
    distance += positionedAdvance;
  }

  return placements;
}

class _MonotonicPathSampler {
  _MonotonicPathSampler(this.points)
    : segments = [
        for (var i = 1; i < points.length; i++)
          (points[i] - points[i - 1]).distance,
      ];

  final List<Offset> points;
  final List<double> segments;
  late final double length = segments.fold(0, (sum, value) => sum + value);
  var _segmentIndex = 0;
  var _segmentStart = 0.0;

  ({Offset position, double angle}) sample(double distance) {
    final target = distance.clamp(0.0, length);
    if (target < _segmentStart) {
      _segmentIndex = 0;
      _segmentStart = 0;
    }
    while (_segmentIndex < segments.length - 1 &&
        target > _segmentStart + segments[_segmentIndex]) {
      _segmentStart += segments[_segmentIndex];
      _segmentIndex += 1;
    }
    final segmentLength = segments[_segmentIndex];
    final delta = points[_segmentIndex + 1] - points[_segmentIndex];
    final t = segmentLength > 0
        ? (target - _segmentStart) / segmentLength
        : 0.0;

    return (
      position: points[_segmentIndex] + delta * t,
      angle: math.atan2(delta.dy, delta.dx),
    );
  }
}

/// Placement information for a symbol displayed by a [MapSymbolOverlay].
///
/// The [textPos] and [iconPos] anchors use logical pixels from the top-left of
/// the map viewport. Their x coordinates increase to the right and their y
/// coordinates increase downward. The overlay centers each builder's widget on
/// the corresponding anchor.
///
/// Each [key] must be unique within a [MapSymbolOverlay.symbols] list. Reusing a
/// key in later lists preserves the symbol's widget and fade state while its
/// placement changes.
class MapSymbol {
  /// The stable identity of this symbol across placement updates.
  ///
  /// This value must be unique among the symbols in the same overlay.
  final String key;

  /// The evaluated style data used to build this symbol.
  final LabelData data;

  /// The text anchor in logical pixels from the viewport's top-left corner.
  ///
  /// A null value means that no text child is laid out for this symbol.
  final Offset? textPos;

  /// The icon anchor in logical pixels from the viewport's top-left corner.
  ///
  /// A null value means that no icon child is laid out for this symbol.
  final Offset? iconPos;

  /// The resolved sprite used by the default icon builder.
  ///
  /// This is null when the symbol has no sprite or its sprite is unavailable.
  /// A custom icon builder can still build a widget when [iconPos] is non-null.
  final SpriteIcon? icon;

  /// Sprite atlas used to resolve images embedded in formatted text.
  ///
  /// This can be null when the active style has no sprite or its atlas is not
  /// available yet.
  final SpriteAtlas? spriteAtlas;

  /// Whether the symbol is present in the latest placement.
  ///
  /// A false value retains the symbol only long enough to fade out. The owner
  /// can remove it when [MapSymbolOverlay.onFadedOut] reports this [key].
  final bool visible;

  /// Whether newly built children start transparent and fade in.
  ///
  /// This value affects a new keyed child and does not restart the fade when an
  /// existing child is rebuilt. Defaults to true.
  final bool fadeIn;

  /// Creates placement information for a map symbol.
  const MapSymbol({
    required this.key,
    required this.data,
    required this.textPos,
    required this.iconPos,
    required this.icon,
    this.spriteAtlas,
    required this.visible,
    this.fadeIn = true,
  });

  /// The anchor used for viewport culling.
  ///
  /// The text anchor is preferred when both anchors are present. The overlay
  /// culls each component using its own anchor. This getter is available to
  /// clients that need one representative position.
  Offset? get anchor => textPos ?? iconPos;
}

/// Signature for building one visual part of a [MapSymbol].
///
/// The overlay calls this builder independently for its icon and text parts.
/// An icon widget is centered on [MapSymbol.iconPos], and a text widget is
/// centered on [MapSymbol.textPos]. Returning null omits that part.
///
/// Builder results receive pointer events while their symbol is visible.
/// Gesture handlers can consume those events instead of passing them to the
/// map beneath the overlay.
typedef SymbolWidgetBuilder = Widget? Function(
  BuildContext context,
  MapSymbol symbol,
);

/// A widget that lays out icon and text widgets for placed map symbols.
///
/// Each builder result is centered on its corresponding [MapSymbol] anchor.
/// Each component is omitted when its own anchor lies outside the viewport
/// extended by [cullingPadding]. The other component remains visible when its
/// anchor is inside that area.
///
/// Children paint in MapLibre's exported order. Within each native paint group,
/// all icons paint before all text so overlapping components match symbol
/// layer compositing.
///
/// A disappearing symbol must remain in [symbols] with
/// [MapSymbol.visible] set to false for its children to fade out. Removing it
/// from [symbols] immediately removes its children without a fade. When a
/// fading child finishes, [onFadedOut] reports that the owner can discard the
/// hidden symbol.
///
/// Default icon and text children ignore pointer events so they do not block
/// the map. Widgets returned by custom builders receive pointer events while
/// their symbol is visible.
///
/// [MapLibreMap] creates this overlay for its placed symbols. Most applications
/// can customize those symbols through [MapLibreMap.symbolIconBuilder] and
/// [MapLibreMap.symbolTextBuilder] instead of constructing an overlay.
///
/// See also:
///
///  * [MapSymbol], which describes one placed symbol.
///  * [SymbolWidgetBuilder], which builds an icon or text child.
class MapSymbolOverlay extends StatefulWidget {
  /// The symbol snapshot used to build, cull, and identify the current children.
  ///
  /// Keys must be unique within this list. The list must not be mutated after it
  /// is passed to the overlay. Membership, visibility, style data, or available
  /// icon and text parts must be changed by rebuilding with a new list.
  final List<MapSymbol> symbols;

  /// Supplies the latest positions for existing children during layout.
  ///
  /// This provider supports position-only updates without replacing the
  /// [symbols] snapshot. Its symbols must keep the same keys and available icon
  /// and text parts as [symbols]. Only their keys, [MapSymbol.iconPos], and
  /// [MapSymbol.textPos] are read from this provider.
  ///
  /// When null, layout uses [symbols].
  final List<MapSymbol> Function()? symbolsProvider;

  /// Notifies the overlay to read [symbolsProvider], recull its components, and
  /// reposition its children. Position changes normally update layout without
  /// rebuilding the overlay. The overlay rebuilds when a component crosses the
  /// culling boundary. Custom builder children rebuild independently so they
  /// continue to receive the latest positions.
  final Listenable? relayout;

  /// The logical viewport size used for symbol culling.
  ///
  /// This should match the map area covered by the overlay. Culling is
  /// recomputed after position-only [relayout] notifications.
  final Size screenSize;

  /// Builds each symbol's icon, or hides all icons when null.
  ///
  /// Defaults to the style-derived sprite builder.
  final SymbolWidgetBuilder? iconBuilder;

  /// Builds each symbol's text label, or hides all labels when null.
  ///
  /// Defaults to the style-derived text builder.
  final SymbolWidgetBuilder? textBuilder;

  /// Called when one of a hidden symbol's children finishes fading out.
  ///
  /// A symbol with both icon and text children can report the same key more
  /// than once. A hidden symbol that is culled or has no anchor is also reported
  /// after the current frame because it has no child to animate. The reported
  /// symbol may have become visible again, so removal handlers need idempotent,
  /// visibility-aware behavior.
  final void Function(String key) onFadedOut;

  /// The duration of symbol fade-in and fade-out transitions.
  ///
  /// Defaults to 150 milliseconds and must not be negative.
  final Duration fadeDuration;

  /// The area beyond each viewport edge in which symbols are retained.
  ///
  /// Culling tests each text and icon anchor independently, not the bounds of
  /// its built widget. The default extends the horizontal edges by 120 logical
  /// pixels and the vertical edges by 60 logical pixels. An [EdgeInsets] with
  /// any non-finite or negative component is treated as [EdgeInsets.zero].
  final EdgeInsets cullingPadding;

  /// Creates an overlay for placed map symbols.
  const MapSymbolOverlay({
    super.key,
    required this.symbols,
    this.symbolsProvider,
    this.relayout,
    required this.screenSize,
    required this.onFadedOut,
    this.iconBuilder = buildDefaultSymbolIcon,
    this.textBuilder = buildDefaultSymbolText,
    this.fadeDuration = const Duration(milliseconds: 150),
    this.cullingPadding = const EdgeInsets.symmetric(
      horizontal: 120,
      vertical: 60,
    ),
  }) : assert(fadeDuration >= Duration.zero);

  @override
  State<MapSymbolOverlay> createState() => _MapSymbolOverlayState();
}

class _MapSymbolOverlayState extends State<MapSymbolOverlay> {
  final _defaultVisuals = <String, _DefaultSymbolVisuals>{};
  final _liveKeys = <String>{};
  final _pendingCulledFadeKeys = <String>{};
  final _positions = _SymbolPositionStore();
  Set<Object> _componentMembership = const {};

  @override
  void initState() {
    super.initState();
    _refreshPositions();
    widget.relayout?.addListener(_handleRelayout);
  }

  @override
  void didUpdateWidget(covariant MapSymbolOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshPositions();
    if (!identical(oldWidget.relayout, widget.relayout)) {
      oldWidget.relayout?.removeListener(_handleRelayout);
      widget.relayout?.addListener(_handleRelayout);
    }
  }

  @override
  void dispose() {
    widget.relayout?.removeListener(_handleRelayout);
    _positions.dispose();
    super.dispose();
  }

  void _handleRelayout() {
    if (!mounted) return;
    _refreshPositions();
    final nextMembership = _currentComponentMembership();
    if (!setEquals(_componentMembership, nextMembership)) {
      setState(() {});

      return;
    }
    _positions.notifyPositionChange();
  }

  void _refreshPositions() {
    _positions.update(widget.symbolsProvider?.call() ?? widget.symbols);
  }

  @override
  Widget build(context) {
    final paintItems = <_SymbolPaintItem>[];
    final liveKeys = _liveKeys..clear();
    final cullingPadding = _validCullingPadding(widget.cullingPadding);
    var paintOrdinal = 0;
    final positionedSymbols = _symbolsForBuild();
    for (final symbol in positionedSymbols) {
      liveKeys.add(symbol.key);
      if (symbol.visible) _pendingCulledFadeKeys.remove(symbol.key);
      final iconInBounds = _isAnchorInBounds(symbol.iconPos, cullingPadding);
      final textInBounds = _isAnchorInBounds(symbol.textPos, cullingPadding);
      if (!iconInBounds && !textInBounds) {
        _completeCulledFade(symbol);
        continue;
      }
      _pendingCulledFadeKeys.remove(symbol.key);
      final usesDefaultIcon = identical(
        widget.iconBuilder,
        buildDefaultSymbolIcon,
      );
      final usesDefaultText = identical(
        widget.textBuilder,
        buildDefaultSymbolText,
      );
      final defaults = usesDefaultIcon || usesDefaultText
          ? _defaultVisuals.update(
              symbol.key,
              (cached) => cached.update(context, symbol),
              ifAbsent: () => _DefaultSymbolVisuals.from(context, symbol),
            )
          : null;
      // Position icon and text independently while fading both together.
      final iconWidget = !iconInBounds
          ? null
          : usesDefaultIcon
          ? defaults!.icon
          : widget.iconBuilder == null
          ? null
          : _PositionedSymbolBuilder(
              symbol: symbol,
              positions: _positions,
              builder: widget.iconBuilder!,
            );
      if (iconWidget != null && symbol.iconPos != null) {
        final id = (symbol.key, true);
        paintItems.add(
          _SymbolPaintItem(
            id: id,
            layerIndex: symbol.data.layerIndex,
            renderGroup: symbol.data.renderGroup,
            componentOrder: 0,
            renderOrder: symbol.data.renderOrder,
            ordinal: paintOrdinal++,
            child: _layoutChild(
              id,
              symbol,
              iconWidget,
              ignorePointer: usesDefaultIcon,
            ),
          ),
        );
      }
      final textWidget = !textInBounds
          ? null
          : usesDefaultText
          ? defaults!.text
          : widget.textBuilder == null
          ? null
          : _PositionedSymbolBuilder(
              symbol: symbol,
              positions: _positions,
              builder: widget.textBuilder!,
            );
      if (textWidget != null && symbol.textPos != null) {
        final id = (symbol.key, false);
        paintItems.add(
          _SymbolPaintItem(
            id: id,
            layerIndex: symbol.data.layerIndex,
            renderGroup: symbol.data.renderGroup,
            componentOrder: 1,
            renderOrder: symbol.data.renderOrder,
            ordinal: paintOrdinal++,
            child: _layoutChild(
              id,
              symbol,
              textWidget,
              ignorePointer: usesDefaultText,
            ),
          ),
        );
      }
    }
    _defaultVisuals.removeWhere((key, _) => !liveKeys.contains(key));
    _componentMembership = _componentMembershipFor(positionedSymbols);
    paintItems.sort(_SymbolPaintItem.compare);
    final childIds = [for (final item in paintItems) item.id];

    return CustomMultiChildLayout(
      delegate: _SymbolLayoutDelegate(
        positions: _positions,
        childIds: childIds,
      ),
      children: [for (final item in paintItems) item.child],
    );
  }

  List<MapSymbol> _symbolsForBuild() {
    return [for (final symbol in widget.symbols) _positions.positioned(symbol)];
  }

  Set<Object> _currentComponentMembership() =>
      _componentMembershipFor(_symbolsForBuild());

  Set<Object> _componentMembershipFor(List<MapSymbol> symbols) {
    final membership = <Object>{};
    final padding = _validCullingPadding(widget.cullingPadding);
    for (final symbol in symbols) {
      if (widget.iconBuilder != null &&
          _isAnchorInBounds(symbol.iconPos, padding)) {
        membership.add((symbol.key, true));
      }
      if (widget.textBuilder != null &&
          _isAnchorInBounds(symbol.textPos, padding)) {
        membership.add((symbol.key, false));
      }
    }

    return membership;
  }

  /// Returns a finite non-negative padding for culling calculations.
  EdgeInsets _validCullingPadding(EdgeInsets padding) {
    if (!padding.left.isFinite ||
        !padding.top.isFinite ||
        !padding.right.isFinite ||
        !padding.bottom.isFinite ||
        !padding.isNonNegative) {
      return EdgeInsets.zero;
    }

    return padding;
  }

  bool _isAnchorInBounds(Offset? anchor, EdgeInsets padding) {
    if (anchor == null) return false;

    return anchor.dx >= -padding.left &&
        anchor.dx <= widget.screenSize.width + padding.right &&
        anchor.dy >= -padding.top &&
        anchor.dy <= widget.screenSize.height + padding.bottom;
  }

  // Culled symbols have no fade widget to report their completion.
  void _completeCulledFade(MapSymbol symbol) {
    if (symbol.visible) return;
    if (!_pendingCulledFadeKeys.add(symbol.key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_pendingCulledFadeKeys.remove(symbol.key) || !mounted) return;
      widget.onFadedOut(symbol.key);
    });
  }

  /// Preserves child and fade identity across placement updates.
  Widget _layoutChild(
    Object childId,
    MapSymbol symbol,
    Widget child, {
    required bool ignorePointer,
  }) => LayoutId(
    key: ValueKey(childId),
    id: childId,
    child: _SymbolFade(
      visible: symbol.visible,
      fadeIn: symbol.fadeIn,
      duration: widget.fadeDuration,
      onFadedOut: () => widget.onFadedOut(symbol.key),
      ignorePointer: ignorePointer,
      child: child,
    ),
  );
}

class _SymbolPaintItem {
  const _SymbolPaintItem({
    required this.id,
    required this.layerIndex,
    required this.renderGroup,
    required this.componentOrder,
    required this.renderOrder,
    required this.ordinal,
    required this.child,
  });

  final Object id;
  final int layerIndex;
  final int renderGroup;
  final int componentOrder;
  final int renderOrder;
  final int ordinal;
  final Widget child;

  static int compare(_SymbolPaintItem left, _SymbolPaintItem right) {
    var result = left.layerIndex.compareTo(right.layerIndex);
    if (result == 0) result = left.renderGroup.compareTo(right.renderGroup);
    if (result == 0) {
      result = left.componentOrder.compareTo(right.componentOrder);
    }
    if (result == 0) result = left.renderOrder.compareTo(right.renderOrder);

    return result == 0 ? left.ordinal.compareTo(right.ordinal) : result;
  }
}

class _DefaultSymbolVisuals {
  const _DefaultSymbolVisuals({
    required this.data,
    required this.sprite,
    required this.spriteAtlas,
    required this.icon,
    required this.text,
  });

  factory _DefaultSymbolVisuals.from(BuildContext context, MapSymbol symbol) =>
      _DefaultSymbolVisuals(
        data: symbol.data,
        sprite: symbol.icon,
        spriteAtlas: symbol.spriteAtlas,
        icon: buildDefaultSymbolIcon(context, symbol),
        text: buildDefaultSymbolText(context, symbol),
      );

  final LabelData data;
  final SpriteIcon? sprite;
  final SpriteAtlas? spriteAtlas;
  final Widget? icon;
  final Widget? text;

  _DefaultSymbolVisuals update(BuildContext context, MapSymbol symbol) {
    final sameData = identical(data, symbol.data);
    final sameSprite = identical(sprite, symbol.icon);
    final sameSpriteAtlas = identical(spriteAtlas, symbol.spriteAtlas);
    if (sameData && sameSprite && sameSpriteAtlas) return this;

    return _DefaultSymbolVisuals(
      data: symbol.data,
      sprite: symbol.icon,
      spriteAtlas: symbol.spriteAtlas,
      icon: buildDefaultSymbolIcon(context, symbol),
      text: sameData && sameSpriteAtlas
          ? text
          : buildDefaultSymbolText(context, symbol),
    );
  }
}

class _SymbolPositionStore extends ChangeNotifier {
  Map<String, MapSymbol> _symbols = const {};
  Map<Object, Offset> _anchors = const {};
  int _revision = 0;

  int get revision => _revision;

  void update(List<MapSymbol> symbols) {
    _revision++;
    _symbols = {for (final symbol in symbols) symbol.key: symbol};
    _anchors = {
      for (final symbol in symbols) (symbol.key, true): ?symbol.iconPos,
      for (final symbol in symbols) (symbol.key, false): ?symbol.textPos,
    };
  }

  void notifyPositionChange() => notifyListeners();

  Offset? anchor(Object id) => _anchors[id];

  MapSymbol positioned(MapSymbol symbol) {
    final positioned = _symbols[symbol.key];
    if (positioned == null) return symbol;

    return MapSymbol(
      key: symbol.key,
      data: symbol.data,
      textPos: positioned.textPos,
      iconPos: positioned.iconPos,
      icon: symbol.icon,
      spriteAtlas: symbol.spriteAtlas,
      visible: symbol.visible,
      fadeIn: symbol.fadeIn,
    );
  }
}

class _PositionedSymbolBuilder extends StatelessWidget {
  const _PositionedSymbolBuilder({
    required this.symbol,
    required this.positions,
    required this.builder,
  });

  final MapSymbol symbol;
  final _SymbolPositionStore positions;
  final SymbolWidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: positions,
    builder: (context, _) =>
        builder(context, positions.positioned(symbol)) ??
        const SizedBox.shrink(),
  );
}

class _SymbolLayoutDelegate extends MultiChildLayoutDelegate {
  static const _hiddenPosition = Offset(-100000, -100000);

  _SymbolLayoutDelegate({required this.positions, required this.childIds})
    : positionRevision = positions.revision,
      super(relayout: positions);

  final _SymbolPositionStore positions;
  final int positionRevision;
  final List<Object> childIds;

  @override
  void performLayout(size) {
    for (final id in childIds) {
      if (!hasChild(id)) continue;
      final childSize = layoutChild(id, BoxConstraints.loose(size));
      final position = positions.anchor(id) ?? _hiddenPosition;
      positionChild(
        id,
        position - Offset(childSize.width / 2, childSize.height / 2),
      );
    }
  }

  @override
  bool shouldRelayout(covariant _SymbolLayoutDelegate oldDelegate) =>
      childIds.length != oldDelegate.childIds.length ||
      !listEquals(childIds, oldDelegate.childIds) ||
      positionRevision != oldDelegate.positionRevision ||
      !identical(positions, oldDelegate.positions);
}

/// Builds the default style-derived sprite for a placed symbol.
///
/// Returns null when [MapSymbol.icon] is null.
Widget? buildDefaultSymbolIcon(BuildContext context, MapSymbol symbol) {
  final icon = symbol.icon;
  if (icon == null) return null;
  final data = symbol.data;
  final hasTextFit = data.iconFitWidth > 0 && data.iconFitHeight > 0;
  final iconScale = data.iconScale.isFinite && data.iconScale > 0
      ? data.iconScale
      : 1.0;
  final fitSize = hasTextFit
      ? icon.fittedContentSize(
              Size(
                data.iconFitWidth / iconScale,
                data.iconFitHeight / iconScale,
              ),
            ) *
            iconScale
      : null;
  Widget result = SpriteIconWidget(
    icon: icon,
    scale: data.iconScale,
    opacity: data.iconOpacity,
    tint: data.iconColor,
    fitSize: fitSize,
    fitSizeConstrained: true,
    haloColor: data.iconHaloColor,
    haloWidth: data.iconHaloWidth,
    haloBlur: data.iconHaloBlur,
  );
  // Only map-aligned line icons inherit the path direction.
  if (data.iconRotationWithMap && (data.iconAlongLine || data.alongLine)) {
    final path = data.iconPath.isNotEmpty ? data.iconPath : data.textPath;
    final pathAngle = _pathAngle(
      path,
      data.iconAngle,
      keepUpright: data.iconKeepUpright,
    );
    result = _applyLineSymbolTransform(
      result,
      data.iconTransform,
      pathAngle + data.iconRotation,
    );
  } else {
    result = _applyPointSymbolTransform(result, data.iconTransform);
  }

  return _applySymbolTranslation(
    result,
    data.iconTranslateX,
    data.iconTranslateY,
  );
}

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
  final scaled = scale.x.isFinite && scale.y.isFinite
      ? Transform.scale(
          scaleX: scale.x,
          scaleY: scale.y,
          alignment: Alignment.center,
          child: child,
        )
      : child;
  if (!angle.isFinite || angle == 0) return scaled;

  return Transform.rotate(angle: angle, child: scaled);
}

({double x, double y}) _lineSymbolScale(LabelAffineTransform transform) => (
  x: math.sqrt(transform.xx * transform.xx + transform.xy * transform.xy),
  y: math.sqrt(transform.yx * transform.yx + transform.yy * transform.yy),
);

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

/// Builds the default style-derived text for a placed symbol.
///
/// Returns null when no non-empty text label was placed.
Widget? buildDefaultSymbolText(BuildContext context, MapSymbol symbol) {
  final data = symbol.data;
  if (!data.textPlaced || data.text.isEmpty) return null;
  final fontSize = data.fontSize;
  final fonts = data.textFonts.isNotEmpty ? data.textFonts : [data.textFont];
  final font = _mapLibreFonts(fonts);
  final fillStyle = TextStyle(
    fontSize: fontSize,
    color: data.textColor,
    fontFamily: font.family,
    fontFamilyFallback: font.fallback,
    fontWeight: font.weight,
    fontStyle: font.style,
    letterSpacing: data.letterSpacing * fontSize,
    height: data.lineHeight,
  );
  Widget text;
  if (data.alongLine && data.textPath.length >= 2) {
    final visualSections = data.visualTextSections.isNotEmpty
        ? data.visualTextSections
        : data.visualText == data.text
        ? data.textSections
        : const <LabelTextSection>[];
    final visualParts = _symbolTextParts(
      symbol,
      fillStyle,
      fonts,
      text: data.visualText,
      sections: visualSections,
    );
    text = _buildPathText(data, visualParts);
  } else if (data.vertical) {
    final parts = _symbolTextParts(
      symbol,
      fillStyle,
      fonts,
      text: data.text,
      sections: data.textSections,
    );
    text = _buildVerticalText(data, parts);
    text = _applyPointSymbolTransform(text, data.textTransform);
  } else {
    final parts = _symbolTextParts(
      symbol,
      fillStyle,
      fonts,
      text: data.text,
      sections: data.textSections,
    );
    text = _buildPointText(data, parts, fillStyle);
    text = data.alongLine
        ? _applyLineSymbolTransform(
            text,
            data.textTransform,
            _pathAngle(
                  data.textPath,
                  data.angle,
                  keepUpright: data.textKeepUpright,
                ) +
                data.textRotation,
          )
        : _applyPointSymbolTransform(text, data.textTransform);
  }
  final opacity = data.textOpacity.clamp(0.0, 1.0);
  if (opacity < 1) text = Opacity(opacity: opacity, child: text);

  return _applySymbolTranslation(
    text,
    data.textTranslateX,
    data.textTranslateY,
  );
}

class _SymbolTextPart {
  const _SymbolTextPart({
    required this.text,
    required this.style,
    this.image,
    this.imageScale = 1,
    this.imageSection = false,
  });

  final String text;
  final TextStyle style;
  final SpriteIcon? image;
  final double imageScale;
  final bool imageSection;
}

List<_SymbolTextPart> _symbolTextParts(
  MapSymbol symbol,
  TextStyle baseStyle,
  List<String> baseFonts, {
  required String text,
  required List<LabelTextSection> sections,
}) {
  final data = symbol.data;
  if (sections.isEmpty) {
    return [_SymbolTextPart(text: text, style: baseStyle)];
  }
  final sortedSections = sections.toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final parts = <_SymbolTextPart>[];
  var offset = 0;
  for (final section in sortedSections) {
    final start = section.start.clamp(offset, text.length);
    final end = section.end.clamp(start, text.length);
    if (start > offset) {
      parts.add(
        _SymbolTextPart(text: text.substring(offset, start), style: baseStyle),
      );
    }
    final scale = section.fontScale.isFinite && section.fontScale > 0
        ? section.fontScale
        : 1.0;
    final sectionFonts = section.fonts.isEmpty ? baseFonts : section.fonts;
    final font = _mapLibreFonts(sectionFonts);
    final style = baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? data.fontSize) * scale,
      color: section.color ?? baseStyle.color,
      fontFamily: font.family,
      fontFamilyFallback: font.fallback,
      fontWeight: font.weight,
      fontStyle: font.style,
    );
    final imageId = section.imageId;
    parts.add(
      _SymbolTextPart(
        text: text.substring(start, end),
        style: style,
        image: imageId == null ? null : symbol.spriteAtlas?[imageId],
        imageScale: scale,
        imageSection: imageId != null,
      ),
    );
    offset = end;
  }
  if (offset < text.length) {
    parts.add(_SymbolTextPart(text: text.substring(offset), style: baseStyle));
  }

  return parts;
}

Widget _buildPointText(
  LabelData data,
  List<_SymbolTextPart> parts,
  TextStyle baseStyle,
) {
  final fontSize = data.fontSize;
  final boxWidth = data.textW;
  final maxWidth = boxWidth > 0
      ? boxWidth
      : (data.maxWidth > 0 ? data.maxWidth * fontSize : fontSize * 8);
  Widget label(bool halo) => _formattedText(
    data,
    parts,
    baseStyle,
    halo: halo,
    maxLines: data.alongLine ? 1 : null,
  );
  final visual = data.haloWidth > 0
      ? Stack(
          alignment: Alignment.center,
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [label(true), label(false)],
        )
      : label(false);

  return SizedBox(width: maxWidth, child: visual);
}

Widget _formattedText(
  LabelData data,
  List<_SymbolTextPart> parts,
  TextStyle baseStyle, {
  required bool halo,
  int? maxLines,
}) {
  final align = switch (data.textJustify) {
    LabelTextJustify.left => TextAlign.left,
    LabelTextJustify.right => TextAlign.right,
    LabelTextJustify.auto || LabelTextJustify.center => TextAlign.center,
  };
  if (parts.length == 1 && !parts.single.imageSection) {
    return Text(
      parts.single.text,
      style: halo ? _haloStyle(parts.single.style, data) : parts.single.style,
      textAlign: align,
      textDirection: data.textDirection,
      softWrap: false,
      maxLines: maxLines,
      overflow: TextOverflow.visible,
    );
  }

  return Text.rich(
    TextSpan(
      style: halo ? _haloStyle(baseStyle, data) : baseStyle,
      children: [for (final part in parts) _textPartSpan(part, data, halo)],
    ),
    textAlign: align,
    textDirection: data.textDirection,
    softWrap: false,
    maxLines: maxLines,
    overflow: TextOverflow.visible,
  );
}

InlineSpan _textPartSpan(_SymbolTextPart part, LabelData data, bool halo) {
  final image = part.image;
  if (!part.imageSection) {
    return TextSpan(
      text: part.text,
      style: halo ? _haloStyle(part.style, data) : part.style,
    );
  }
  if (image == null) {
    return const WidgetSpan(child: SizedBox.shrink());
  }
  final size = image.displaySize * part.imageScale;

  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: halo
        ? image.sdf && data.haloWidth > 0
              ? SpriteIconWidget(
                  icon: image,
                  scale: part.imageScale,
                  tint: const Color(0x00000000),
                  haloColor: data.haloColor,
                  haloWidth: data.haloWidth,
                  haloBlur: data.haloBlur,
                )
              : SizedBox.fromSize(size: size)
        : SpriteIconWidget(
            icon: image,
            scale: part.imageScale,
            tint: part.style.color,
          ),
  );
}

TextStyle _haloStyle(TextStyle style, LabelData data) => style.copyWith(
  foreground: Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = data.haloWidth * 2
    ..strokeJoin = StrokeJoin.round
    ..maskFilter = data.haloBlur > 0
        ? MaskFilter.blur(BlurStyle.normal, data.haloBlur)
        : null
    ..color = data.haloColor,
);

Widget _buildVerticalText(LabelData data, List<_SymbolTextPart> parts) {
  final children = <Widget>[];
  for (final part in parts) {
    if (part.imageSection) {
      final image = part.image;
      if (image == null) continue;
      children.add(
        SpriteIconWidget(
          icon: image,
          scale: part.imageScale,
          tint: part.style.color,
          haloColor: image.sdf ? data.haloColor : null,
          haloWidth: image.sdf ? data.haloWidth : 0,
          haloBlur: image.sdf ? data.haloBlur : 0,
        ),
      );
      continue;
    }
    for (final grapheme in part.text.characters) {
      if (grapheme == '\n' || grapheme == '\r') continue;
      Widget glyph = _glyphText(grapheme, part.style, data);
      if (_rotateVerticalGlyph(grapheme)) {
        glyph = Transform.rotate(angle: math.pi / 2, child: glyph);
      }
      children.add(glyph);
    }
  }

  return Column(mainAxisSize: MainAxisSize.min, children: children);
}

bool _rotateVerticalGlyph(String grapheme) {
  final rune = grapheme.runes.firstOrNull;
  if (rune == null) return false;

  return rune > 0x20 && rune < 0x2e80;
}

Widget _glyphText(String text, TextStyle style, LabelData data) {
  final fill = Text(
    text,
    style: style.copyWith(height: 1),
    textDirection: data.textDirection,
  );
  if (data.haloWidth <= 0) return fill;

  return Stack(
    alignment: Alignment.center,
    clipBehavior: Clip.none,
    children: [
      Text(
        text,
        style: _haloStyle(style.copyWith(height: 1), data),
        textDirection: data.textDirection,
      ),
      fill,
    ],
  );
}

Widget _buildPathText(LabelData data, List<_SymbolTextPart> parts) {
  final glyphs = <_PathGlyph>[];
  final direction = data.textDirection;
  for (final part in parts) {
    if (part.imageSection) {
      final image = part.image;
      if (image == null) continue;
      final size = image.displaySize * part.imageScale;
      glyphs.add(
        _PathGlyph(
          advance: size.width,
          size: size,
          child: SpriteIconWidget(
            icon: image,
            scale: part.imageScale,
            tint: part.style.color,
            haloColor: image.sdf ? data.haloColor : null,
            haloWidth: image.sdf ? data.haloWidth : 0,
            haloBlur: image.sdf ? data.haloBlur : 0,
          ),
        ),
      );
      continue;
    }
    for (final grapheme in part.text.characters) {
      if (grapheme == '\n' || grapheme == '\r') continue;
      final glyphStyle = part.style.copyWith(height: 1);
      final metrics = _pathGlyphMetrics(grapheme, glyphStyle, direction);
      glyphs.add(
        _PathGlyph(
          advance: metrics.advance,
          size: metrics.size,
          child: _glyphText(grapheme, glyphStyle, data),
        ),
      );
    }
  }
  final path = [for (final point in data.textPath) Offset(point.x, point.y)];
  final lineScale = _lineSymbolScale(data.textTransform);
  final advanceScale = lineScale.x.isFinite ? lineScale.x : 1.0;
  final placements = layoutSymbolGlyphsAlongPath(path, [
    for (final glyph in glyphs) glyph.advance * advanceScale,
  ], keepUpright: data.textKeepUpright);
  if (placements.length != glyphs.length) {
    final fallbackStyle = parts.isEmpty
        ? TextStyle(fontSize: data.fontSize, color: data.textColor)
        : parts.first.style;
    final fallback = _buildPointText(data, parts, fallbackStyle);

    return _applyLineSymbolTransform(
      fallback,
      data.textTransform,
      _pathAngle(data.textPath, data.angle, keepUpright: data.textKeepUpright) +
          data.textRotation,
    );
  }

  final visualScaleX = lineScale.x.isFinite ? math.max(lineScale.x, 0) : 1.0;
  final visualScaleY = lineScale.y.isFinite ? math.max(lineScale.y, 0) : 1.0;
  final maxGlyphWidth =
      glyphs.fold<double>(
        data.fontSize,
        (value, glyph) => math.max(value, glyph.size.width),
      ) *
      visualScaleX;
  final maxGlyphHeight =
      glyphs.fold<double>(
        data.fontSize,
        (value, glyph) => math.max(value, glyph.size.height),
      ) *
      visualScaleY;
  final halfWidth =
      path.fold<double>(0, (value, point) => math.max(value, point.dx.abs())) +
      maxGlyphWidth / 2 +
      data.haloWidth +
      data.haloBlur;
  final halfHeight =
      path.fold<double>(0, (value, point) => math.max(value, point.dy.abs())) +
      maxGlyphHeight / 2 +
      data.haloWidth +
      data.haloBlur;
  final children = <Widget>[];
  for (var i = 0; i < glyphs.length; i++) {
    final glyph = glyphs[i];
    final placement = placements[i];
    final transformed = _applyLineSymbolTransform(
      SizedBox.fromSize(size: glyph.size, child: glyph.child),
      data.textTransform,
      placement.angle + data.textRotation,
    );
    children.add(
      Positioned(
        left: halfWidth + placement.position.dx - glyph.size.width / 2,
        top: halfHeight + placement.position.dy - glyph.size.height / 2,
        child: transformed,
      ),
    );
  }

  return SizedBox(
    width: math.max(1, halfWidth * 2),
    height: math.max(1, halfHeight * 2),
    child: Stack(clipBehavior: Clip.none, children: children),
  );
}

class _PathGlyph {
  const _PathGlyph({
    required this.advance,
    required this.size,
    required this.child,
  });

  final double advance;
  final Size size;
  final Widget child;
}

typedef _GlyphMetrics = ({double advance, Size size});

const _maxPathGlyphMetrics = 4096;
final _pathGlyphMetricsCache =
    <(String, TextStyle, TextDirection), _GlyphMetrics>{};
var _listensForSystemFontChanges = false;

_GlyphMetrics _pathGlyphMetrics(
  String text,
  TextStyle style,
  TextDirection direction,
) {
  if (!_listensForSystemFontChanges) {
    PaintingBinding.instance.systemFonts.addListener(
      _pathGlyphMetricsCache.clear,
    );
    _listensForSystemFontChanges = true;
  }
  final key = (text, style, direction);
  final cached = _pathGlyphMetricsCache[key];
  if (cached != null) return cached;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    maxLines: 1,
  );
  late final _GlyphMetrics metrics;
  try {
    painter.layout();
    metrics = (advance: painter.width, size: painter.size);
  } finally {
    painter.dispose();
  }
  if (_pathGlyphMetricsCache.length >= _maxPathGlyphMetrics) {
    _pathGlyphMetricsCache.clear();
  }
  _pathGlyphMetricsCache[key] = metrics;

  return metrics;
}

typedef _MapLibreFont = ({String? family, FontWeight weight, FontStyle style});

const _maxMapLibreFontCacheEntries = 256;
final _mapLibreFontCache = <String, _MapLibreFont>{};

/// Resolves a Flutter font description from a MapLibre font stack.
({String? family, List<String>? fallback, FontWeight? weight, FontStyle? style})
_mapLibreFonts(Iterable<String> fontNames) {
  final fonts = [
    for (final name in fontNames)
      if (name.isNotEmpty) name,
  ];
  if (fonts.isEmpty) {
    return (family: null, fallback: null, weight: null, style: null);
  }
  final primary = _mapLibreFont(fonts.first);
  final fallback = <String>[];
  for (final name in fonts.skip(1)) {
    final family = _mapLibreFont(name).family;
    if (family != null &&
        family != primary.family &&
        !fallback.contains(family)) {
      fallback.add(family);
    }
  }

  return (
    family: primary.family,
    fallback: fallback.isEmpty ? null : List.unmodifiable(fallback),
    weight: primary.weight,
    style: primary.style,
  );
}

_MapLibreFont _mapLibreFont(String fontName) {
  final cached = _mapLibreFontCache[fontName];
  if (cached != null) return cached;
  final lower = fontName.toLowerCase();
  final weight = lower.contains('black') || lower.contains('heavy')
      ? FontWeight.w900
      : lower.contains('extra bold') || lower.contains('extrabold')
      ? FontWeight.w800
      : lower.contains('semi bold') ||
            lower.contains('semibold') ||
            lower.contains('demi bold') ||
            lower.contains('demibold')
      ? FontWeight.w600
      : lower.contains('bold')
      ? FontWeight.w700
      : lower.contains('medium')
      ? FontWeight.w500
      : lower.contains('light')
      ? FontWeight.w300
      : lower.contains('thin')
      ? FontWeight.w100
      : FontWeight.w400;
  final style = lower.contains('italic') || lower.contains('oblique')
      ? FontStyle.italic
      : FontStyle.normal;
  final family = fontName
      .replaceFirst(
        RegExp(
          r'(?:\s+(?:extra\s*bold|semi\s*bold|demi\s*bold|'
          r'black|heavy|bold|medium|regular|italic|oblique|light|thin))+$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  final result = (
    family: family.isEmpty ? null : family,
    weight: weight,
    style: style,
  );
  if (_mapLibreFontCache.length >= _maxMapLibreFontCacheEntries) {
    _mapLibreFontCache.clear();
  }
  _mapLibreFontCache[fontName] = result;

  return result;
}

/// Fades one symbol child in and out before reporting its removal.
class _SymbolFade extends StatefulWidget {
  final bool visible;
  final bool fadeIn;
  final Widget child;
  final Duration duration;
  final VoidCallback onFadedOut;
  final bool ignorePointer;

  const _SymbolFade({
    required this.visible,
    required this.fadeIn,
    required this.child,
    required this.duration,
    required this.onFadedOut,
    required this.ignorePointer,
  });

  @override
  State<_SymbolFade> createState() => _SymbolFadeState();
}

class _SymbolFadeState extends State<_SymbolFade> {
  late double _opacity;
  late bool _animating;

  @override
  void initState() {
    super.initState();
    // Fade only symbols that are new to the current placement.
    _opacity = widget.visible && !widget.fadeIn ? 1.0 : 0.0;
    _animating = widget.fadeIn || !widget.visible;
    if (widget.fadeIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible) setState(() => _opacity = 1.0);
      });
    }
  }

  @override
  void didUpdateWidget(old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) _animating = true;
    _opacity = widget.visible ? 1.0 : 0.0;
  }

  @override
  Widget build(context) {
    if (!_animating && widget.visible) {
      // Remove the completed opacity layer while retaining rasterized content.
      return IgnorePointer(
        ignoring: widget.ignorePointer,
        child: RepaintBoundary(child: widget.child),
      );
    }
    return IgnorePointer(
      ignoring: widget.ignorePointer || !widget.visible,
      child: AnimatedOpacity(
        opacity: _opacity,
        duration: widget.duration,
        onEnd: () {
          if (_opacity == 0.0) {
            widget.onFadedOut();
          } else if (mounted) {
            setState(() => _animating = false);
          }
        },
        child: widget.child,
      ),
    );
  }
}
