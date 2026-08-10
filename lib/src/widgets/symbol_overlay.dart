/// @docImport 'maplibre_map.dart';
library;

// MapLibre places symbols while Flutter builds their visual representation.
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show Listenable, listEquals;
import 'package:flutter/material.dart';

import '../labels/label_data.dart';
import '../sprites/sprite_atlas.dart';

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
    required this.visible,
    this.fadeIn = true,
  });

  /// The anchor used for viewport culling.
  ///
  /// The text anchor is preferred when both anchors are present. This is null
  /// when neither part has been placed.
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
typedef SymbolWidgetBuilder =
    Widget? Function(BuildContext context, MapSymbol symbol);

/// A widget that lays out icon and text widgets for placed map symbols.
///
/// Each builder result is centered on its corresponding [MapSymbol] anchor. A
/// symbol is omitted when [MapSymbol.anchor] lies outside the viewport extended
/// by [cullingPadding].
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
  /// This provider supports position-only updates without rebuilding symbol
  /// widgets. Its symbols must keep the same keys and available icon and text
  /// parts as [symbols]. Only their keys, [MapSymbol.iconPos], and
  /// [MapSymbol.textPos] are read from this provider.
  ///
  /// When null, layout uses [symbols].
  final List<MapSymbol> Function()? symbolsProvider;

  /// Notifies the layout delegate to read [symbolsProvider] and reposition its
  /// existing children.
  ///
  /// Notifications perform layout without calling the symbol builders. A
  /// changing position source therefore needs both this signal and a
  /// [symbolsProvider] that returns its latest snapshot.
  final Listenable? relayout;

  /// The logical viewport size used for symbol culling.
  ///
  /// This should match the map area covered by the overlay. Culling occurs when
  /// [symbols] is built and is not recomputed by position-only [relayout]
  /// notifications.
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
  /// Culling tests the symbol's preferred [MapSymbol.anchor], not the bounds of
  /// its built widgets. The default extends the horizontal edges by 120 logical
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

  @override
  Widget build(context) {
    final widgets = <Widget>[];
    final childIds = <Object>[];
    final liveKeys = _liveKeys..clear();
    final cullingPadding = _validCullingPadding(widget.cullingPadding);
    for (final symbol in widget.symbols) {
      liveKeys.add(symbol.key);
      if (symbol.visible) _pendingCulledFadeKeys.remove(symbol.key);
      final anchor = symbol.anchor;
      if (anchor == null) {
        _completeCulledFade(symbol);
        continue;
      }
      if (anchor.dx < -cullingPadding.left ||
          anchor.dx > widget.screenSize.width + cullingPadding.right ||
          anchor.dy < -cullingPadding.top ||
          anchor.dy > widget.screenSize.height + cullingPadding.bottom) {
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
      final iconWidget = usesDefaultIcon
          ? defaults!.icon
          : widget.iconBuilder?.call(context, symbol);
      if (iconWidget != null && symbol.iconPos != null) {
        final id = (symbol.key, true);
        childIds.add(id);
        widgets.add(
          _layoutChild(id, symbol, iconWidget, ignorePointer: usesDefaultIcon),
        );
      }
      final textWidget = usesDefaultText
          ? defaults!.text
          : widget.textBuilder?.call(context, symbol);
      if (textWidget != null && symbol.textPos != null) {
        final id = (symbol.key, false);
        childIds.add(id);
        widgets.add(
          _layoutChild(id, symbol, textWidget, ignorePointer: usesDefaultText),
        );
      }
    }
    _defaultVisuals.removeWhere((key, _) => !liveKeys.contains(key));

    return CustomMultiChildLayout(
      delegate: _SymbolLayoutDelegate(
        symbolsProvider: widget.symbolsProvider ?? () => widget.symbols,
        childIds: childIds,
        relayout: widget.relayout,
      ),
      children: widgets,
    );
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

class _DefaultSymbolVisuals {
  const _DefaultSymbolVisuals({
    required this.data,
    required this.sprite,
    required this.icon,
    required this.text,
  });

  factory _DefaultSymbolVisuals.from(BuildContext context, MapSymbol symbol) =>
      _DefaultSymbolVisuals(
        data: symbol.data,
        sprite: symbol.icon,
        icon: buildDefaultSymbolIcon(context, symbol),
        text: buildDefaultSymbolText(context, symbol),
      );

  final LabelData data;
  final SpriteIcon? sprite;
  final Widget? icon;
  final Widget? text;

  _DefaultSymbolVisuals update(BuildContext context, MapSymbol symbol) {
    final sameData = identical(data, symbol.data);
    final sameSprite = identical(sprite, symbol.icon);
    if (sameData && sameSprite) return this;

    return _DefaultSymbolVisuals(
      data: symbol.data,
      sprite: symbol.icon,
      icon: buildDefaultSymbolIcon(context, symbol),
      text: sameData ? text : buildDefaultSymbolText(context, symbol),
    );
  }
}

class _SymbolLayoutDelegate extends MultiChildLayoutDelegate {
  static const _hiddenPosition = Offset(-100000, -100000);

  _SymbolLayoutDelegate({
    required this.symbolsProvider,
    required this.childIds,
    super.relayout,
  });

  final List<MapSymbol> Function() symbolsProvider;
  final List<Object> childIds;

  @override
  void performLayout(size) {
    final positions = <Object, Offset>{};
    for (final symbol in symbolsProvider()) {
      final iconPos = symbol.iconPos;
      if (iconPos != null) positions[(symbol.key, true)] = iconPos;
      final textPos = symbol.textPos;
      if (textPos != null) positions[(symbol.key, false)] = textPos;
    }
    for (final id in childIds) {
      if (!hasChild(id)) continue;
      final childSize = layoutChild(id, BoxConstraints.loose(size));
      final position = positions[id] ?? _hiddenPosition;
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
      !identical(symbolsProvider, oldDelegate.symbolsProvider);
}

/// Builds the default style-derived sprite for a placed symbol.
///
/// Returns null when [MapSymbol.icon] is null.
Widget? buildDefaultSymbolIcon(BuildContext context, MapSymbol symbol) {
  final icon = symbol.icon;
  if (icon == null) return null;

  return SpriteIconWidget(
    icon: icon,
    scale: symbol.data.iconScale,
    opacity: symbol.data.iconOpacity,
    tint: symbol.data.iconColor,
  );
}

/// Builds the default style-derived text for a placed symbol.
///
/// Returns null when no non-empty text label was placed.
Widget? buildDefaultSymbolText(BuildContext context, MapSymbol symbol) {
  final data = symbol.data;
  if (!data.textPlaced || data.text.isEmpty) return null;
  final fontSize = data.fontSize;
  // Use native collision bounds to preserve the placed label width.
  final boxWidth = data.alongLine && data.textW > 0
      ? math.sqrt(data.textW * data.textW + data.textH * data.textH)
      : data.textW;
  final maxWidth = data.alongLine
      ? (boxWidth > 0 ? boxWidth + fontSize : fontSize * 8)
      : (boxWidth > 0
            ? boxWidth + fontSize
            : (data.maxWidth > 0 ? data.maxWidth * fontSize : fontSize * 8));
  Text label(TextStyle style) => Text(
    data.text,
    style: style,
    textAlign: TextAlign.center,
    softWrap: false,
    maxLines: data.alongLine ? 1 : null,
    overflow: TextOverflow.visible,
  );
  final font = _mapLibreFont(data.textFont);
  final fillStyle = TextStyle(
    fontSize: fontSize,
    color: data.textColor,
    fontFamily: font.family,
    fontWeight: font.weight,
    fontStyle: font.style,
    letterSpacing: data.letterSpacing * fontSize,
    height: data.lineHeight,
  );
  final text = SizedBox(
    width: maxWidth,
    child: data.haloWidth > 0
        ? Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              label(
                fillStyle.copyWith(
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = data.haloWidth * 2
                    ..strokeJoin = StrokeJoin.round
                    ..maskFilter = data.haloBlur > 0
                        ? MaskFilter.blur(BlurStyle.normal, data.haloBlur)
                        : null
                    ..color = data.haloColor,
                ),
              ),
              label(fillStyle),
            ],
          )
        : label(fillStyle),
  );
  final opacity = data.textOpacity.clamp(0.0, 1.0);
  final styledText = opacity < 1
      ? Opacity(opacity: opacity, child: text)
      : text;
  if (!data.alongLine || data.angle == 0) return styledText;
  // Keep line labels upright after applying their placement angle.
  var angle = data.angle;
  if (angle > math.pi / 2) angle -= math.pi;
  if (angle < -math.pi / 2) angle += math.pi;

  return Transform.rotate(angle: angle, child: styledText);
}

/// Resolves a Flutter font description from a MapLibre font name.
({String? family, FontWeight? weight, FontStyle? style}) _mapLibreFont(
  String fontName,
) {
  if (fontName.isEmpty) {
    return (family: null, weight: null, style: null);
  }
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

  return (family: family.isEmpty ? null : family, weight: weight, style: style);
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
