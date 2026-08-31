/// @docImport 'maplibre_map.dart';
library;

// MapLibre places symbols while Flutter builds their visual representation.
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, internal, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show Ticker;

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

class _MonotonicPathSampler(final List<Offset> points) {
  final segments = [
    for (var i = 1; i < points.length; i++)
      (points[i] - points[i - 1]).distance,
  ];
  late final length = segments.fold(0.0, (sum, value) => sum + value);
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
class const MapSymbol({
  /// The stable identity of this symbol across placement updates.
  ///
  /// This value must be unique among the symbols in the same overlay.
  required final String key,

  /// The evaluated style data used to build this symbol.
  required final LabelData data,

  /// The text anchor in logical pixels from the viewport's top-left corner.
  ///
  /// A null value means that no text child is laid out for this symbol.
  required final Offset? textPos,

  /// The icon anchor in logical pixels from the viewport's top-left corner.
  ///
  /// A null value means that no icon child is laid out for this symbol.
  required final Offset? iconPos,

  /// The resolved sprite used by the default icon builder.
  ///
  /// This is null when the symbol has no sprite or its sprite is unavailable.
  /// A custom icon builder can still build a widget when [iconPos] is non-null.
  required final SpriteIcon? icon,

  /// Sprite atlas used to resolve images embedded in formatted text.
  ///
  /// This can be null when the active style has no sprite or its atlas is not
  /// available yet.
  final SpriteAtlas? spriteAtlas,

  /// Whether the symbol is present in the latest placement.
  ///
  /// A false value retains the symbol only long enough to fade out. The owner
  /// can remove it when [MapSymbolOverlay.onFadedOut] reports this [key].
  required final bool visible,

  /// Whether newly built children start transparent and fade in.
  ///
  /// This value affects a new keyed child and does not restart the fade when an
  /// existing child is rebuilt. Defaults to true.
  final bool fadeIn = true,
}) {
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

/// Live keyed positions used by the map's position-only symbol updates.
///
/// Implementations keep the immutable visual snapshot separate from current
/// screen anchors. This interface is internal and is not exported by the
/// package barrel.
@internal
abstract interface class SymbolPositionList implements List<MapSymbol> {
  /// Returns the latest anchor for one symbol component.
  Offset? anchorFor(String key, {required bool icon});

  /// Returns [symbol] with its latest positions and placement data.
  MapSymbol positioned(MapSymbol symbol);
}

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
class const MapSymbolOverlay({
  super.key,

  /// The symbol snapshot used to build, cull, and identify the current children.
  ///
  /// Keys must be unique within this list. The list must not be mutated after it
  /// is passed to the overlay. Membership, visibility, style data, or available
  /// icon and text parts must be changed by rebuilding with a new list.
  required final List<MapSymbol> symbols,

  /// Supplies the latest positions for existing children during layout.
  ///
  /// This provider supports position-only updates without replacing the
  /// [symbols] snapshot. Its symbols must keep the same keys and available icon
  /// and text parts as [symbols]. Only their keys, [MapSymbol.iconPos], and
  /// [MapSymbol.textPos] are read from this provider.
  ///
  /// When null, layout uses [symbols].
  final List<MapSymbol> Function()? symbolsProvider,

  /// Notifies the overlay to read [symbolsProvider], recull its components, and
  /// reposition its children. Position changes normally update layout without
  /// rebuilding the overlay. The overlay rebuilds when a component crosses the
  /// culling boundary. Custom builder children rebuild independently so they
  /// continue to receive the latest positions.
  final Listenable? relayout,

  /// The logical viewport size used for symbol culling.
  ///
  /// This should match the map area covered by the overlay. Culling is
  /// recomputed after position-only [relayout] notifications.
  required final Size screenSize,

  /// Called when one of a hidden symbol's children finishes fading out.
  ///
  /// A symbol with both icon and text children can report the same key more
  /// than once. A hidden symbol that is culled or has no anchor is also reported
  /// after a post-frame grace period because it has no child to animate. The
  /// reported symbol may have become visible again, so removal handlers need
  /// idempotent, visibility-aware behavior.
  required final void Function(String key) onFadedOut,

  /// Builds each symbol's icon, or hides all icons when null.
  ///
  /// Defaults to the style-derived sprite builder.
  final SymbolWidgetBuilder? iconBuilder = buildDefaultSymbolIcon,

  /// Builds each symbol's text label, or hides all labels when null.
  ///
  /// Defaults to the style-derived text builder.
  final SymbolWidgetBuilder? textBuilder = buildDefaultSymbolText,

  /// The duration of symbol fade-in and fade-out transitions.
  ///
  /// Defaults to 150 milliseconds and must not be negative.
  final Duration fadeDuration = const Duration(milliseconds: 150),

  /// The area beyond each viewport edge in which symbols are retained.
  ///
  /// Culling tests each text and icon anchor independently, not the bounds of
  /// its built widget. The default extends the horizontal edges by 120 logical
  /// pixels and the vertical edges by 60 logical pixels. An [EdgeInsets] with
  /// any non-finite or negative component is treated as [EdgeInsets.zero].
  final EdgeInsets cullingPadding = const EdgeInsets.symmetric(
    horizontal: 120,
    vertical: 60,
  ),
}) extends StatefulWidget {
  this : assert(fadeDuration >= Duration.zero);

  @override
  State<MapSymbolOverlay> createState() => _MapSymbolOverlayState();
}

class _MapSymbolOverlayState extends State<MapSymbolOverlay>
    with SingleTickerProviderStateMixin {
  final _defaultVisuals = <String, _DefaultSymbolVisuals>{};
  final _liveKeys = <String>{};
  final _pendingCulledFadeKeys = <String>{};
  var _culledFadeDrainScheduled = false;
  final _positions = _SymbolPositionStore();
  late final _BatchedSymbolFadeController _batchedFades;
  Map<String, int> _componentMembership = const {};

  @override
  void initState() {
    super.initState();
    _batchedFades = .new(
      vsync: this,
      onFadedOut: (key) => widget.onFadedOut(key),
    );
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
    _batchedFades.dispose();
    _positions.dispose();
    super.dispose();
  }

  void _handleRelayout() {
    if (!mounted) return;
    _refreshPositions();
    if (_componentMembershipChanged()) {
      setState(() {});

      return;
    }
    _positions.notifyPositionChange();
  }

  void _refreshPositions() =>
      _positions.update(widget.symbolsProvider?.call() ?? widget.symbols);

  @override
  Widget build(context) {
    final paintItems = <_SymbolPaintItem>[];
    final liveKeys = _liveKeys..clear();
    final cullingPadding = _validCullingPadding(widget.cullingPadding);
    final usesDefaultIcon = identical(
      widget.iconBuilder,
      buildDefaultSymbolIcon,
    );
    final usesDefaultText = identical(
      widget.textBuilder,
      buildDefaultSymbolText,
    );
    final componentMembership = <String, int>{};
    var paintOrdinal = 0;
    for (final symbol in widget.symbols) {
      liveKeys.add(symbol.key);
      if (symbol.visible) _pendingCulledFadeKeys.remove(symbol.key);
      final iconId = (symbol.key, true);
      final textId = (symbol.key, false);
      final iconPos = _positions.anchorFor(symbol.key, icon: true);
      final textPos = _positions.anchorFor(symbol.key, icon: false);
      final iconInBounds = _isAnchorInBounds(iconPos, cullingPadding);
      final textInBounds = _isAnchorInBounds(textPos, cullingPadding);
      var membership = 0;
      if (widget.iconBuilder != null && iconInBounds) membership |= 1;
      if (widget.textBuilder != null && textInBounds) membership |= 2;
      if (membership != 0) componentMembership[symbol.key] = membership;
      if (!iconInBounds && !textInBounds) {
        _completeCulledFade(symbol);
        continue;
      }
      _pendingCulledFadeKeys.remove(symbol.key);
      final skipsHiddenDefaults =
          !symbol.visible && widget.fadeDuration == Duration.zero;
      final defaults =
          (usesDefaultIcon || usesDefaultText) && !skipsHiddenDefaults
          ? _defaultVisuals.update(
              symbol.key,
              (cached) => cached.update(context, symbol),
              ifAbsent: () => .from(context, symbol),
            )
          : null;
      // Position icon and text independently while fading both together.
      final iconWidget = !iconInBounds
          ? null
          : usesDefaultIcon
          ? skipsHiddenDefaults
                ? symbol.icon == null
                      ? null
                      : const SizedBox.shrink()
                : defaults!.icon
          : widget.iconBuilder == null
          ? null
          : _PositionedSymbolBuilder(
              symbol: symbol,
              positions: _positions,
              builder: widget.iconBuilder!,
            );
      var hasPaintItem = false;
      if (iconWidget != null && iconPos != null) {
        hasPaintItem = true;
        paintItems.add(
          _SymbolPaintItem(
            id: iconId,
            layerIndex: symbol.data.layerIndex,
            renderGroup: symbol.data.renderGroup,
            componentOrder: 0,
            renderOrder: symbol.data.renderOrder,
            ordinal: paintOrdinal++,
            symbolKey: symbol.key,
            visible: symbol.visible,
            fadeIn: symbol.fadeIn,
            interactive: !usesDefaultIcon,
            child: iconWidget,
          ),
        );
      }
      final textWidget = !textInBounds
          ? null
          : usesDefaultText
          ? skipsHiddenDefaults
                ? !symbol.data.textPlaced || symbol.data.text.isEmpty
                      ? null
                      : const SizedBox.shrink()
                : defaults!.text
          : widget.textBuilder == null
          ? null
          : _PositionedSymbolBuilder(
              symbol: symbol,
              positions: _positions,
              builder: widget.textBuilder!,
            );
      if (textWidget != null && textPos != null) {
        hasPaintItem = true;
        paintItems.add(
          _SymbolPaintItem(
            id: textId,
            layerIndex: symbol.data.layerIndex,
            renderGroup: symbol.data.renderGroup,
            componentOrder: 1,
            renderOrder: symbol.data.renderOrder,
            ordinal: paintOrdinal++,
            symbolKey: symbol.key,
            visible: symbol.visible,
            fadeIn: symbol.fadeIn,
            interactive: !usesDefaultText,
            child: textWidget,
          ),
        );
      }
      if (!symbol.visible && !hasPaintItem) _completeCulledFade(symbol);
    }
    _defaultVisuals.removeWhere((key, _) => !liveKeys.contains(key));
    _componentMembership = componentMembership;
    paintItems.sort(_SymbolPaintItem.compare);
    _batchedFades.update(paintItems, widget.fadeDuration);

    return _SymbolBatch(
      paintItems: paintItems,
      positions: _positions,
      fades: _batchedFades,
      screenSize: widget.screenSize,
    );
  }

  bool _componentMembershipChanged() {
    final padding = _validCullingPadding(widget.cullingPadding);
    var count = 0;
    for (final key in _liveKeys) {
      var membership = 0;
      if (widget.iconBuilder != null &&
          _isAnchorInBounds(_positions.anchorFor(key, icon: true), padding)) {
        membership |= 1;
      }
      if (widget.textBuilder != null &&
          _isAnchorInBounds(_positions.anchorFor(key, icon: false), padding)) {
        membership |= 2;
      }
      if (membership == 0) continue;
      count++;
      if (_componentMembership[key] != membership) return true;
    }

    return count != _componentMembership.length;
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
    _pendingCulledFadeKeys.add(symbol.key);
    if (_culledFadeDrainScheduled) return;
    _culledFadeDrainScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _culledFadeDrainScheduled = false;
        while (_pendingCulledFadeKeys.isNotEmpty) {
          final key = _pendingCulledFadeKeys.first;
          _pendingCulledFadeKeys.remove(key);
          widget.onFadedOut(key);
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }
}

class const _SymbolPaintItem({
  required final Object id,
  required final int layerIndex,
  required final int renderGroup,
  required final int componentOrder,
  required final int renderOrder,
  required final int ordinal,
  required final String symbolKey,
  required final bool visible,
  required final bool fadeIn,
  required final bool interactive,
  required final Widget child,
}) {
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

class _BatchedSymbolFadeController extends ChangeNotifier {
  new({required TickerProvider vsync, required this.onFadedOut}) {
    _ticker = vsync.createTicker(_handleTick);
  }

  final void Function(String key) onFadedOut;
  late final Ticker _ticker;
  final Map<Object, _BatchedSymbolFade> _fades = {};
  Duration _timeline = Duration.zero;
  Duration _tickerBase = Duration.zero;
  bool _disposed = false;

  double opacityFor(Object id) => _fades[id]?.opacity ?? 1;

  bool isVisible(Object id) => _fades[id]?.visible ?? false;

  void update(List<_SymbolPaintItem> items, Duration duration) {
    final liveIds = {for (final item in items) item.id};
    var changed = false;
    _fades.removeWhere((id, _) {
      final removes = !liveIds.contains(id);
      if (removes) changed = true;

      return removes;
    });
    for (final item in items) {
      final existing = _fades[item.id];
      if (existing == null) {
        final startsVisible = item.visible && !item.fadeIn;
        final fade = _BatchedSymbolFade(
          symbolKey: item.symbolKey,
          visible: item.visible,
          opacity: startsVisible ? 1 : 0,
          from: startsVisible ? 1 : 0,
          target: item.visible ? 1 : 0,
          startedAt: _timeline,
          duration: duration,
        );
        _fades[item.id] = fade;
        changed = true;
        if (fade.opacity != fade.target && duration > Duration.zero) {
          fade.animating = true;
        } else {
          fade.opacity = fade.target;
          if (!item.visible) _scheduleFadeCompletion(item.id, fade);
        }
        continue;
      }
      existing.symbolKey = item.symbolKey;
      if (existing.visible != item.visible) {
        _startTransition(item.id, existing, item.visible, duration);
        changed = true;
      } else if (existing.animating && existing.duration != duration) {
        existing
          ..from = existing.opacity
          ..startedAt = _timeline
          ..duration = duration;
        if (duration == Duration.zero) {
          existing
            ..opacity = existing.target
            ..animating = false;
          if (!existing.visible) {
            _scheduleFadeCompletion(item.id, existing);
          }
        }
        changed = true;
      }
    }
    if (_fades.values.any((fade) => fade.animating)) {
      _ensureTicking();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
    if (changed) notifyListeners();
  }

  void _startTransition(
    Object id,
    _BatchedSymbolFade fade,
    bool visible,
    Duration duration,
  ) {
    fade
      ..visible = visible
      ..from = fade.opacity
      ..target = visible ? 1 : 0
      ..startedAt = _timeline
      ..duration = duration
      ..generation = fade.generation + 1
      ..completionScheduled = false
      ..animating =
          fade.opacity != (visible ? 1 : 0) && duration > Duration.zero;
    if (!fade.animating) {
      fade.opacity = fade.target;
      if (!visible) _scheduleFadeCompletion(id, fade);
    }
  }

  void _ensureTicking() {
    if (_ticker.isActive) return;
    _tickerBase = _timeline;
    _ticker.start();
  }

  void _handleTick(Duration elapsed) {
    _timeline = _tickerBase + elapsed;
    var changed = false;
    for (final entry in _fades.entries) {
      final fade = entry.value;
      if (!fade.animating) continue;
      final durationMicros = fade.duration.inMicroseconds;
      final elapsedMicros = (_timeline - fade.startedAt).inMicroseconds;
      final progress = durationMicros <= 0
          ? 1.0
          : (elapsedMicros / durationMicros).clamp(0.0, 1.0);
      fade.opacity = fade.from + (fade.target - fade.from) * progress;
      changed = true;
      if (progress < 1) continue;
      fade.animating = false;
      if (!fade.visible) _scheduleFadeCompletion(entry.key, fade);
    }
    if (!_fades.values.any((fade) => fade.animating)) _ticker.stop();
    if (changed) notifyListeners();
  }

  void _scheduleFadeCompletion(Object id, _BatchedSymbolFade fade) {
    if (fade.completionScheduled) return;
    fade.completionScheduled = true;
    final generation = fade.generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final current = _fades[id];
      if (current == null ||
          current.generation != generation ||
          current.visible) {
        return;
      }
      onFadedOut(current.symbolKey);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _fades.clear();
    _ticker.dispose();
    super.dispose();
  }
}

class _BatchedSymbolFade({
  required var String symbolKey,
  required var bool visible,
  required var double opacity,
  required var double from,
  required var double target,
  required var Duration startedAt,
  required var Duration duration,
}) {
  bool animating = false;
  int generation = 0;
  bool completionScheduled = false;
}

class _SymbolBatch extends MultiChildRenderObjectWidget {
  _SymbolBatch({
    required List<_SymbolPaintItem> paintItems,
    required this.positions,
    required this.fades,
    required this.screenSize,
  }) : entries = [
         for (final item in paintItems)
           _DefaultSymbolBatchEntry(item.id, interactive: item.interactive),
       ],
       positionRevision = positions.revision,
       super(
         children: [
           for (final item in paintItems)
             RepaintBoundary(
               key: ValueKey(item.id),
               child: item.interactive
                   ? IgnorePointer(ignoring: !item.visible, child: item.child)
                   : item.child,
             ),
         ],
       );

  final List<_DefaultSymbolBatchEntry> entries;
  final _SymbolPositionStore positions;
  final _BatchedSymbolFadeController fades;
  final Size screenSize;
  final int positionRevision;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSymbolBatch(
    entries: entries,
    positions: positions,
    fades: fades,
    screenSize: screenSize,
    positionRevision: positionRevision,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSymbolBatch renderObject,
  ) {
    renderObject
      ..entries = entries
      ..positions = positions
      ..fades = fades
      ..screenSize = screenSize
      ..positionRevision = positionRevision;
  }
}

class const _DefaultSymbolBatchEntry(
  final Object id, {
  required final bool interactive,
});

class _DefaultSymbolBatchParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSymbolBatch({
  required var List<_DefaultSymbolBatchEntry> _entries,
  required var _SymbolPositionStore _positions,
  required var _BatchedSymbolFadeController _fades,
  required var Size _screenSize,
  required var int _positionRevision,
}) extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DefaultSymbolBatchParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _DefaultSymbolBatchParentData
        > {
  static const _hiddenPosition = Offset(-100000, -100000);
  var _hasLayout = false;

  set entries(List<_DefaultSymbolBatchEntry> value) {
    final needsLayout = !_sameEntryOrder(_entries, value);
    _entries = value;
    if (needsLayout) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
      markNeedsSemanticsUpdate();
    }
  }

  set positions(_SymbolPositionStore value) {
    if (identical(_positions, value)) return;
    if (attached) _positions.removeListener(_handlePositionChange);
    _positions = value;
    if (attached) _positions.addListener(_handlePositionChange);
    _handlePositionChange();
  }

  set fades(_BatchedSymbolFadeController value) {
    if (identical(_fades, value)) return;
    if (attached) _fades.removeListener(_handleFadeChange);
    _fades = value;
    if (attached) _fades.addListener(_handleFadeChange);
    markNeedsPaint();
  }

  set screenSize(Size value) {
    if (_screenSize == value) return;
    _screenSize = value;
    markNeedsLayout();
  }

  set positionRevision(int value) {
    if (_positionRevision == value) return;
    _positionRevision = value;
    _handlePositionChange();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DefaultSymbolBatchParentData) {
      child.parentData = _DefaultSymbolBatchParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _positions.addListener(_handlePositionChange);
    _fades.addListener(_handleFadeChange);
  }

  @override
  void detach() {
    _positions.removeListener(_handlePositionChange);
    _fades.removeListener(_handleFadeChange);
    super.detach();
  }

  @override
  void markNeedsLayout() {
    _hasLayout = false;
    super.markNeedsLayout();
  }

  void _handlePositionChange() {
    if (!_hasLayout) {
      markNeedsLayout();

      return;
    }
    _updateChildOffsets();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void _handleFadeChange() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_screenSize);

  @override
  void performLayout() {
    size = constraints.constrain(_screenSize);
    final childConstraints = BoxConstraints.loose(size);
    var child = firstChild;
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      final parentData = child.parentData! as _DefaultSymbolBatchParentData;
      child = parentData.nextSibling;
    }
    _hasLayout = true;
    _updateChildOffsets();
  }

  void _updateChildOffsets() {
    var child = firstChild;
    var index = 0;
    while (child != null) {
      assert(index < _entries.length);
      final parentData = child.parentData! as _DefaultSymbolBatchParentData;
      final anchor = index < _entries.length
          ? _positions.anchor(_entries[index].id) ?? _hiddenPosition
          : _hiddenPosition;
      parentData.offset =
          anchor - Offset(child.size.width / 2, child.size.height / 2);
      child = parentData.nextSibling;
      index++;
    }
    assert(index == _entries.length);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    var index = 0;
    while (child != null) {
      final currentChild = child;
      final parentData = child.parentData! as _DefaultSymbolBatchParentData;
      final entry = _entries[index];
      final childOffset = offset + parentData.offset;
      final alpha = (_fades.opacityFor(entry.id).clamp(0.0, 1.0) * 255).round();
      if (alpha == 255) {
        context.paintChild(currentChild, childOffset);
      } else if (alpha > 0) {
        context.pushOpacity(
          childOffset,
          alpha,
          (innerContext, innerOffset) =>
              innerContext.paintChild(currentChild, innerOffset),
        );
      }
      child = parentData.nextSibling;
      index++;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    var index = _entries.length - 1;
    while (child != null) {
      final currentChild = child;
      final parentData = child.parentData! as _DefaultSymbolBatchParentData;
      final entry = _entries[index];
      if (entry.interactive && _fades.isVisible(entry.id)) {
        final hit = result.addWithPaintOffset(
          offset: parentData.offset,
          position: position,
          hitTest: (result, transformed) =>
              currentChild.hitTest(result, position: transformed),
        );
        if (hit) return true;
      }
      child = parentData.previousSibling;
      index--;
    }

    return false;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final parentData = child.parentData! as _DefaultSymbolBatchParentData;
    transform.multiply(
      Matrix4.translationValues(parentData.offset.dx, parentData.offset.dy, 0),
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var child = firstChild;
    var index = 0;
    while (child != null) {
      final parentData = child.parentData! as _DefaultSymbolBatchParentData;
      if (_fades.opacityFor(_entries[index].id) > 0) visitor(child);
      child = parentData.nextSibling;
      index++;
    }
  }
}

bool _sameEntryOrder(
  List<_DefaultSymbolBatchEntry> left,
  List<_DefaultSymbolBatchEntry> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].id != right[index].id) return false;
  }

  return true;
}

class const _DefaultSymbolVisuals({
  required final LabelData data,
  required final SpriteIcon? sprite,
  required final SpriteAtlas? spriteAtlas,
  required final Widget? icon,
  required final Widget? text,
}) {
  factory from(BuildContext context, MapSymbol symbol) => .new(
    data: symbol.data,
    sprite: symbol.icon,
    spriteAtlas: symbol.spriteAtlas,
    icon: buildDefaultSymbolIcon(context, symbol),
    text: buildDefaultSymbolText(context, symbol),
  );

  _DefaultSymbolVisuals update(BuildContext context, MapSymbol symbol) {
    final sameSprite = identical(sprite, symbol.icon);
    final sameSpriteAtlas = identical(spriteAtlas, symbol.spriteAtlas);
    final sameIconVisual = _sameDefaultIconVisual(data, symbol.data);
    final sameTextVisual = _sameDefaultTextVisual(data, symbol.data);
    if (sameIconVisual && sameTextVisual && sameSprite && sameSpriteAtlas) {
      return this;
    }

    return .new(
      data: symbol.data,
      sprite: symbol.icon,
      spriteAtlas: symbol.spriteAtlas,
      icon: sameIconVisual && sameSprite
          ? icon
          : buildDefaultSymbolIcon(context, symbol),
      text: sameTextVisual && sameSpriteAtlas
          ? text
          : buildDefaultSymbolText(context, symbol),
    );
  }
}

bool _sameDefaultIconVisual(LabelData left, LabelData right) =>
    identical(left, right) ||
    left.iconScale == right.iconScale &&
        left.iconOpacity == right.iconOpacity &&
        left.iconR == right.iconR &&
        left.iconG == right.iconG &&
        left.iconB == right.iconB &&
        left.iconA == right.iconA &&
        left.iconHaloR == right.iconHaloR &&
        left.iconHaloG == right.iconHaloG &&
        left.iconHaloB == right.iconHaloB &&
        left.iconHaloA == right.iconHaloA &&
        left.iconHaloWidth == right.iconHaloWidth &&
        left.iconHaloBlur == right.iconHaloBlur &&
        left.iconFitWidth == right.iconFitWidth &&
        left.iconFitHeight == right.iconFitHeight &&
        left.iconRotationWithMap == right.iconRotationWithMap &&
        left.iconAlongLine == right.iconAlongLine &&
        left.alongLine == right.alongLine &&
        left.iconAngle == right.iconAngle &&
        left.iconKeepUpright == right.iconKeepUpright &&
        left.iconRotation == right.iconRotation &&
        _sameAffineTransform(left.iconTransform, right.iconTransform) &&
        left.iconTranslateX == right.iconTranslateX &&
        left.iconTranslateY == right.iconTranslateY &&
        _sameLabelPath(left.iconPath, right.iconPath) &&
        _sameLabelPath(left.textPath, right.textPath);

bool _sameDefaultTextVisual(LabelData left, LabelData right) =>
    identical(left, right) ||
    left.textPlaced == right.textPlaced &&
        left.text == right.text &&
        left.visualText == right.visualText &&
        left.fontSize == right.fontSize &&
        left.textR == right.textR &&
        left.textG == right.textG &&
        left.textB == right.textB &&
        left.textA == right.textA &&
        left.haloR == right.haloR &&
        left.haloG == right.haloG &&
        left.haloB == right.haloB &&
        left.haloA == right.haloA &&
        left.haloWidth == right.haloWidth &&
        left.haloBlur == right.haloBlur &&
        left.textOpacity == right.textOpacity &&
        left.letterSpacing == right.letterSpacing &&
        left.lineHeight == right.lineHeight &&
        left.maxWidth == right.maxWidth &&
        left.textW == right.textW &&
        left.textFont == right.textFont &&
        _sameStrings(left.textFonts, right.textFonts) &&
        _sameTextSections(left.textSections, right.textSections) &&
        _sameTextSections(left.visualTextSections, right.visualTextSections) &&
        left.alongLine == right.alongLine &&
        left.vertical == right.vertical &&
        left.angle == right.angle &&
        left.textRotation == right.textRotation &&
        left.textKeepUpright == right.textKeepUpright &&
        left.textJustify == right.textJustify &&
        left.textDirection == right.textDirection &&
        _sameAffineTransform(left.textTransform, right.textTransform) &&
        left.textTranslateX == right.textTranslateX &&
        left.textTranslateY == right.textTranslateY &&
        _sameLabelPath(left.textPath, right.textPath);

bool _sameAffineTransform(
  LabelAffineTransform left,
  LabelAffineTransform right,
) =>
    identical(left, right) ||
    left.xx == right.xx &&
        left.xy == right.xy &&
        left.yx == right.yx &&
        left.yy == right.yy;

bool _sameLabelPath(List<LabelPathPoint> left, List<LabelPathPoint> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].x != right[index].x || left[index].y != right[index].y) {
      return false;
    }
  }

  return true;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }

  return true;
}

bool _sameTextSections(
  List<LabelTextSection> left,
  List<LabelTextSection> right,
) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final a = left[index];
    final b = right[index];
    if (a.start != b.start ||
        a.end != b.end ||
        a.fontScale != b.fontScale ||
        a.color != b.color ||
        a.imageId != b.imageId ||
        !_sameStrings(a.fonts, b.fonts)) {
      return false;
    }
  }

  return true;
}

class _SymbolPositionStore extends ChangeNotifier {
  Map<String, MapSymbol> _symbols = const {};
  Map<Object, Offset> _anchors = const {};
  SymbolPositionList? _livePositions;
  int _revision = 0;

  int get revision => _revision;

  void update(List<MapSymbol> symbols) {
    _revision++;
    if (symbols is SymbolPositionList) {
      _livePositions = symbols;
      _symbols = const {};
      _anchors = const {};

      return;
    }
    _livePositions = null;
    _symbols = {for (final symbol in symbols) symbol.key: symbol};
    _anchors = {
      for (final symbol in symbols) (symbol.key, true): ?symbol.iconPos,
      for (final symbol in symbols) (symbol.key, false): ?symbol.textPos,
    };
  }

  void notifyPositionChange() => notifyListeners();

  Offset? anchor(Object id) {
    final component = id as (String, bool);

    return anchorFor(component.$1, icon: component.$2);
  }

  Offset? anchorFor(String key, {required bool icon}) {
    final livePositions = _livePositions;
    if (livePositions != null) {
      return livePositions.anchorFor(key, icon: icon);
    }

    return _anchors[(key, icon)];
  }

  MapSymbol positioned(MapSymbol symbol) {
    final livePositions = _livePositions;
    if (livePositions != null) return livePositions.positioned(symbol);
    final positioned = _symbols[symbol.key];
    if (positioned == null) return symbol;

    return .new(
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

class const _PositionedSymbolBuilder({
  required final MapSymbol symbol,
  required final _SymbolPositionStore positions,
  required final SymbolWidgetBuilder builder,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: positions,
    builder: (context, _) =>
        builder(context, positions.positioned(symbol)) ??
        const SizedBox.shrink(),
  );
}

/// Builds the default style-derived sprite for a placed symbol.
///
/// Returns null when [MapSymbol.icon] is null.
Widget? buildDefaultSymbolIcon(BuildContext context, MapSymbol symbol) {
  final icon = symbol.icon;
  if (icon == null) return null;
  final data = symbol.data;
  if (data.iconOpacity <= 0) return const SizedBox.shrink();
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

/// Builds the default style-derived text for a placed symbol.
///
/// Returns null when no non-empty text label was placed.
Widget? buildDefaultSymbolText(BuildContext context, MapSymbol symbol) {
  final data = symbol.data;
  if (!data.textPlaced || data.text.isEmpty) return null;
  if (data.textOpacity <= 0) return const SizedBox.shrink();
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

class const _SymbolTextPart({
  required final String text,
  required final TextStyle style,
  final SpriteIcon? image,
  final double imageScale = 1,
  final bool imageSection = false,
});

List<_SymbolTextPart> _symbolTextParts(
  MapSymbol symbol,
  TextStyle baseStyle,
  List<String> baseFonts, {
  required String text,
  required List<LabelTextSection> sections,
}) {
  final data = symbol.data;
  if (sections.isEmpty) return [_SymbolTextPart(text: text, style: baseStyle)];
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
    .left => TextAlign.left,
    .right => TextAlign.right,
    .auto || .center => TextAlign.center,
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
  if (image == null) return const WidgetSpan(child: SizedBox.shrink());
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
  final pathAngle =
      _pathAngle(data.textPath, data.angle, keepUpright: data.textKeepUpright) +
      data.textRotation;
  final advanceScale = _lineAdvanceScale(lineScale, pathAngle);
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
  final placementsForLayout = <_PathGlyphPlacement>[];
  final children = <Widget>[];
  for (var i = 0; i < glyphs.length; i++) {
    final glyph = glyphs[i];
    final placement = placements[i];
    placementsForLayout.add(
      _PathGlyphPlacement(
        size: glyph.size,
        offset: Offset(
          halfWidth + placement.position.dx - glyph.size.width / 2,
          halfHeight + placement.position.dy - glyph.size.height / 2,
        ),
      ),
    );
    children.add(
      Transform(
        alignment: Alignment.center,
        transform: _pathGlyphTransform(
          data.textTransform,
          placement.angle + data.textRotation,
        ),
        child: glyph.child,
      ),
    );
  }

  return _PathGlyphLayout(
    desiredSize: Size(math.max(1, halfWidth * 2), math.max(1, halfHeight * 2)),
    placements: placementsForLayout,
    children: children,
  );
}

Matrix4 _pathGlyphTransform(LabelAffineTransform transform, double angle) {
  final scale = _lineSymbolScale(transform);
  final hasFiniteScale = scale.x.isFinite && scale.y.isFinite;
  final scaleX = hasFiniteScale ? scale.x : 1.0;
  final scaleY = hasFiniteScale ? scale.y : 1.0;
  final safeAngle = angle.isFinite ? angle : 0.0;
  final cosine = math.cos(safeAngle);
  final sine = math.sin(safeAngle);

  return Matrix4.identity()
    ..setEntry(0, 0, cosine * scaleX)
    ..setEntry(1, 0, sine * scaleY)
    ..setEntry(0, 1, -sine * scaleX)
    ..setEntry(1, 1, cosine * scaleY);
}

class const _PathGlyphLayout({
  required final Size desiredSize,
  required final List<_PathGlyphPlacement> placements,
  required super.children,
}) extends MultiChildRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPathGlyphLayout(desiredSize: desiredSize, placements: placements);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderPathGlyphLayout renderObject,
  ) {
    renderObject
      ..desiredSize = desiredSize
      ..placements = placements;
  }
}

class const _PathGlyphPlacement({
  required final Size size,
  required final Offset offset,
});

class _PathGlyphParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPathGlyphLayout({
  required var Size _desiredSize,
  required var List<_PathGlyphPlacement> _placements,
}) extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PathGlyphParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PathGlyphParentData> {
  set desiredSize(Size value) {
    if (_desiredSize == value) return;
    _desiredSize = value;
    markNeedsLayout();
  }

  set placements(List<_PathGlyphPlacement> value) {
    _placements = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PathGlyphParentData) {
      child.parentData = _PathGlyphParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_desiredSize);

  @override
  void performLayout() {
    size = constraints.constrain(_desiredSize);
    var child = firstChild;
    var index = 0;
    while (child != null) {
      assert(index < _placements.length);
      final placement = _placements[index];
      child.layout(BoxConstraints.tight(placement.size));
      final parentData = child.parentData! as _PathGlyphParentData;
      parentData.offset = placement.offset;
      child = parentData.nextSibling;
      index++;
    }
    assert(index == _placements.length);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final parentData = child.parentData! as _PathGlyphParentData;
    transform.multiply(
      Matrix4.translationValues(parentData.offset.dx, parentData.offset.dy, 0),
    );
  }
}

class const _PathGlyph({
  required final double advance,
  required final Size size,
  required final Widget child,
});

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
