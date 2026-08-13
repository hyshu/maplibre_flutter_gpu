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
    expect(visualE2eParitySceneIds, hasLength(11));
    expect(visualE2eDesktopSceneIds, hasLength(20));
    expect(visualE2eStrictDesktopSceneIds, hasLength(5));
    expect(
      visualE2eDesktopSceneIds.toSet(),
      containsAll(visualE2eStrictDesktopSceneIds),
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

  test('PNG capture requires at least one readback attempt', () async {
    await expectLater(
      captureVisualE2ePng(readbackAttempts: 0),
      throwsArgumentError,
    );
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
