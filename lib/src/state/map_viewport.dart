// Coalesces layout changes and derives the logical and physical map sizes.
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show BoxConstraints, Size;

/// A requested logical map size and device pixel ratio.
typedef ViewportRequest = ({Size logicalSize, double dpr});

/// Coalesces viewport requests and tracks the most recently applied value.
class MapViewportCoalescer {
  ViewportRequest? _applied;
  ViewportRequest? _pending;
  var _scheduled = false;

  /// The viewport currently in effect, or null before the first apply.
  ViewportRequest? get applied => _applied;

  /// Whether the caller has an outstanding apply callback.
  bool get isScheduled => _scheduled;

  /// Records [request] and returns whether an apply callback must be scheduled.
  ///
  /// A scheduled callback always consumes the latest non-redundant request.
  bool request(ViewportRequest request) {
    request = _normalizeViewportRequest(request);
    final pending = _pending;
    if (pending != null &&
        pending.logicalSize == request.logicalSize &&
        pending.dpr == request.dpr) {
      return false;
    }
    // An applied viewport is authoritative only when no request is pending.
    // Returning to it during a pending transition remains a real change.
    if (pending == null &&
        _applied?.logicalSize == request.logicalSize &&
        _applied?.dpr == request.dpr) {
      return false;
    }

    _pending = request;
    if (_scheduled) return false;
    _scheduled = true;

    return true;
  }

  /// Consumes the queued request, if any, at post-frame time.
  ///
  /// Clears the scheduled flag first so a request arriving during the apply
  /// queues a fresh callback rather than being swallowed.
  ViewportRequest? takePending() {
    _scheduled = false;
    final pending = _pending;
    _pending = null;

    return pending;
  }

  /// Records that [request] is now in effect.
  void markApplied(ViewportRequest request) =>
      _applied = _normalizeViewportRequest(request);

  /// Drops the queued request without applying it.
  void cancel() {
    _scheduled = false;
    _pending = null;
  }
}

/// Tracks map layout and its logical and physical render dimensions.
class MapViewport {
  final MapViewportCoalescer _coalescer = MapViewportCoalescer();

  var _physicalWidth = 1;
  var _physicalHeight = 1;
  var _logicalWidth = 0;
  var _logicalHeight = 0;
  var _devicePixelRatio = 1.0;
  var _initializationAdopted = false;
  var _reportedDprChange = false;

  /// Render-target width in device pixels.
  int get physicalWidth => _physicalWidth;

  /// Render-target height in device pixels.
  int get physicalHeight => _physicalHeight;

  /// Width handed to native in logical pixels.
  int get logicalWidth => _logicalWidth;

  /// Height handed to native in logical pixels.
  int get logicalHeight => _logicalHeight;

  /// Device pixel ratio adopted for the lifetime of this viewport.
  double get devicePixelRatio => _devicePixelRatio;

  /// The viewport currently in effect, or null before the first layout.
  ViewportRequest? get applied => _coalescer.applied;

  /// Current logical map size.
  Size get logicalSize =>
      Size(_logicalWidth.toDouble(), _logicalHeight.toDouble());

  /// Records a layout change.
  ///
  /// Returns whether the caller must schedule a post-frame apply.
  bool request(Size logicalSize, double dpr) =>
      _coalescer.request((logicalSize: logicalSize, dpr: dpr));

  /// Consumes the pending viewport request.
  ViewportRequest? takePending() => _coalescer.takePending();

  /// Drops the pending viewport request.
  void cancel() => _coalescer.cancel();

  /// Fixes the dimensions native will be initialized with.
  ///
  /// The first call fixes the device pixel ratio and dimensions. Later calls
  /// do nothing.
  void adoptForInitialization(Size logicalSize, double observedDpr) {
    if (_initializationAdopted) return;
    _initializationAdopted = true;
    _devicePixelRatio = _normalizeDevicePixelRatio(observedDpr);
    _setDimensions(logicalSize);
  }

  /// Applies a coalesced layout change, and reports whether the native render
  /// target must be resized.
  ///
  /// Before initialization the request is only recorded. After initialization
  /// the adopted device pixel ratio remains fixed across logical resizes.
  bool applyLayout(
    Size newLogicalSize,
    double observedDpr, {
    required bool initialized,
  }) {
    observedDpr = _normalizeDevicePixelRatio(observedDpr);
    final previous = _coalescer.applied;
    final sizeChanged = previous?.logicalSize != newLogicalSize;
    final dprChanged = previous?.dpr != observedDpr;
    _coalescer.markApplied((logicalSize: newLogicalSize, dpr: observedDpr));
    if (!initialized) return false;

    if (dprChanged &&
        (observedDpr - _devicePixelRatio).abs() > 0.000001 &&
        !_reportedDprChange) {
      _reportedDprChange = true;
      debugPrint(
        '[MapLibreMap] devicePixelRatio changed after initialization; '
        'keeping native DPR $_devicePixelRatio until the map is remounted',
      );
    }
    if (!sizeChanged) return false;

    return _setDimensions(newLogicalSize);
  }

  /// Updates derived dimensions and returns whether any extent changed.
  bool _setDimensions(Size newLogicalSize) {
    final dimensions = viewportDimensions(newLogicalSize, _devicePixelRatio);
    if (dimensions.logicalWidth == _logicalWidth &&
        dimensions.logicalHeight == _logicalHeight &&
        dimensions.physicalWidth == _physicalWidth &&
        dimensions.physicalHeight == _physicalHeight) {
      return false;
    }
    _logicalWidth = dimensions.logicalWidth;
    _logicalHeight = dimensions.logicalHeight;
    _physicalWidth = dimensions.physicalWidth;
    _physicalHeight = dimensions.physicalHeight;

    return true;
  }
}

/// The size to lay the map out at, or null when it cannot be rendered.
///
/// Unbounded, non-finite, and empty constraints do not define a viewport.
Size? mapLayoutSize(BoxConstraints constraints) {
  if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
    return null;
  }
  final size = constraints.biggest;
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    return null;
  }
  return size;
}

/// Splits a logical size into the logical and physical extents native needs.
///
/// Every returned extent is at least one pixel.
({int logicalWidth, int logicalHeight, int physicalWidth, int physicalHeight})
viewportDimensions(Size logicalSize, double devicePixelRatio) {
  final dpr = _normalizeDevicePixelRatio(devicePixelRatio);
  final logicalWidth = _normalizeLogicalExtent(logicalSize.width);
  final logicalHeight = _normalizeLogicalExtent(logicalSize.height);
  final physicalWidth = (logicalWidth * dpr).floor();
  final physicalHeight = (logicalHeight * dpr).floor();

  return (
    logicalWidth: logicalWidth,
    logicalHeight: logicalHeight,
    physicalWidth: physicalWidth > 0 ? physicalWidth : 1,
    physicalHeight: physicalHeight > 0 ? physicalHeight : 1,
  );
}

ViewportRequest _normalizeViewportRequest(ViewportRequest request) => (
  logicalSize: request.logicalSize,
  dpr: _normalizeDevicePixelRatio(request.dpr),
);

double _normalizeDevicePixelRatio(double value) =>
    value.isFinite && value > 0 ? value : 1.0;

int _normalizeLogicalExtent(double value) {
  if (!value.isFinite || value <= 0) return 1;
  final extent = value.floor();

  return extent > 0 ? extent : 1;
}
