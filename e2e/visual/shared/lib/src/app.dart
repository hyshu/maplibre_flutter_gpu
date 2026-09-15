part of '../visual_e2e_shared.dart';

var _visualE2eProcessIdentityLogged = false;

class VisualTestStatus {
  new _();

  static final ValueNotifier<bool> ready = ValueNotifier(false);
  static Timer? _settleTimer;
  static var _generation = 0;

  static int reset() {
    _settleTimer?.cancel();
    _settleTimer = null;
    ready.value = false;

    return ++_generation;
  }

  static void mapIdle({
    required String implementation,
    required String sceneId,
    required int generation,
  }) {
    if (generation != _generation || ready.value) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 750), () {
      if (generation != _generation) return;
      _settleTimer = null;
      ready.value = true;
      debugPrint('$visualE2eReadyPrefix|$implementation|$sceneId');
    });
  }
}

Future<void> runVisualE2eApp({
  required String implementation,
  required VisualMapBuilder mapBuilder,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!_visualE2eProcessIdentityLogged) {
    _visualE2eProcessIdentityLogged = true;
    debugPrint(
      'VISUAL_E2E_PROCESS|$implementation|$visualE2eRunToken|$pid|'
      '${visualE2eSuiteSceneIds.join(',')}',
    );
  }
  await SystemChrome.setPreferredOrientations(const [.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      systemNavigationBarColor: Color(0x00000000),
    ),
  );

  final generation = VisualTestStatus.reset();
  final scene = await loadVisualScene();
  runApp(
    _VisualE2eApp(
      implementation: implementation,
      scene: scene,
      mapBuilder: mapBuilder,
      generation: generation,
    ),
  );
}

class _VisualE2eApp extends StatelessWidget {
  const new({
    required this.implementation,
    required this.scene,
    required this.mapBuilder,
    required this.generation,
  });

  final String implementation;
  final VisualScene scene;
  final VisualMapBuilder mapBuilder;
  final int generation;

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: scene.backgroundColor,
    debugShowCheckedModeBanner: false,
    initialRoute: '/',
    pageRouteBuilder: _buildPageRoute,
    home: ColoredBox(
      color: scene.backgroundColor,
      child: _VisualViewport(
        implementation: implementation,
        scene: scene,
        mapBuilder: mapBuilder,
        generation: generation,
      ),
    ),
  );
}

PageRoute<T> _buildPageRoute<T>(
  RouteSettings settings,
  WidgetBuilder builder,
) => PageRouteBuilder<T>(
  settings: settings,
  pageBuilder: (
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context),
);

class _VisualViewport extends StatelessWidget {
  const new({
    required this.implementation,
    required this.scene,
    required this.mapBuilder,
    required this.generation,
  });

  // Keep native ornaments outside the captured viewport without pushing the
  // z2 camera past the antimeridian. On iOS, maplibre_gl constrains the whole
  // visible screen to [-180, 180] when CameraTargetBounds is unbounded.
  static const _controlOverscan = 24.0;

  final String implementation;
  final VisualScene scene;
  final VisualMapBuilder mapBuilder;
  final int generation;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: VisualTestStatus.ready,
    builder: (BuildContext context, bool ready, Widget? child) => Semantics(
      container: true,
      label: ready
          ? '$visualE2eReadyPrefix|${scene.id}'
          : 'VISUAL_E2E_LOADING|${scene.id}',
      child: child,
    ),
    child: RepaintBoundary(
      key: visualE2eRepaintBoundaryKey,
      child: ClipRect(
        child: Stack(
          fit: .expand,
          clipBehavior: .hardEdge,
          children: [
            Positioned(
              left: -_controlOverscan,
              top: -_controlOverscan,
              right: -_controlOverscan,
              bottom: -_controlOverscan,
              child: mapBuilder(
                scene,
                () => VisualTestStatus.mapIdle(
                  implementation: implementation,
                  sceneId: scene.id,
                  generation: generation,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
