import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Keeps a composed map image independent of its live render targets.
class MapRenderFreezeController extends ChangeNotifier {
  _RenderMapFreeze? _surface;
  var _paused = false;
  var _disposed = false;
  var _notificationPending = false;
  var _revealPending = false;
  var _generation = 0;

  /// Whether the live subtree is frozen and its tickers are muted.
  bool get isPaused => _paused;

  /// Captures the last painted layers without painting pending changes.
  void pause(double pixelRatio) {
    if (_disposed || _paused) return;
    _surface?.freeze(pixelRatio);
    _paused = true;
    _generation++;
    _notifySafely();
  }

  /// Allows live painting while retaining the image until [reveal] is called.
  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    _generation++;
    _surface?.resume();
    _notifySafely();
  }

  /// Reveals a completed replacement frame without replaying frozen changes.
  void reveal() {
    if (_disposed || _paused) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_revealPending) return;
      _revealPending = true;
      final generation = _generation;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _revealPending = false;
        if (!_disposed && !_paused && generation == _generation) {
          _surface?.reveal();
        }
      });

      return;
    }
    _surface?.reveal();
  }

  void _notifySafely() {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notifyListeners();

      return;
    }
    if (_notificationPending) return;
    _notificationPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notificationPending = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _surface?._clearImage();
    _surface = null;
    super.dispose();
  }
}

/// Retains child state while replacing its painted output with a frozen image.
class MapRenderFreeze extends StatelessWidget {
  const MapRenderFreeze({
    super.key,
    required this.controller,
    required this.child,
  });

  final MapRenderFreezeController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    child: _MapFreezeSurface(controller: controller, child: child),
    builder: (context, child) =>
        TickerMode(enabled: !controller.isPaused, child: child!),
  );
}

class _MapFreezeSurface extends SingleChildRenderObjectWidget {
  const _MapFreezeSurface({required this.controller, required super.child});

  final MapRenderFreezeController controller;

  @override
  _RenderMapFreeze createRenderObject(BuildContext context) =>
      _RenderMapFreeze(controller);

  @override
  void updateRenderObject(BuildContext context, _RenderMapFreeze renderObject) {
    renderObject.controller = controller;
  }
}

class _RenderMapFreeze extends RenderProxyBox {
  _RenderMapFreeze(MapRenderFreezeController controller) {
    this.controller = controller;
  }

  MapRenderFreezeController? _controller;
  ui.Image? _image;
  final _replacementLayer = LayerHandle<OpacityLayer>();
  var _paused = false;
  var _paintedSize = Size.zero;
  var _painting = false;

  set controller(MapRenderFreezeController value) {
    if (identical(_controller, value)) return;
    _controller?._surface = null;
    _controller = value;
    value._surface = this;
    _paused = value.isPaused;
  }

  @override
  bool get isRepaintBoundary => true;

  void freeze(double pixelRatio) {
    if (_paused) return;
    if (_painting) {
      throw StateError(
        'Cannot freeze a map while its layers are being painted',
      );
    }
    final paintedLayer = layer;
    if (_image == null &&
        paintedLayer is OffsetLayer &&
        !_paintedSize.isEmpty) {
      // The layer still contains the last completed paint even when a new
      // layout or paint has already been requested.
      _image = paintedLayer.toImageSync(
        Offset.zero & _paintedSize,
        pixelRatio: pixelRatio,
      );
    }
    _paused = true;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void reveal() {
    if (_paused || _image == null) return;
    _clearImage();
    markNeedsPaint();
  }

  void _clearImage() {
    final image = _image;
    _image = null;
    _replacementLayer.layer = null;
    if (image == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => image.dispose());
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_paused) {
      _painting = true;
      try {
        if (_image == null) {
          super.paint(context, offset);
        } else {
          // Replacement painting must run to report frame completion while
          // only the retained image contributes to the visible composition.
          _replacementLayer.layer = context.pushOpacity(
            offset,
            0,
            super.paint,
            oldLayer: _replacementLayer.layer,
          );
        }
        _paintedSize = size;
      } finally {
        _painting = false;
      }
    }
    final image = _image;
    if (image != null) {
      paintImage(
        canvas: context.canvas,
        rect: offset & size,
        image: image,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.low,
      );
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !_paused && super.hitTest(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_paused) super.visitChildrenForSemantics(visitor);
  }

  @override
  void dispose() {
    _clearImage();
    if (identical(_controller?._surface, this)) _controller?._surface = null;
    super.dispose();
  }
}
