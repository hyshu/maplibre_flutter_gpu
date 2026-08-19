import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

void main() {
  test('parses runtime scene routes used by platform launchers', () {
    expect(visualE2eSceneIdFromRoute('/visual-e2e/geometry'), 'geometry');
    expect(
      visualE2eSceneIdFromRoute('/visual-e2e?scene=text-symbol'),
      'text-symbol',
    );
    expect(visualE2eSceneIdFromRoute('mvt'), 'mvt');
    expect(visualE2eSceneIdFromRoute('/'), isNull);
    expect(visualE2eSceneIdFromRoute('/visual-e2e/unknown'), isNull);
  });

  test('parses a unique ordered scene suite', () {
    expect(parseVisualE2eSceneIds('geometry, text-symbol,mvt'), <String>[
      'geometry',
      'text-symbol',
      'mvt',
    ]);
    expect(
      () => parseVisualE2eSceneIds('geometry,geometry'),
      throwsArgumentError,
    );
    expect(() => parseVisualE2eSceneIds('geometry,,mvt'), throwsArgumentError);
    expect(() => parseVisualE2eSceneIds('unknown'), throwsArgumentError);
  });

  test('supported suites retain every intended scene', () {
    expect(visualE2eParitySceneIds, hasLength(18));
    expect(visualE2eDesktopSceneIds, hasLength(20));
    expect(visualE2eStrictDesktopSceneIds, hasLength(5));
    expect(
      visualE2eDesktopSceneIds.toSet(),
      containsAll(visualE2eStrictDesktopSceneIds),
    );
    expect(
      visualE2eParitySceneIds,
      containsAll(const <String>[
        'symbol-data-driven-paint',
        'symbol-paint-update',
        'symbol-line-pitch',
        'symbol-icon-effects',
        'symbol-layer-order',
        'symbol-z-order',
        'symbol-text-shaping',
      ]),
    );
  });

  test('only empty Impeller readback errors are transient', () {
    expect(
      VisualE2eReadbackException(Exception('')).isTransientImpellerFailure,
      isTrue,
    );
    expect(
      VisualE2eReadbackException(
        Exception('Failed to allocate destination buffer.'),
      ).isTransientImpellerFailure,
      isFalse,
    );
    expect(
      const VisualE2eReadbackException('PNG encoding returned no data')
          .isTransientImpellerFailure,
      isFalse,
    );
  });

  test('routes each requested font stack to its matching glyph fixture', () {
    expect(
      visualE2eGlyphAssetPath('/glyphs/NotoCJK/19968-20223.pbf'),
      'packages/visual_e2e_shared/assets/resources/glyphs/NotoCJK/'
      '19968-20223.pbf',
    );
    expect(
      visualE2eGlyphAssetPath(
        '/glyphs/Noto%20Sans%20Regular,Noto%20Sans%20Hebrew%20Regular/'
        '1280-1535.pbf',
      ),
      'packages/visual_e2e_shared/assets/resources/glyphs/NotoSansHebrew/'
      '1280-1535.pbf',
    );
    expect(visualE2eGlyphAssetPath('/glyphs/NotoCJK/not-a-range.pbf'), isNull);
  });

  test('routes both sprite sources to the deterministic fixture', () {
    expect(
      visualE2eSpriteAssetPath('/sprite.json'),
      'packages/visual_e2e_shared/assets/resources/sprite.json',
    );
    expect(
      visualE2eSpriteAssetPath('/sprite-alt@2x.png'),
      'packages/visual_e2e_shared/assets/resources/sprite.png',
    );
    expect(visualE2eSpriteAssetPath('/unknown.png'), isNull);
  });

  test('PNG capture requires at least one readback attempt', () async {
    await expectLater(
      captureVisualE2ePng(readbackAttempts: 0),
      throwsArgumentError,
    );
  });

  test('performance probe reports median frame timings', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final probe = VisualE2ePerformanceProbe();
    final metrics = await probe.measure(() async {
      binding.platformDispatcher.onReportTimings?.call(<ui.FrameTiming>[
        _frameTiming(buildMicros: 1000, rasterMicros: 4000),
        _frameTiming(buildMicros: 2000, rasterMicros: 5000),
        _frameTiming(buildMicros: 3000, rasterMicros: 6000),
      ]);
    });

    expect(metrics['flutter_frame_count'], 3);
    expect(metrics['p50_flutter_build_time_millis'], 2);
    expect(metrics['p50_flutter_raster_time_millis'], 5);
  });

  test('ignores idle callbacks from an earlier app generation', () async {
    addTearDown(() {
      VisualTestStatus.reset();
    });
    final staleGeneration = VisualTestStatus.reset();
    VisualTestStatus.mapIdle(
      implementation: 'stale',
      sceneId: 'geometry',
      generation: staleGeneration,
    );
    final activeGeneration = VisualTestStatus.reset();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(VisualTestStatus.ready.value, isFalse);

    VisualTestStatus.mapIdle(
      implementation: 'active',
      sceneId: 'text-symbol',
      generation: activeGeneration,
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(VisualTestStatus.ready.value, isTrue);
  });
}

ui.FrameTiming _frameTiming({
  required int buildMicros,
  required int rasterMicros,
}) {
  return ui.FrameTiming(
    vsyncStart: 0,
    buildStart: 0,
    buildFinish: buildMicros,
    rasterStart: buildMicros,
    rasterFinish: buildMicros + rasterMicros,
    rasterFinishWallTime: buildMicros + rasterMicros,
  );
}
