import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _ciScenes = [
  'geometry',
  'text-symbol',
  'symbol-data-driven-paint',
  'symbol-paint-update',
  'symbol-line-pitch',
  'symbol-icon-effects',
  'symbol-layer-order',
  'symbol-z-order',
  'symbol-text-shaping',
  '3d-buildings',
  'mvt',
  'tilejson-mvt',
  'image-source',
  'geojson-url',
  'raster-jpeg',
  'raster-webp',
  'raster-tms',
  'wmts',
];

void main() {
  test('all CI scenes run in one process for each fixture', () async {
    final harness = await _IosCliHarness.create(
      environment: const {'FAKE_FLUTTER_DELAY_SECONDS': '0.05'},
    );
    addTearDown(harness.dispose);

    final result = await harness.run(['--scenes', _ciScenes.join(',')]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final driveCalls = harness.driveCalls;
    expect(driveCalls, hasLength(2));
    expect(driveCalls.map(_fixture), [
      'maplibre_gl',
      'maplibre_flutter_gpu',
    ]);
    expect(driveCalls.map(_scenesDefine), everyElement(_ciScenes.join(',')));
    for (final arguments in driveCalls) {
      expect(
        arguments.where(
          (argument) => argument.startsWith('--dart-define=VISUAL_E2E_SCENE='),
        ),
        isEmpty,
      );
    }
    expect(harness.watchdogSleeps, isNotEmpty);
    expect(harness.watchdogSleeps, everyElement('${600 * _ciScenes.length}'));

    for (final scene in _ciScenes) {
      expect(
        File('${harness.output.path}/$scene/images/maplibre_gl.png')
            .readAsStringSync(),
        'maplibre_gl:$scene:1',
      );
      expect(
        File('${harness.output.path}/$scene/images/gpu.png').readAsStringSync(),
        'maplibre_flutter_gpu:$scene:1',
      );
    }
  });

  test('a successful drive stops the watchdog sleep child', () async {
    final harness = await _IosCliHarness.create(
      environment: const {'FAKE_FLUTTER_DELAY_SECONDS': '0.05'},
    );
    addTearDown(harness.dispose);

    final result = await harness.run(['--scene', 'geometry']);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(harness.watchdogSleeps, isNotEmpty);
    expect(harness.watchdogSleeps, everyElement('600'));
    expect(harness.watchdogPids, isNotEmpty);
    for (final pid in harness.watchdogPids) {
      expect(
        await _waitForProcessExit(pid),
        isTrue,
        reason: 'A successful drive must stop watchdog process $pid.',
      );
    }
    expect(_simctlOperations(harness.xcrunCalls), isNot(contains('shutdown')));
    expect(
      _simctlOperations(harness.xcrunCalls).where((value) => value == 'boot'),
      hasLength(1),
    );
    expect(
      harness.xcrunCalls
          .where((call) => call.first == 'simctl' || call.first == 'open')
          .take(4)
          .map((call) {
            if (call.first == 'simctl') {
              return call[1];
            }

            return call.first;
          }),
      ['boot', 'open', 'bootstatus', 'status_bar'],
    );
  });

  test('rejects a stale app that reports a different run token', () async {
    final harness = await _IosCliHarness.create(
      environment: const {
        'FAKE_FLUTTER_PROCESS_TOKEN': 'stale-build',
      },
    );
    addTearDown(harness.dispose);

    final result = await harness.run(['--scene', 'geometry']);

    expect(result.exitCode, 65);
    expect(result.stderr, contains('expected one fresh process marker'));
    expect(harness.driveCalls, hasLength(1));
    expect(_fixture(harness.driveCalls.single), 'maplibre_gl');
  });

  test('an idle failure retries that fixture batch', () async {
    final harness = await _IosCliHarness.create(
      environment: const {
        'FAKE_FLUTTER_FAIL_FIXTURE': 'maplibre_gl',
        'FAKE_FLUTTER_FAIL_SCENE': 'geometry',
        'FAKE_FLUTTER_FAIL_COUNT': '1',
        'FAKE_FLUTTER_FAIL_KIND': 'idle',
      },
    );
    addTearDown(harness.dispose);

    final result = await harness.run([
      '--scenes',
      'geometry,text-symbol',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      harness.driveCalls.map(
        (call) => '${_fixture(call)}:${_scenesDefine(call)}',
      ),
      [
        'maplibre_gl:geometry,text-symbol',
        'maplibre_gl:geometry,text-symbol',
        'maplibre_flutter_gpu:geometry,text-symbol',
      ],
    );
    expect(result.stderr, contains('retrying scenes geometry,text-symbol'));
    expect(
      File('${harness.output.path}/geometry/images/maplibre_gl.png')
          .readAsStringSync(),
      'maplibre_gl:geometry:2',
    );
    expect(
      File('${harness.output.path}/text-symbol/images/maplibre_gl.png')
          .readAsStringSync(),
      'maplibre_gl:text-symbol:2',
    );
    final driveLog = File('${harness.output.path}/logs/maplibre_gl-drive.log')
        .readAsStringSync();
    expect(driveLog, contains('did not become idle'));
    expect(driveLog, contains('flutter-drive maplibre_gl:geometry:2'));
    expect(_simctlOperations(harness.xcrunCalls), isNot(contains('shutdown')));
    expect(
      _simctlOperations(harness.xcrunCalls).where((value) => value == 'boot'),
      hasLength(1),
    );
  });

  test('a non-idle failure is not retried', () async {
    final harness = await _IosCliHarness.create(
      environment: const {
        'FAKE_FLUTTER_FAIL_FIXTURE': 'maplibre_gl',
        'FAKE_FLUTTER_FAIL_SCENE': 'geometry',
        'FAKE_FLUTTER_FAIL_COUNT': '1',
        'FAKE_FLUTTER_FAIL_KIND': 'other',
        'VISUAL_E2E_IOS_IDLE_RETRIES': '3',
      },
    );
    addTearDown(harness.dispose);

    final result = await harness.run([
      '--scenes',
      'geometry,text-symbol',
    ]);

    expect(result.exitCode, 23);
    expect(result.stderr, contains('reason other than the idle timeout'));
    expect(harness.driveCalls, hasLength(1));
    expect(_fixture(harness.driveCalls.single), 'maplibre_gl');
    expect(_scenesDefine(harness.driveCalls.single), 'geometry,text-symbol');
  });

  test(
    'a drive timeout retries that fixture batch after a cold restart',
    () async {
      final harness = await _IosCliHarness.create(
        environment: const {
          'FAKE_FLUTTER_FAIL_FIXTURE': 'maplibre_gl',
          'FAKE_FLUTTER_FAIL_SCENE': 'geometry',
          'FAKE_FLUTTER_FAIL_COUNT': '1',
          'FAKE_FLUTTER_FAIL_KIND': 'timeout',
          'VISUAL_E2E_IOS_DRIVE_TIMEOUT_SECONDS': '1',
          'VISUAL_E2E_IOS_DRIVE_RETRIES': '1',
        },
      );
      addTearDown(harness.dispose);

      final result = await harness.run([
        '--scenes',
        'geometry,text-symbol',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        harness.driveCalls.map(
          (call) => '${_fixture(call)}:${_scenesDefine(call)}',
        ),
        [
          'maplibre_gl:geometry,text-symbol',
          'maplibre_gl:geometry,text-symbol',
          'maplibre_flutter_gpu:geometry,text-symbol',
        ],
      );
      expect(
        result.stderr,
        contains('retrying scenes geometry,text-symbol after timeout'),
      );

      final simctlCalls = harness.xcrunCalls
          .where((call) => call.length >= 2 && call.first == 'simctl')
          .toList();
      final retryCleanupStart = simctlCalls.indexWhere(
        (call) =>
            call[1] == 'terminate' &&
            call.last == 'dev.maplibre.fluttergpu.e2e.visualE2eMaplibreGl',
      );
      expect(retryCleanupStart, isNonNegative);
      expect(
        simctlCalls
            .sublist(retryCleanupStart, retryCleanupStart + 2)
            .map((call) => call[1]),
        ['terminate', 'uninstall'],
      );
      expect(
        _simctlOperations(harness.xcrunCalls)
            .where((value) => value == 'shutdown'),
        hasLength(1),
      );
      expect(
        _simctlOperations(harness.xcrunCalls).where((value) => value == 'boot'),
        hasLength(2),
      );
      expect(
        File(
          '${harness.output.path}/logs/'
          'maplibre_gl-geometry-attempt-1.log',
        ).readAsStringSync(),
        contains('synthetic hung drive'),
      );
      expect(
        File(
          '${harness.output.path}/logs/'
          'maplibre_gl-geometry-attempt-2.log',
        ).readAsStringSync(),
        contains('flutter-drive maplibre_gl:geometry:2'),
      );
    },
  );

  test('repeated drive timeouts cold-restart before the final retry', () async {
    final harness = await _IosCliHarness.create(
      environment: const {
        'FAKE_FLUTTER_FAIL_FIXTURE': 'maplibre_gl',
        'FAKE_FLUTTER_FAIL_SCENE': 'geometry',
        'FAKE_FLUTTER_FAIL_COUNT': '2',
        'FAKE_FLUTTER_FAIL_KIND': 'timeout',
        'VISUAL_E2E_IOS_DRIVE_TIMEOUT_SECONDS': '1',
      },
    );
    addTearDown(harness.dispose);

    final result = await harness.run(['--scene', 'geometry']);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(harness.driveCalls, hasLength(4));
    expect(
      harness.driveCalls
          .take(3)
          .map((call) => '${_fixture(call)}:${_sceneDefine(call)}'),
      everyElement('maplibre_gl:geometry'),
    );
    final operations = _simctlOperations(harness.xcrunCalls).toList();
    expect(
      operations,
      containsAllInOrder([
        'terminate',
        'uninstall',
        'terminate',
        'uninstall',
        'shutdown',
        'boot',
        'bootstatus',
        'status_bar',
      ]),
    );
    expect(operations.where((value) => value == 'shutdown'), hasLength(2));
    expect(operations.where((value) => value == 'boot'), hasLength(3));
  });

  test('a final drive timeout does not reboot the simulator', () async {
    final harness = await _IosCliHarness.create(
      environment: const {
        'FAKE_FLUTTER_FAIL_FIXTURE': 'maplibre_gl',
        'FAKE_FLUTTER_FAIL_SCENE': 'geometry',
        'FAKE_FLUTTER_FAIL_COUNT': '1',
        'FAKE_FLUTTER_FAIL_KIND': 'timeout',
        'VISUAL_E2E_IOS_DRIVE_TIMEOUT_SECONDS': '1',
        'VISUAL_E2E_IOS_DRIVE_RETRIES': '0',
      },
    );
    addTearDown(harness.dispose);

    final result = await harness.run(['--scene', 'geometry']);

    expect(result.exitCode, 124);
    expect(result.stderr, contains('timed out after 1 attempts'));
    expect(harness.driveCalls, hasLength(1));
    expect(_simctlOperations(harness.xcrunCalls), isNot(contains('shutdown')));
    expect(
      _simctlOperations(harness.xcrunCalls).where((value) => value == 'boot'),
      hasLength(1),
    );
    expect(
      File(
        '${harness.output.path}/logs/'
        'maplibre_gl-geometry-attempt-1.log',
      ).readAsStringSync(),
      contains('synthetic hung drive'),
    );
    expect(
      File(
        '${harness.output.path}/logs/'
        'maplibre_gl-geometry-attempt-2.log',
      ).existsSync(),
      isFalse,
    );
  });

  test(
    'a drive that ignores TERM is force-killed after the grace period',
    () async {
      final harness = await _IosCliHarness.create(
        environment: const {
          'FAKE_FLUTTER_FAIL_FIXTURE': 'maplibre_gl',
          'FAKE_FLUTTER_FAIL_SCENE': 'geometry',
          'FAKE_FLUTTER_FAIL_COUNT': '1',
          'FAKE_FLUTTER_FAIL_KIND': 'timeout',
          'FAKE_FLUTTER_IGNORE_TERM': 'true',
          'VISUAL_E2E_IOS_DRIVE_TIMEOUT_SECONDS': '1',
          'VISUAL_E2E_IOS_DRIVE_RETRIES': '0',
          'VISUAL_E2E_IOS_DRIVE_KILL_GRACE_SECONDS': '1',
        },
      );
      addTearDown(harness.dispose);

      final stopwatch = Stopwatch()..start();
      final result = await harness.run(['--scene', 'geometry']);
      stopwatch.stop();

      expect(result.exitCode, 124);
      expect(result.stderr, contains('timed out after 1 attempts'));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(harness.driveCalls, hasLength(1));
      final drivePid = int.parse(
        File('${harness.state.path}/maplibre_gl-geometry.drive.pid')
            .readAsStringSync(),
      );
      final childPid = int.parse(
        File('${harness.state.path}/maplibre_gl-geometry.child.pid')
            .readAsStringSync(),
      );
      expect(await _waitForProcessExit(drivePid), isTrue);
      expect(await _waitForProcessExit(childPid), isTrue);
      expect(
        File(
          '${harness.output.path}/logs/'
          'maplibre_gl-geometry-attempt-2.log',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('a TERM-resistant child is killed after its parent exits', () async {
    final harness = await _IosCliHarness.create(
      environment: const {
        'FAKE_FLUTTER_FAIL_FIXTURE': 'maplibre_gl',
        'FAKE_FLUTTER_FAIL_SCENE': 'geometry',
        'FAKE_FLUTTER_FAIL_COUNT': '1',
        'FAKE_FLUTTER_FAIL_KIND': 'timeout',
        'FAKE_FLUTTER_CHILD_IGNORE_TERM': 'true',
        'VISUAL_E2E_IOS_DRIVE_TIMEOUT_SECONDS': '1',
        'VISUAL_E2E_IOS_DRIVE_RETRIES': '0',
        'VISUAL_E2E_IOS_DRIVE_KILL_GRACE_SECONDS': '1',
      },
    );
    addTearDown(harness.dispose);

    final stopwatch = Stopwatch()..start();
    final result = await harness.run(['--scene', 'geometry']);
    stopwatch.stop();

    expect(result.exitCode, 124);
    expect(result.stderr, contains('timed out after 1 attempts'));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    final drivePid = int.parse(
      File('${harness.state.path}/maplibre_gl-geometry.drive.pid')
          .readAsStringSync(),
    );
    final childPid = int.parse(
      File('${harness.state.path}/maplibre_gl-geometry.child.pid')
          .readAsStringSync(),
    );
    expect(await _waitForProcessExit(drivePid), isTrue);
    expect(await _waitForProcessExit(childPid), isTrue);
  });

  test('a stuck simulator boot wait exits at its deadline', () async {
    final harness = await _IosCliHarness.create(
      environment: const {
        'FAKE_XCRUN_HANG_OPERATION': 'bootstatus',
        'VISUAL_E2E_IOS_SIMCTL_TIMEOUT_SECONDS': '1',
        'VISUAL_E2E_IOS_DRIVE_KILL_GRACE_SECONDS': '1',
      },
    );
    addTearDown(harness.dispose);

    final stopwatch = Stopwatch()..start();
    final result = await harness.run(['--scene', 'geometry']);
    stopwatch.stop();

    expect(result.exitCode, 124);
    expect(
      result.stderr,
      contains('Command timed out after 1s: xcrun simctl bootstatus'),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(harness.driveCalls, isEmpty);
  });

  test('a stuck simulator cleanup exits at its shorter deadline', () async {
    final harness = await _IosCliHarness.create(
      environment: const {
        'FAKE_FLUTTER_FAIL_FIXTURE': 'maplibre_gl',
        'FAKE_FLUTTER_FAIL_SCENE': 'geometry',
        'FAKE_FLUTTER_FAIL_COUNT': '1',
        'FAKE_FLUTTER_FAIL_KIND': 'other',
        'FAKE_XCRUN_HANG_OPERATION': 'terminate',
        'VISUAL_E2E_IOS_SIMCTL_CLEANUP_TIMEOUT_SECONDS': '1',
        'VISUAL_E2E_IOS_DRIVE_KILL_GRACE_SECONDS': '1',
      },
    );
    addTearDown(harness.dispose);

    final stopwatch = Stopwatch()..start();
    final result = await harness.run(['--scene', 'geometry']);
    stopwatch.stop();

    expect(result.exitCode, 124);
    expect(
      result.stderr,
      contains('Command timed out after 1s: xcrun simctl terminate'),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    expect(harness.driveCalls, isEmpty);
  });

  test(
    'single scene keeps zoom, performance, output, and log contracts',
    () async {
      final harness = await _IosCliHarness.create();
      addTearDown(harness.dispose);

      final result = await harness.run([
        '--scene',
        'flutter-markers',
        '--zoom',
        '13',
        '--performance',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(harness.driveCalls, hasLength(2));
      for (final arguments in harness.driveCalls) {
        expect(
          arguments,
          contains('--dart-define=VISUAL_E2E_SCENE=flutter-markers'),
        );
        expect(
          arguments.where(
            (argument) =>
                argument.startsWith('--dart-define=VISUAL_E2E_SCENES='),
          ),
          isEmpty,
        );
        expect(arguments, contains('--dart-define=VISUAL_E2E_ZOOM=13'));
        expect(
          arguments,
          contains('--dart-define=VISUAL_E2E_PERFORMANCE=true'),
        );
        expect(
          arguments,
          contains(
            '--dart-define=VISUAL_E2E_PERFORMANCE_ENVIRONMENT=iOS Simulator',
          ),
        );
      }
      expect(
        File('${harness.output.path}/images/maplibre_gl.png')
            .readAsStringSync(),
        'maplibre_gl:flutter-markers:1',
      );
      expect(
        File('${harness.output.path}/images/gpu.png').readAsStringSync(),
        'maplibre_flutter_gpu:flutter-markers:1',
      );
      expect(
        File('${harness.output.path}/performance/maplibre_gl.json')
            .existsSync(),
        isTrue,
      );
      expect(
        File('${harness.output.path}/performance/maplibre_flutter_gpu.json')
            .existsSync(),
        isTrue,
      );
      expect(
        File('${harness.output.path}/logs/maplibre_gl-drive.log').existsSync(),
        isTrue,
      );
      expect(
        File('${harness.output.path}/logs/maplibre_flutter_gpu-drive.log')
            .existsSync(),
        isTrue,
      );
    },
  );

  test('performance fixtures enable live frame scheduling conditionally', () {
    const guard = '''
  if (visualE2ePerformanceEnabled) {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  }
''';
    for (final path in [
      'e2e/visual/gpu_app/integration_test/visual_test.dart',
      'e2e/visual/maplibre_gl_app/integration_test/visual_test.dart',
    ]) {
      final source = File('${_repositoryRoot.path}/$path').readAsStringSync();

      expect(source, contains(guard), reason: path);
      expect(
        RegExp(r'binding\.framePolicy').allMatches(source),
        hasLength(1),
        reason: path,
      );
      expect(
        source.indexOf(guard),
        lessThan(source.indexOf('final sceneIds')),
        reason: path,
      );
    }
  });

  test('idle retry count must be a non-negative integer', () async {
    final harness = await _IosCliHarness.create(
      environment: const {'VISUAL_E2E_IOS_IDLE_RETRIES': '-1'},
    );
    addTearDown(harness.dispose);

    final result = await harness.run(const []);

    expect(result.exitCode, 2);
    expect(
      result.stderr,
      contains('VISUAL_E2E_IOS_IDLE_RETRIES must be a non-negative integer.'),
    );
    expect(harness.flutterCalls, isEmpty);
  });

  test('simulator cleanup timeout must be a positive integer', () async {
    final harness = await _IosCliHarness.create(
      environment: const {
        'VISUAL_E2E_IOS_SIMCTL_CLEANUP_TIMEOUT_SECONDS': '0',
      },
    );
    addTearDown(harness.dispose);

    final result = await harness.run(const []);

    expect(result.exitCode, 2);
    expect(
      result.stderr,
      contains(
        'VISUAL_E2E_IOS_SIMCTL_CLEANUP_TIMEOUT_SECONDS must be a positive '
        'integer.',
      ),
    );
    expect(harness.flutterCalls, isEmpty);
  });
}

String? _fixture(List<String> arguments) => _metadata(arguments, 'FIXTURE=');

String? _sceneDefine(List<String> arguments) {
  const prefix = '--dart-define=VISUAL_E2E_SCENE=';
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) {
      return argument.substring(prefix.length);
    }
  }

  return null;
}

String? _scenesDefine(List<String> arguments) {
  const prefix = '--dart-define=VISUAL_E2E_SCENES=';
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) {
      return argument.substring(prefix.length);
    }
  }

  return null;
}

Iterable<String> _simctlOperations(List<List<String>> calls) => calls
    .where((call) => call.length >= 2 && call.first == 'simctl')
    .map((call) => call[1]);

Future<bool> _waitForProcessExit(int pid) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    final result = await Process.run('/bin/kill', ['-0', '$pid']);
    if (result.exitCode != 0) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  return false;
}

String? _metadata(List<String> arguments, String prefix) {
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) {
      return argument.substring(prefix.length);
    }
  }

  return null;
}

final class _IosCliHarness {
  new _({
    required this.temporary,
    required this.output,
    required this.state,
    required this.flutterLog,
    required this.xcrunLog,
    required this.sleepLog,
    required this.watchdogPidLog,
    required this.environment,
  });

  final Directory temporary;
  final Directory output;
  final Directory state;
  final File flutterLog;
  final File xcrunLog;
  final File sleepLog;
  final File watchdogPidLog;
  final Map<String, String> environment;

  static Future<_IosCliHarness> create({
    Map<String, String> environment = const {},
  }) async {
    final temporary = await Directory.systemTemp.createTemp(
      'run-ios-cli-test.',
    );
    final bin = Directory('${temporary.path}/bin');
    final output = Directory('${temporary.path}/output');
    final state = Directory('${temporary.path}/state');
    final temp = Directory('${temporary.path}/tmp');
    await Future.wait([
      bin.create(),
      output.create(),
      state.create(),
      temp.create(),
    ]);
    final flutterLog = File('${temporary.path}/flutter.log');
    final xcrunLog = File('${temporary.path}/xcrun.log');
    final sleepLog = File('${temporary.path}/sleep.log');
    final watchdogPidLog = File('${temporary.path}/watchdog-pid.log');
    final flutter = File('${bin.path}/flutter');
    final xcrun = File('${bin.path}/xcrun');
    final open = File('${bin.path}/open');
    final dart = File('${bin.path}/dart');
    final sleep = File('${bin.path}/sleep');
    await flutter.writeAsString(_fakeFlutter);
    await xcrun.writeAsString(_fakeXcrun);
    await open.writeAsString(_fakeOpen);
    await dart.writeAsString('#!/usr/bin/env bash\nexit 0\n');
    await sleep.writeAsString(_fakeSleep);
    final chmod = await Process.run('/bin/chmod', [
      '755',
      flutter.path,
      xcrun.path,
      open.path,
      dart.path,
      sleep.path,
    ]);
    if (chmod.exitCode != 0) {
      await temporary.delete(recursive: true);
      throw ProcessException('/bin/chmod', const [], '${chmod.stderr}');
    }

    return ._(
      temporary: temporary,
      output: output,
      state: state,
      flutterLog: flutterLog,
      xcrunLog: xcrunLog,
      sleepLog: sleepLog,
      watchdogPidLog: watchdogPidLog,
      environment: {
        ...Platform.environment,
        'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
        'TMPDIR': temp.path,
        'FAKE_FLUTTER_LOG': flutterLog.path,
        'FAKE_FLUTTER_STATE': state.path,
        'FAKE_XCRUN_LOG': xcrunLog.path,
        'FAKE_SLEEP_LOG': sleepLog.path,
        'FAKE_WATCHDOG_LOG': sleepLog.path,
        'FAKE_WATCHDOG_PID_LOG': watchdogPidLog.path,
        ...environment,
      },
    );
  }

  List<List<String>> get flutterCalls => _calls(flutterLog);

  List<List<String>> get xcrunCalls => _calls(xcrunLog);

  List<List<String>> _calls(File log) {
    if (!log.existsSync()) {
      return const [];
    }
    final tokens = utf8
        .decode(log.readAsBytesSync())
        .split(String.fromCharCode(0));
    final calls = <List<String>>[];
    List<String>? current;
    for (final token in tokens) {
      if (token == 'CALL') {
        current = [];
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

  List<List<String>> get driveCalls => flutterCalls
      .where((arguments) => arguments.firstOrNull == 'drive')
      .toList();

  List<String> get watchdogSleeps {
    if (!sleepLog.existsSync()) {
      return const [];
    }

    return sleepLog.readAsLinesSync().where((line) => line.isNotEmpty).toList();
  }

  List<int> get watchdogPids {
    if (!watchdogPidLog.existsSync()) {
      return const [];
    }

    return watchdogPidLog
        .readAsLinesSync()
        .where((line) => line.isNotEmpty)
        .map(int.parse)
        .toList();
  }

  Future<ProcessResult> run(List<String> arguments) => Process.run(
    '/bin/bash',
    [
      '${_repositoryRoot.path}/e2e/visual/run_ios.sh',
      '--device',
      'FAKE-IOS-DEVICE',
      '--output',
      output.path,
      ...arguments,
    ],
    workingDirectory: _repositoryRoot.path,
    environment: environment,
  );

  Future<void> dispose() => temporary.delete(recursive: true);
}

Directory get _repositoryRoot {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}/e2e/visual/run_ios.sh').existsSync()) {
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

fixture=""
capture_name=""
case "$PWD" in
  */maplibre_gl_app)
    fixture="maplibre_gl"
    capture_name="maplibre_gl"
    ;;
  */gpu_app)
    fixture="maplibre_flutter_gpu"
    capture_name="gpu"
    ;;
esac

{
  printf 'CALL\0'
  for argument in "$@"; do
    printf '%s\0' "$argument"
  done
  printf 'FIXTURE=%s\0' "$fixture"
  printf 'SCREENSHOT_DIR=%s\0' "${VISUAL_E2E_SCREENSHOT_DIR:-}"
  printf 'PERFORMANCE_OUTPUT=%s\0' "${VISUAL_E2E_PERFORMANCE_OUTPUT:-}"
  printf 'END\0'
} >>"$FAKE_FLUTTER_LOG"

if [[ "${1:-}" == "pub" && "${2:-}" == "get" ]]; then
  exit 0
fi
if [[ "${1:-}" != "drive" ]]; then
  echo "unexpected fake flutter command" >&2
  exit 64
fi

watchdog_ready="$VISUAL_E2E_SCREENSHOT_DIR/watchdog-ready"
for _ in {1..200}; do
  [[ -f "$watchdog_ready" ]] && break
  /bin/sleep 0.01
done
if [[ ! -f "$watchdog_ready" ]]; then
  echo "fake flutter did not observe this drive watchdog" >&2
  exit 70
fi

for _ in {1..200}; do
  [[ -s "$FAKE_WATCHDOG_LOG" ]] && break
  /bin/sleep 0.01
done
if [[ ! -s "$FAKE_WATCHDOG_LOG" ]]; then
  echo "fake flutter did not observe the watchdog timer" >&2
  exit 70
fi

scene=""
scenes_option=""
run_token=""
for argument in "$@"; do
  case "$argument" in
    --dart-define=VISUAL_E2E_SCENE=*)
      scene="${argument#--dart-define=VISUAL_E2E_SCENE=}"
      ;;
    --dart-define=VISUAL_E2E_SCENES=*)
      scenes_option="${argument#--dart-define=VISUAL_E2E_SCENES=}"
      ;;
    --dart-define=VISUAL_E2E_RUN_TOKEN=*)
      run_token="${argument#--dart-define=VISUAL_E2E_RUN_TOKEN=}"
      ;;
  esac
done
if [[ -n "$scenes_option" ]]; then
  IFS=',' read -r -a scenes <<<"$scenes_option"
else
  scenes=("$scene")
fi
suite="$(IFS=,; echo "${scenes[*]}")"
if [[ -z "$fixture" || -z "$capture_name" || "${#scenes[@]}" -eq 0 || \
      -z "$run_token" || -z "${VISUAL_E2E_SCREENSHOT_DIR:-}" ]]; then
  echo "fake flutter could not resolve its fixture, scenes, or capture path" >&2
  exit 64
fi

if [[ -n "${FAKE_FLUTTER_DELAY_SECONDS:-}" ]]; then
  /bin/sleep "$FAKE_FLUTTER_DELAY_SECONDS"
fi

mkdir -p "$VISUAL_E2E_SCREENSHOT_DIR"
process_token="${FAKE_FLUTTER_PROCESS_TOKEN:-$run_token}"
process_suite="${FAKE_FLUTTER_PROCESS_SCENES:-$suite}"
echo "VISUAL_E2E_PROCESS|$fixture|$process_token|$$|$process_suite"
failed_scene=""
for scene in "${scenes[@]}"; do
  counter="$FAKE_FLUTTER_STATE/$fixture-$scene.count"
  attempt=1
  if [[ -f "$counter" ]]; then
    attempt=$(( $(<"$counter") + 1 ))
  fi
  printf '%s' "$attempt" >"$counter"
  echo "flutter-drive $fixture:$scene:$attempt"
  echo "VISUAL_E2E_READY|$fixture|$scene"
  printf '%s' "$$" >"$FAKE_FLUTTER_STATE/$fixture-$scene.drive.pid"

  screenshot="$VISUAL_E2E_SCREENSHOT_DIR/$capture_name.png"
  if [[ "${#scenes[@]}" -gt 1 ]]; then
    screenshot="$VISUAL_E2E_SCREENSHOT_DIR/$capture_name-$scene.png"
  fi
  printf '%s' "$fixture:$scene:$attempt" >"$screenshot"
  if [[ "$fixture" == "${FAKE_FLUTTER_FAIL_FIXTURE:-}" && \
        "$scene" == "${FAKE_FLUTTER_FAIL_SCENE:-}" && \
        "$attempt" -le "${FAKE_FLUTTER_FAIL_COUNT:-0}" ]]; then
    printf 'stale' >"$screenshot"
    failed_scene="$scene"
  fi
done

if [[ -n "$failed_scene" ]]; then
  case "${FAKE_FLUTTER_FAIL_KIND:-other}" in
    idle)
      echo "$fixture did not become idle within 60 seconds"
      ;;
    timeout)
      echo "synthetic hung drive"
      if [[ "${FAKE_FLUTTER_CHILD_IGNORE_TERM:-false}" == "true" ]]; then
        /bin/bash -c '
          trap "" TERM
          while true; do
            /bin/sleep 30
          done
        ' &
        child_pid=$!
        printf '%s' "$child_pid" \
          >"$FAKE_FLUTTER_STATE/$fixture-$failed_scene.child.pid"
        wait "$child_pid" || true
      elif [[ "${FAKE_FLUTTER_IGNORE_TERM:-false}" == "true" ]]; then
        trap '' TERM
        while true; do
          /bin/sleep 30 &
          child_pid=$!
          printf '%s' "$child_pid" \
            >"$FAKE_FLUTTER_STATE/$fixture-$failed_scene.child.pid"
          wait "$child_pid" || true
        done
      else
        /bin/sleep 30
      fi
      ;;
    *)
      echo "synthetic compiler failure"
      ;;
  esac
  exit 23
fi

if [[ -n "${VISUAL_E2E_PERFORMANCE_OUTPUT:-}" ]]; then
  mkdir -p "$(dirname "$VISUAL_E2E_PERFORMANCE_OUTPUT")"
  printf '{"fixture":"%s"}\n' "$fixture" >"$VISUAL_E2E_PERFORMANCE_OUTPUT"
fi
''';

const _fakeXcrun = r'''#!/usr/bin/env bash
set -euo pipefail

{
  printf 'CALL\0'
  for argument in "$@"; do
    printf '%s\0' "$argument"
  done
  printf 'END\0'
} >>"$FAKE_XCRUN_LOG"

if [[ "${FAKE_XCRUN_HANG_OPERATION:-}" == "${2:-}" ]]; then
  trap '' TERM
  while true; do
    /bin/sleep 30
  done
fi
''';

const _fakeOpen = r'''#!/usr/bin/env bash
set -euo pipefail

{
  printf 'CALL\0open\0'
  for argument in "$@"; do
    printf '%s\0' "$argument"
  done
  printf 'END\0'
} >>"$FAKE_XCRUN_LOG"
''';

const _fakeSleep = r'''#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$FAKE_SLEEP_LOG"
if [[ "${1:-}" =~ ^[0-9]+$ && "${1:-}" -ge 600 ]]; then
  printf '%s\n' "$$" >>"$FAKE_WATCHDOG_PID_LOG"
  exec /bin/sleep 4
fi
exec /bin/sleep "$@"
''';
