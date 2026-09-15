part of 'maplibre_map_controller.dart';

/// Owns the callbacks and active lifetime of a borrowed native bridge.
abstract class _ControllerBinding extends ChangeNotifier {
  new(
    this._bridge, {
    this._onCameraChangeRequested,
    this._onStyleChangeRequested,
    this._beforeStyleMutation,
    this._onStyleMutationRequested,
    this._placedLabelsProvider,
  });

  final MaplibreBridge _bridge;
  VoidCallback? _onCameraChangeRequested;
  Future<void> Function(String styleString, String resolvedStyle)?
  _onStyleChangeRequested;
  Future<void> Function()? _beforeStyleMutation;
  VoidCallback? _onStyleMutationRequested;
  List<LabelData> Function()? _placedLabelsProvider;
  var _disposed = false;

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('MapLibreMapController used after dispose');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onCameraChangeRequested = null;
    _onStyleChangeRequested = null;
    _beforeStyleMutation = null;
    _onStyleMutationRequested = null;
    _placedLabelsProvider = null;
    super.dispose();
  }
}
