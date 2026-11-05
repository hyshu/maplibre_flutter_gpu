import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'label_data.dart';

/// Borrowed inputs for one synchronous diagnostic capture. Internal.
///
/// The recorder copies scalar values and nested collections before returning.
@internal
class const LabelUpdateDiagnosticEntry({
  required final String key,
  required final LabelData data,
  required final bool visible,
  required final bool fadeIn,
  required final Offset? textPosition,
  required final Offset? iconPosition,
});

/// Classifies consecutive label projections without changing their rendering.
///
/// Each instance retains only its previous copied snapshot. It retains no
/// placement objects, atlas, image, native buffer, or GPU resource. Counters
/// accumulate across all instances in the current isolate. Layer observations
/// cover the union of previous and current layer indices, including removals.
/// Frames that do not project labels are not observed. Internal.
@internal
class LabelUpdateDiagnostics {
  /// Whether the optional Android capture path is enabled.
  static bool get enabled =>
      const bool.fromEnvironment('MAPLIBRE_LABEL_UPDATE_DIAGNOSTICS') &&
      defaultTargetPlatform == TargetPlatform.android;

  static final _totals = <String, int>{
    'resets': 0,
    'comparisonMicros': 0,
    for (final scope in [
      'frames',
      'layers',
      'nativeChanged.frames',
      'nativeChanged.layers',
    ]) ...{
      for (final name in [
        'observed',
        'baseline',
        'compared',
        'unchanged',
        'projectedPositionOnly',
        'nativeAnchorOnly',
        'rejected',
        'nativeAnchorChanged',
        'projectedPositionChanged',
      ])
        '$scope.$name': 0,
      for (final outcome in [
        'baseline',
        'unchanged',
        'projectedPositionOnly',
        'nativeAnchorOnly',
        'rejected',
      ])
        '$scope.${outcome}Entries': 0,
      for (final reason in _Reason.values) '$scope.reason.${reason.name}': 0,
    },
  };

  _ProjectionSnapshot? _previous;

  /// Returns copied cumulative counters without resetting any instance.
  ///
  /// Reasons and changed-field flags overlap. Outcome categories are exclusive.
  /// Entry totals count current reconciled labels, including fading entries.
  /// The nativeChanged families include only comparisons with a changed native
  /// placement version. They exclude the first observation after a reset.
  /// Microseconds measure elapsed capture, comparison, and counter tally time.
  static Map<String, int> snapshot() => Map.unmodifiable(_totals);

  /// Copies one complete, ordered, reconciled label projection.
  ///
  /// [atlasChanged] compares atlas identity with the previous projection without
  /// retaining the atlas. Anchor-only classification permits only geographic
  /// anchors, native center offsets, and projected positions to differ. It does
  /// not establish unchanged culling, map topology, or custom builder output.
  /// Returns the counter increments for this observation.
  Map<String, int> record(
    Iterable<LabelUpdateDiagnosticEntry> entries, {
    required bool atlasChanged,
    required int nativeVersion,
  }) {
    final watch = Stopwatch()..start();
    final current = _ProjectionSnapshot.capture(entries, nativeVersion);
    final previous = _previous;
    final increments = <String, int>{};
    _classify(
      increments,
      'frames',
      previous?.entries,
      current.entries,
      atlasChanged,
    );
    for (final layer in {...?previous?.layers.keys, ...current.layers.keys}) {
      _classify(
        increments,
        'layers',
        previous == null ? null : previous.layers[layer] ?? const [],
        current.layers[layer] ?? const [],
        atlasChanged,
      );
    }
    if (previous != null && previous.nativeVersion != nativeVersion) {
      for (final entry in increments.entries.toList()) {
        increments['nativeChanged.${entry.key}'] = entry.value;
      }
    }
    _previous = current;
    for (final entry in increments.entries) {
      _totals[entry.key] = _totals[entry.key]! + entry.value;
    }
    watch.stop();
    increments['comparisonMicros'] = watch.elapsedMicroseconds;
    _totals['comparisonMicros'] =
        _totals['comparisonMicros']! + watch.elapsedMicroseconds;

    return increments;
  }

  /// Drops the previous projection while preserving cumulative counters.
  void reset() {
    _previous = null;
    _totals['resets'] = _totals['resets']! + 1;
  }
}

enum _Reason {
  membership,
  parts,
  order,
  fade,
  style,
  content,
  atlas,
  affine,
  size,
  path,
}

class _ProjectionSnapshot {
  _ProjectionSnapshot.capture(
    Iterable<LabelUpdateDiagnosticEntry> source,
    this.nativeVersion,
  ) {
    for (final entry in source) {
      final captured = _EntrySnapshot.capture(entry);
      entries.add(captured);
      (layers[entry.data.layerIndex] ??= []).add(captured);
    }
  }

  final entries = <_EntrySnapshot>[];
  final layers = <int, List<_EntrySnapshot>>{};
  final int nativeVersion;
}

class _EntrySnapshot {
  _EntrySnapshot.capture(LabelUpdateDiagnosticEntry entry)
    : key = entry.key,
      anchors = [
        entry.data.lat,
        entry.data.lon,
        entry.data.iconLat,
        entry.data.iconLon,
        entry.data.textOffsetX,
        entry.data.textOffsetY,
        entry.data.iconOffsetX,
        entry.data.iconOffsetY,
      ],
      positions = [
        entry.textPosition?.dx,
        entry.textPosition?.dy,
        entry.iconPosition?.dx,
        entry.iconPosition?.dy,
      ],
      groups = _captureGroups(entry);

  final String key;
  final List<Object?> anchors;
  final List<Object?> positions;
  final Map<_Reason, List<Object?>> groups;
}

Map<_Reason, List<Object?>> _captureGroups(LabelUpdateDiagnosticEntry entry) {
  final data = entry.data;

  return {
    _Reason.membership: [data.crossTileId, data.tileWrap, data.layer],
    _Reason.parts: [
      data.textPlaced,
      data.iconPlaced,
      entry.textPosition != null,
      entry.iconPosition != null,
    ],
    _Reason.order: [data.layerIndex, data.renderGroup, data.renderOrder],
    _Reason.fade: [entry.visible, entry.fadeIn],
    _Reason.style: [
      data.textR,
      data.textG,
      data.textB,
      data.textA,
      data.haloR,
      data.haloG,
      data.haloB,
      data.haloA,
      data.textOpacity,
      data.iconOpacity,
      data.iconR,
      data.iconG,
      data.iconB,
      data.iconA,
      data.iconHaloR,
      data.iconHaloG,
      data.iconHaloB,
      data.iconHaloA,
      data.textJustify,
      data.vertical,
      data.iconSdf,
      data.textPitchWithMap,
      data.textRotationWithMap,
      data.iconPitchWithMap,
      data.iconRotationWithMap,
      data.textKeepUpright,
      data.iconKeepUpright,
      data.alongLine,
      data.iconAlongLine,
    ],
    _Reason.content: [
      data.text,
      data.visualText,
      data.textDirection,
      data.icon,
      data.textFont,
      data.textFonts.length,
      ...data.textFonts,
      ..._sectionScalars(data.textSections),
      ..._sectionScalars(data.visualTextSections),
    ],
    _Reason.affine: [
      data.textTransform.xx,
      data.textTransform.xy,
      data.textTransform.yx,
      data.textTransform.yy,
      data.iconTransform.xx,
      data.iconTransform.xy,
      data.iconTransform.yx,
      data.iconTransform.yy,
      data.angle,
      data.iconAngle,
      data.textRotation,
      data.iconRotation,
      data.textTranslateX,
      data.textTranslateY,
      data.iconTranslateX,
      data.iconTranslateY,
    ],
    _Reason.size: [
      data.fontSize,
      data.textW,
      data.textH,
      data.iconW,
      data.iconH,
      data.iconScale,
      data.iconFitWidth,
      data.iconFitHeight,
      data.haloWidth,
      data.haloBlur,
      data.iconHaloWidth,
      data.iconHaloBlur,
      data.letterSpacing,
      data.lineHeight,
      data.maxWidth,
    ],
    _Reason.path: [
      data.textPath.length,
      for (final point in data.textPath) ...[point.x, point.y],
      data.iconPath.length,
      for (final point in data.iconPath) ...[point.x, point.y],
    ],
  };
}

Iterable<Object?> _sectionScalars(List<LabelTextSection> sections) sync* {
  yield sections.length;
  for (final section in sections) {
    yield section.start;
    yield section.end;
    yield section.fontScale;
    yield section.fonts.length;
    yield* section.fonts;
    final color = section.color;
    yield color != null;
    if (color != null) {
      yield color.a;
      yield color.r;
      yield color.g;
      yield color.b;
      yield color.colorSpace;
    }
    yield section.imageId;
  }
}

void _classify(
  Map<String, int> counts,
  String scope,
  List<_EntrySnapshot>? previous,
  List<_EntrySnapshot> current,
  bool atlasChanged,
) {
  void add(String name, [int amount = 1]) {
    final key = '$scope.$name';
    counts[key] = (counts[key] ?? 0) + amount;
  }

  void outcome(String name) {
    add(name);
    add('${name}Entries', current.length);
  }

  add('observed');
  if (previous == null) {
    outcome('baseline');

    return;
  }
  add('compared');
  final reasons = <_Reason>{if (atlasChanged) _Reason.atlas};
  final oldEntries = {for (final entry in previous) entry.key: entry};
  final newEntries = {for (final entry in current) entry.key: entry};
  if (oldEntries.length != previous.length ||
      newEntries.length != current.length ||
      !setEquals(oldEntries.keys.toSet(), newEntries.keys.toSet())) {
    reasons.add(_Reason.membership);
  }
  if (!listEquals(
    previous
        .where((entry) => newEntries.containsKey(entry.key))
        .map((e) => e.key)
        .toList(),
    current
        .where((entry) => oldEntries.containsKey(entry.key))
        .map((e) => e.key)
        .toList(),
  )) {
    reasons.add(_Reason.order);
  }
  var anchorChanged = false;
  var positionChanged = false;
  for (final entry in current) {
    final old = oldEntries[entry.key];
    if (old == null) continue;
    anchorChanged |= !_sameScalars(old.anchors, entry.anchors);
    positionChanged |= !_sameScalars(old.positions, entry.positions);
    for (final group in entry.groups.entries) {
      if (!_sameScalars(old.groups[group.key]!, group.value)) {
        reasons.add(group.key);
      }
    }
  }
  if (anchorChanged) add('nativeAnchorChanged');
  if (positionChanged) add('projectedPositionChanged');
  if (reasons.isNotEmpty) {
    outcome('rejected');
    for (final reason in reasons) {
      add('reason.${reason.name}');
    }
  } else if (anchorChanged) {
    outcome('nativeAnchorOnly');
  } else if (positionChanged) {
    outcome('projectedPositionOnly');
  } else {
    outcome('unchanged');
  }
}

bool _sameScalars(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final a = left[index];
    final b = right[index];
    if (a != b) return false;
    // Signed zero remains observable to custom symbol builders.
    if (a is double && b is double && a == 0 && a.isNegative != b.isNegative) {
      return false;
    }
  }
  return true;
}
