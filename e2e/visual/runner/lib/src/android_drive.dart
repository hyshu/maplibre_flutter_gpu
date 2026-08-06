List<String> buildAndroidDriveArguments({
  required String device,
  required String sceneId,
  double? zoom,
  String? applicationBinary,
}) {
  return <String>[
    'drive',
    '--driver=test_driver/integration_test.dart',
    '--target=integration_test/visual_test.dart',
    '--device-id=$device',
    if (applicationBinary == null) ...<String>[
      '--dart-define=VISUAL_E2E_SCENE=$sceneId',
      if (zoom != null) '--dart-define=VISUAL_E2E_ZOOM=$zoom',
    ] else
      '--use-application-binary=$applicationBinary',
    '--no-pub',
    '--no-dds',
  ];
}
