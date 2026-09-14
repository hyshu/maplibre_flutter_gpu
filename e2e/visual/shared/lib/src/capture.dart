part of '../visual_e2e_shared.dart';

final GlobalKey visualE2eRepaintBoundaryKey = GlobalKey(
  debugLabel: 'visual-e2e-repaint-boundary',
);

/// Identifies a PNG readback failure after Flutter produced a GPU image.
final class VisualE2eReadbackException implements Exception {
  /// Creates a readback failure that preserves the engine error.
  const new(this.cause);

  /// Error reported by `ui.Image.toByteData`.
  final Object cause;

  /// Whether Flutter reported the transient empty Impeller command status.
  bool get isTransientImpellerFailure =>
      cause is Exception && cause.toString().trim() == 'Exception:';

  @override
  String toString() => 'VISUAL_E2E_PNG_READBACK_FAILED: $cause';
}

/// Callback invoked before another PNG readback attempt.
typedef VisualE2eReadbackRetry = Future<void> Function(
  int failedAttempt,
  VisualE2eReadbackException error,
  StackTrace stackTrace,
);

/// Captures the visual viewport at the requested pixel ratio.
///
/// Only Flutter's empty transient Impeller readback error is retried. A retry
/// creates a fresh image from the repaint boundary. All other failures retain
/// their original stack trace.
Future<Uint8List> captureVisualE2ePng({
  double? pixelRatio,
  int readbackAttempts = 1,
  VisualE2eReadbackRetry? beforeReadbackRetry,
}) async {
  if (readbackAttempts < 1) {
    throw ArgumentError.value(
      readbackAttempts,
      'readbackAttempts',
      'must be at least one',
    );
  }
  final boundary =
      visualE2eRepaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('visual E2E repaint boundary is not mounted');
  }
  final ratio =
      pixelRatio ??
      WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

  for (var attempt = 1; attempt <= readbackAttempts; attempt += 1) {
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      try {
        final data = await image.toByteData(format: .png);
        if (data == null) {
          throw const VisualE2eReadbackException(
            'PNG encoding returned no data',
          );
        }

        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } on VisualE2eReadbackException {
        rethrow;
      } catch (error, stackTrace) {
        Error.throwWithStackTrace(
          VisualE2eReadbackException(error),
          stackTrace,
        );
      }
    } on VisualE2eReadbackException catch (error, stackTrace) {
      if (!error.isTransientImpellerFailure || attempt == readbackAttempts) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      await beforeReadbackRetry?.call(attempt, error, stackTrace);
    } finally {
      image.dispose();
    }
  }

  throw StateError('visual E2E PNG readback exhausted unexpectedly');
}
