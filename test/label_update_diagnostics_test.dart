import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/labels/label_data.dart';
import 'package:maplibre_flutter_gpu/src/labels/label_source.dart';
import 'package:maplibre_flutter_gpu/src/labels/label_update_diagnostics.dart';
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart'
    hide LabelData;
import 'package:maplibre_flutter_gpu/src/sprites/sprite_atlas.dart';

LabelData _label({
  int id = 42,
  double lat = 35,
  double offset = 0,
  int layer = 1,
  int order = 0,
  double opacity = 1,
  double size = 16,
  double translation = 0,
  LabelAffineTransform transform = const LabelAffineTransform(),
  List<String> fonts = const [],
  List<LabelTextSection> sections = const [],
  List<LabelTextSection> visualSections = const [],
  List<LabelPathPoint> textPath = const [],
  List<LabelPathPoint> iconPath = const [],
}) => LabelData(
  crossTileId: id,
  lat: lat,
  lon: 139,
  textOffsetX: offset,
  fontSize: size,
  textR: 0,
  textG: 0,
  textB: 0,
  textA: 1,
  haloR: 0,
  haloG: 0,
  haloB: 0,
  haloA: 0,
  haloWidth: 0,
  textOpacity: opacity,
  textTranslateX: translation,
  textTransform: transform,
  textFonts: fonts,
  textSections: sections,
  visualTextSections: visualSections,
  textPath: textPath,
  iconPath: iconPath,
  text: 'Place',
  layer: 'places-$layer',
  layerIndex: layer,
  renderOrder: order,
);

LabelUpdateDiagnosticEntry _entry(
  LabelData data, {
  String key = 'place',
  Offset? position = const Offset(40, 50),
  bool visible = true,
  bool fadeIn = false,
}) => LabelUpdateDiagnosticEntry(
  key: key,
  data: data,
  visible: visible,
  fadeIn: fadeIn,
  textPosition: position,
  iconPosition: null,
);

Map<String, int> _compare(
  LabelUpdateDiagnosticEntry before,
  LabelUpdateDiagnosticEntry after, {
  bool atlasChanged = false,
}) {
  final diagnostic = LabelUpdateDiagnostics();
  diagnostic.record([before], nativeVersion: 0, atlasChanged: false);

  return diagnostic.record(
    [after],
    nativeVersion: 0,
    atlasChanged: atlasChanged,
  );
}

void _expectPartition(Map<String, int> result, String scope) {
  final baseline = result['$scope.baseline'] ?? 0;
  final compared = [
    'unchanged',
    'projectedPositionOnly',
    'nativeAnchorOnly',
    'rejected',
  ].fold(0, (sum, category) => sum + (result['$scope.$category'] ?? 0));
  expect(result['$scope.observed'], baseline + compared);
  expect(result['$scope.compared'] ?? 0, compared);
}

class _Bridge implements MaplibreBridge {
  _Bridge(this.label);

  LabelData label;
  int version = 0;
  Offset offset = Offset.zero;

  @override
  int getLabelsVersion() => version;

  @override
  List<LabelData> getPlacedLabels() => [label];

  @override
  List<Offset> wrappedLatLonsToScreen(
    List<({double latitude, double longitude, int tileWrap})> coordinates,
  ) => [
    for (final coordinate in coordinates)
      Offset(coordinate.longitude, coordinate.latitude) + offset,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _Atlas implements SpriteAtlas {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

void main() {
  test(
    'separates unchanged, projected movement, and native anchor changes',
    () {
      final before = _entry(_label());
      expect(_compare(before, _entry(_label()))['frames.unchanged'], 1);
      final projected = _compare(
        before,
        _entry(_label(), position: const Offset(140, 50)),
      );
      expect(projected['frames.projectedPositionOnly'], 1);
      expect(projected['frames.nativeAnchorChanged'], isNull);
      final native = _compare(
        before,
        _entry(_label(lat: 36, offset: 3), position: const Offset(43, 51)),
      );
      expect(native['frames.nativeAnchorOnly'], 1);
      expect(native['frames.projectedPositionChanged'], 1);
      _expectPartition(native, 'frames');
      _expectPartition(native, 'layers');
    },
  );

  test('rejects visual changes even when a component is absent', () {
    final before = _entry(_label());
    final cases = <String, LabelData>{
      'style': _label(opacity: .5),
      'size': _label(size: 18),
      'affine': _label(translation: 2),
      'content': _label(fonts: ['Another font']),
      'path': _label(iconPath: [const LabelPathPoint(1, 2)]),
      'order': _label(order: 1),
    };
    for (final change in cases.entries) {
      final result = _compare(before, _entry(change.value));
      expect(result['frames.rejected'], 1, reason: change.key);
      expect(result['frames.reason.${change.key}'], 1);
      expect(result['frames.nativeAnchorOnly'], isNull);
    }
    final affine = _compare(
      before,
      _entry(_label(transform: const LabelAffineTransform(xy: .2))),
    );
    expect(affine['frames.reason.affine'], 1);
  });

  test('rejects atlas, fade, and projected anchor availability changes', () {
    final before = _entry(_label());
    expect(
      _compare(before, before, atlasChanged: true)['frames.reason.atlas'],
      1,
    );
    expect(
      _compare(before, _entry(_label(), visible: false))['frames.reason.fade'],
      1,
    );
    expect(
      _compare(before, _entry(_label(), fadeIn: true))['frames.reason.fade'],
      1,
    );
    final missing = _compare(before, _entry(_label(), position: null));
    expect(missing['frames.reason.parts'], 1);
    expect(missing['frames.rejected'], 1);
  });

  test('captures caller-mutable nested content and paths by value', () {
    final fonts = ['First'];
    final sectionFonts = ['Section'];
    final sections = [LabelTextSection(start: 0, end: 5, fonts: sectionFonts)];
    final visual = [const LabelTextSection(start: 0, end: 5)];
    final path = [const LabelPathPoint(0, 0), const LabelPathPoint(10, 0)];
    final data = _label(
      fonts: fonts,
      sections: sections,
      visualSections: visual,
      textPath: path,
    );
    final diagnostic = LabelUpdateDiagnostics();
    diagnostic.record([_entry(data)], nativeVersion: 0, atlasChanged: false);
    fonts[0] = 'Second';
    sectionFonts[0] = 'Changed section';
    visual[0] = const LabelTextSection(start: 0, end: 4, imageId: 'image');
    path[1] = const LabelPathPoint(10, 3);
    final result = diagnostic.record(
      [_entry(data)],
      nativeVersion: 0,
      atlasChanged: false,
    );
    expect(result['frames.reason.content'], 1);
    expect(result['frames.reason.path'], 1);
    expect(result['frames.rejected'], 1);
    _expectPartition(result, 'frames');
  });

  test('uses exact custom-observable scalars, including signed zero', () {
    final result = _compare(
      _entry(_label(translation: 0.0)),
      _entry(_label(translation: -0.0)),
    );
    expect(result['frames.reason.affine'], 1);
    final section = _compare(
      _entry(_label(sections: [const LabelTextSection(start: 0, end: 5)])),
      _entry(
        _label(
          sections: [const LabelTextSection(start: 0, end: 5, fontScale: 1.01)],
        ),
      ),
    );
    expect(section['frames.reason.content'], 1);
  });

  test('reports whole-frame rejection and independent layer opportunities', () {
    final diagnostic = LabelUpdateDiagnostics();
    diagnostic.record(
      [_entry(_label(), key: 'one'), _entry(_label(layer: 2), key: 'two')],
      nativeVersion: 0,
      atlasChanged: false,
    );
    final result = diagnostic.record(
      [
        _entry(_label(lat: 36), key: 'one'),
        _entry(_label(layer: 2, opacity: .5), key: 'two'),
      ],
      nativeVersion: 0,
      atlasChanged: false,
    );
    expect(result['frames.rejected'], 1);
    expect(result['layers.nativeAnchorOnly'], 1);
    expect(result['layers.rejected'], 1);
    expect(result['layers.observed'], 2);
    expect(result['frames.rejectedEntries'], 2);
    expect(result['layers.nativeAnchorOnlyEntries'], 1);
    expect(result['layers.rejectedEntries'], 1);
    _expectPartition(result, 'frames');
    _expectPartition(result, 'layers');
    final removed = diagnostic.record(
      [],
      nativeVersion: 0,
      atlasChanged: false,
    );
    expect(removed['layers.observed'], 2);
    expect(removed['layers.reason.membership'], 2);
    expect(removed['layers.rejectedEntries'], 0);
    _expectPartition(removed, 'layers');
  });

  test('detects stable-key reordering and rejects duplicate identities', () {
    final diagnostic = LabelUpdateDiagnostics();
    final one = _entry(_label(), key: 'one');
    final two = _entry(_label(), key: 'two');
    diagnostic.record([one, two], nativeVersion: 0, atlasChanged: false);
    final reordered = diagnostic.record(
      [two, one],
      nativeVersion: 0,
      atlasChanged: false,
    );
    expect(reordered['frames.reason.order'], 1);
    expect(reordered['frames.reason.membership'], isNull);
    final duplicate = diagnostic.record(
      [one, one],
      nativeVersion: 0,
      atlasChanged: false,
    );
    expect(duplicate['frames.reason.membership'], 1);
  });

  test('reset discards comparisons without resetting cumulative counters', () {
    final diagnostic = LabelUpdateDiagnostics();
    diagnostic.record(
      [_entry(_label())],
      nativeVersion: 0,
      atlasChanged: false,
    );
    final before = LabelUpdateDiagnostics.snapshot();
    diagnostic.reset();
    final result = diagnostic.record(
      [_entry(_label(lat: 36))],
      nativeVersion: 0,
      atlasChanged: false,
    );
    final after = LabelUpdateDiagnostics.snapshot();
    expect(result['frames.baseline'], 1);
    expect(result['frames.compared'], isNull);
    expect(after['resets']! - before['resets']!, 1);
    expect(after['frames.observed']! - before['frames.observed']!, 1);
    expect(
      after['comparisonMicros'],
      greaterThanOrEqualTo(before['comparisonMicros']!),
    );
  });

  test(
    'isolates changed native versions from existing position-only updates',
    () {
      final diagnostic = LabelUpdateDiagnostics();
      diagnostic.record(
        [_entry(_label())],
        nativeVersion: 10,
        atlasChanged: false,
      );
      final moved = _entry(_label(), position: const Offset(80, 50));
      final sameVersion = diagnostic.record(
        [moved],
        nativeVersion: 10,
        atlasChanged: false,
      );
      expect(sameVersion['frames.projectedPositionOnly'], 1);
      expect(
        sameVersion.keys.where((key) => key.startsWith('nativeChanged.')),
        isEmpty,
      );
      final published = diagnostic.record(
        [_entry(_label(), position: const Offset(80, 50))],
        nativeVersion: 11,
        atlasChanged: false,
      );
      expect(published['nativeChanged.frames.compared'], 1);
      expect(published['nativeChanged.frames.unchanged'], 1);
      expect(published['nativeChanged.layers.unchangedEntries'], 1);
      _expectPartition(published, 'nativeChanged.frames');
      _expectPartition(published, 'nativeChanged.layers');
      diagnostic.reset();
      final reset = diagnostic.record(
        [moved],
        nativeVersion: 12,
        atlasChanged: false,
      );
      expect(reset['frames.baseline'], 1);
      expect(
        reset.keys.where((key) => key.startsWith('nativeChanged.')),
        isEmpty,
      );
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('projection capture honors flag and $platform gate', () {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const flag = bool.fromEnvironment('MAPLIBRE_LABEL_UPDATE_DIAGNOSTICS');
      final expected = flag && platform == TargetPlatform.android;
      expect(LabelUpdateDiagnostics.enabled, expected);
      final before = LabelUpdateDiagnostics.snapshot();
      final bridge = _Bridge(_label());
      final source = MapLabelSource()..syncFromNative(bridge);
      source.cacheScreenPositions(bridge, null);
      source.cacheScreenPositions(bridge, null);
      bridge.offset = const Offset(10, 0);
      source.cacheScreenPositions(bridge, null);
      source.cacheScreenPositions(bridge, _Atlas());
      source.reset();
      final after = LabelUpdateDiagnostics.snapshot();
      expect(
        after['frames.observed']! - before['frames.observed']!,
        expected ? 4 : 0,
      );
      expect(
        after['frames.reason.fade']! - before['frames.reason.fade']!,
        expected ? 1 : 0,
      );
      expect(
        after['frames.projectedPositionOnly']! -
            before['frames.projectedPositionOnly']!,
        expected ? 1 : 0,
      );
      expect(
        after['frames.reason.atlas']! - before['frames.reason.atlas']!,
        expected ? 1 : 0,
      );
    });
  }

  test(
    'reconciled invalid cross-tile IDs cannot reuse a later native snapshot',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final before = LabelUpdateDiagnostics.snapshot();
      final bridge = _Bridge(_label(id: 0));
      final source = MapLabelSource()..syncFromNative(bridge);
      source.cacheScreenPositions(bridge, null);
      bridge.version++;
      source.syncFromNative(bridge);
      source.cacheScreenPositions(bridge, null);
      final after = LabelUpdateDiagnostics.snapshot();
      expect(
        after['frames.reason.membership']! -
            before['frames.reason.membership']!,
        LabelUpdateDiagnostics.enabled ? 1 : 0,
      );
      expect(
        after['frames.nativeAnchorOnly']! - before['frames.nativeAnchorOnly']!,
        0,
      );
      expect(
        after['nativeChanged.frames.compared']! -
            before['nativeChanged.frames.compared']!,
        LabelUpdateDiagnostics.enabled ? 1 : 0,
      );
    },
  );
}
