import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('multiple scenes run in separate scene-specific processes', () async {
    final harness = await _MacOsCliHarness.create();
    addTearDown(harness.dispose);

    final result = await harness.run(<String>[
      '--scenes',
      'geometry,text-symbol',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final testCalls = harness.flutterCalls.where(
      (arguments) => arguments.firstOrNull == 'test',
    );
    expect(testCalls, hasLength(2));
    for (final arguments in testCalls) {
      expect(
        arguments.where(
          (argument) => argument.startsWith('--dart-define=VISUAL_E2E_SCENES='),
        ),
        isEmpty,
      );
      expect(_plainName(arguments), isNull);
    }
    expect(testCalls.map(_sceneDefine), <String?>['geometry', 'text-symbol']);

    final attemptLog = File(
      '${harness.output.path}/logs/maplibre_flutter_gpu-test-attempt-1.log',
    ).readAsStringSync();
    final finalLog = File(
      '${harness.output.path}/logs/maplibre_flutter_gpu-test.log',
    ).readAsStringSync();
    for (final scene in <String>['geometry', 'text-symbol']) {
      expect(attemptLog, contains('flutter-test scene=$scene attempt=1'));
      expect(finalLog, contains('flutter-test scene=$scene attempt=1'));
    }
  });

  test('a non-idle failure is not retried and stops later scenes', () async {
    final harness = await _MacOsCliHarness.create(
      environment: const <String, String>{
        'FAKE_FLUTTER_FAIL_SCENE': 'geometry',
        'FAKE_FLUTTER_FAIL_COUNT': '1',
        'FAKE_FLUTTER_FAIL_KIND': 'other',
      },
    );
    addTearDown(harness.dispose);

    final result = await harness.run(<String>[
      '--scenes',
      'geometry,text-symbol',
      '--idle-retries',
      '3',
    ]);

    expect(result.exitCode, 23);
    expect(result.stderr, contains('reason other than the idle timeout'));
    final testCalls = harness.flutterCalls
        .where((arguments) => arguments.firstOrNull == 'test')
        .toList();
    expect(testCalls, hasLength(1));
    expect(_sceneDefine(testCalls.single), 'geometry');
  });

  test('a single scene keeps the existing define and log contract', () async {
    final harness = await _MacOsCliHarness.create();
    addTearDown(harness.dispose);

    final result = await harness.run(<String>['--scene', 'geometry']);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final testCall = harness.flutterCalls.singleWhere(
      (arguments) => arguments.firstOrNull == 'test',
    );
    expect(testCall, contains('--dart-define=VISUAL_E2E_SCENE=geometry'));
    expect(
      testCall.where(
        (argument) => argument.startsWith('--dart-define=VISUAL_E2E_SCENES='),
      ),
      isEmpty,
    );
    expect(_plainName(testCall), isNull);
    expect(
      File(
        '${harness.output.path}/geometry/logs/'
        'maplibre_flutter_gpu-test-attempt-1.log',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${harness.output.path}/geometry/logs/'
        'maplibre_flutter_gpu-test.log',
      ).readAsStringSync(),
      contains('flutter-test scene=geometry attempt=1'),
    );
  });

  test('an idle retry removes stale captures and preserves logs', () async {
    final harness = await _MacOsCliHarness.create(
      environment: const <String, String>{
        'FAKE_FLUTTER_FAIL_SCENE': 'geometry',
        'FAKE_FLUTTER_FAIL_COUNT': '1',
        'FAKE_FLUTTER_FAIL_KIND': 'idle',
        'FAKE_FLUTTER_REQUIRE_CLEAN_RETRY': '1',
      },
    );
    addTearDown(harness.dispose);

    final result = await harness.run(<String>[
      '--scene',
      'geometry',
      '--idle-retries',
      '1',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final logs = Directory('${harness.output.path}/geometry/logs');
    expect(
      File(
        '${logs.path}/maplibre_flutter_gpu-test-attempt-1.log',
      ).readAsStringSync(),
      contains('did not become idle'),
    );
    final successfulAttempt = File(
      '${logs.path}/maplibre_flutter_gpu-test-attempt-2.log',
    ).readAsStringSync();
    expect(
      successfulAttempt,
      contains('flutter-test scene=geometry attempt=2'),
    );
    final finalLog = File(
      '${logs.path}/maplibre_flutter_gpu-test.log',
    ).readAsStringSync();
    expect(finalLog, contains('flutter-test scene=geometry attempt=2'));
    expect(finalLog, isNot(contains('did not become idle')));
  });
}

String? _plainName(List<String> arguments) {
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument.startsWith('--plain-name=')) {
      return argument.substring('--plain-name='.length);
    }
    if (argument == '--plain-name' && index + 1 < arguments.length) {
      return arguments[index + 1];
    }
  }

  return null;
}

String? _sceneDefine(List<String> arguments) {
  const prefix = '--dart-define=VISUAL_E2E_SCENE=';
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) {
      return argument.substring(prefix.length);
    }
  }

  return null;
}

final class _MacOsCliHarness {
  _MacOsCliHarness._({
    required this.temporary,
    required this.output,
    required this.flutterLog,
    required this.environment,
  });

  final Directory temporary;
  final Directory output;
  final File flutterLog;
  final Map<String, String> environment;

  static Future<_MacOsCliHarness> create({
    Map<String, String> environment = const <String, String>{},
  }) async {
    final temporary = await Directory.systemTemp.createTemp(
      'run-macos-cli-test.',
    );
    final bin = Directory('${temporary.path}/bin');
    final output = Directory('${temporary.path}/output');
    final state = Directory('${temporary.path}/state');
    final temp = Directory('${temporary.path}/tmp');
    await Future.wait(<Future<void>>[
      bin.create(),
      output.create(),
      state.create(),
      temp.create(),
    ]);
    final flutterLog = File('${temporary.path}/flutter.log');
    final flutter = File('${bin.path}/flutter');
    final dart = File('${bin.path}/dart');
    final sleep = File('${bin.path}/sleep');
    await flutter.writeAsString(_fakeFlutter);
    await dart.writeAsString('#!/usr/bin/env bash\nexit 0\n');
    await sleep.writeAsString('#!/usr/bin/env bash\nexit 0\n');
    final chmod = await Process.run('/bin/chmod', <String>[
      '755',
      flutter.path,
      dart.path,
      sleep.path,
    ]);
    if (chmod.exitCode != 0) {
      await temporary.delete(recursive: true);
      throw ProcessException('/bin/chmod', const <String>[], '${chmod.stderr}');
    }

    return _MacOsCliHarness._(
      temporary: temporary,
      output: output,
      flutterLog: flutterLog,
      environment: <String, String>{
        ...Platform.environment,
        'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
        'TMPDIR': temp.path,
        'FAKE_FLUTTER_LOG': flutterLog.path,
        'FAKE_FLUTTER_STATE': state.path,
        ...environment,
      },
    );
  }

  List<List<String>> get flutterCalls {
    if (!flutterLog.existsSync()) {
      return const <List<String>>[];
    }
    final tokens = utf8
        .decode(flutterLog.readAsBytesSync())
        .split(String.fromCharCode(0));
    final calls = <List<String>>[];
    List<String>? current;
    for (final token in tokens) {
      if (token == 'CALL') {
        current = <String>[];
      } else if (token == 'END') {
        if (current != null) {
          calls.add(current);
        }
        current = null;
      } else if (current != null) {
        current.add(token);
      }
    }

    return calls;
  }

  Future<ProcessResult> run(List<String> arguments) {
    return Process.run(
      '/bin/bash',
      <String>[
        '${_repositoryRoot.path}/e2e/visual/run_macos.sh',
        '--output',
        output.path,
        ...arguments,
      ],
      workingDirectory: _repositoryRoot.path,
      environment: environment,
    );
  }

  Future<void> dispose() => temporary.delete(recursive: true);
}

Directory get _repositoryRoot {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}/e2e/visual/run_macos.sh').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not find the repository root.');
    }
    directory = parent;
  }
}

const _fakeFlutter = r'''#!/usr/bin/env bash
set -euo pipefail

{
  printf 'CALL\0'
  for argument in "$@"; do
    printf '%s\0' "$argument"
  done
  printf 'END\0'
} >>"$FAKE_FLUTTER_LOG"

if [[ "${1:-}" == "pub" && "${2:-}" == "get" ]]; then
  exit 0
fi

scene=""
test_name=""
screenshot_dir=""
read_plain_name=0
for argument in "$@"; do
  if [[ "$read_plain_name" -eq 1 ]]; then
    test_name="$argument"
    read_plain_name=0
    continue
  fi
  case "$argument" in
    --plain-name=*) test_name="${argument#--plain-name=}" ;;
    --plain-name) read_plain_name=1 ;;
    --dart-define=VISUAL_E2E_SCENE=*)
      scene="${argument#--dart-define=VISUAL_E2E_SCENE=}"
      ;;
    --dart-define=VISUAL_E2E_SCREENSHOT_DIR=*)
      screenshot_dir="${argument#--dart-define=VISUAL_E2E_SCREENSHOT_DIR=}"
      ;;
  esac
done
if [[ -n "$test_name" ]]; then
  scene="${test_name#capture maplibre_flutter_gpu }"
  scene="${scene% scene}"
fi
if [[ -z "$scene" || -z "$screenshot_dir" ]]; then
  echo "fake flutter could not resolve the scene or screenshot directory" >&2
  exit 64
fi

counter="$FAKE_FLUTTER_STATE/$scene.count"
attempt=1
if [[ -f "$counter" ]]; then
  attempt=$(( $(<"$counter") + 1 ))
fi
printf '%s' "$attempt" >"$counter"
echo "flutter-test scene=$scene attempt=$attempt"

mkdir -p "$screenshot_dir"
screenshot="$screenshot_dir/$scene.png"
coverage="$screenshot_dir/$scene.coverage.json"
if [[ "$scene" == "${FAKE_FLUTTER_FAIL_SCENE:-}" && \
      "$attempt" -le "${FAKE_FLUTTER_FAIL_COUNT:-0}" ]]; then
  printf 'stale' >"$screenshot"
  printf 'stale' >"$coverage"
  if [[ "${FAKE_FLUTTER_FAIL_KIND:-other}" == "idle" ]]; then
    echo "maplibre_flutter_gpu did not become idle within 60 seconds"
  else
    echo "synthetic compiler failure"
  fi
  exit 23
fi

if [[ "$attempt" -gt 1 && \
      "${FAKE_FLUTTER_REQUIRE_CLEAN_RETRY:-0}" == "1" && \
      ( -e "$screenshot" || -e "$coverage" ) ]]; then
  echo "stale capture remained before retry" >&2
  exit 29
fi
printf 'fresh' >"$screenshot"
printf '{}' >"$coverage"
''';
