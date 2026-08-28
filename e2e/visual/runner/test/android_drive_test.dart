import 'package:test/test.dart';
import 'package:visual_e2e_runner/src/android_drive.dart';

void main() {
  test('source mode compiles the selected scene during flutter drive', () {
    final arguments = buildAndroidDriveArguments(
      device: 'emulator-5554',
      sceneId: 'geometry',
      zoom: 13,
    );

    expect(arguments, contains('--dart-define=VISUAL_E2E_SCENE=geometry'));
    expect(arguments, contains('--dart-define=VISUAL_E2E_ZOOM=13.0'));
    expect(
      arguments.where(
        (argument) => argument.startsWith('--use-application-binary='),
      ),
      isEmpty,
    );
  });

  test('prebuilt mode installs the APK without compiling on the emulator', () {
    final arguments = buildAndroidDriveArguments(
      device: 'emulator-5554',
      sceneId: 'geometry',
      applicationBinary: '/tmp/maplibre-gl.apk',
    );

    expect(
      arguments,
      contains('--use-application-binary=/tmp/maplibre-gl.apk'),
    );
    expect(
      arguments.where((argument) => argument.startsWith('--dart-define=')),
      isEmpty,
    );
    expect(
      arguments,
      containsAll([
        '--driver=test_driver/integration_test.dart',
        '--target=integration_test/visual_test.dart',
        '--device-id=emulator-5554',
        '--no-pub',
        '--no-dds',
      ]),
    );
  });
}
