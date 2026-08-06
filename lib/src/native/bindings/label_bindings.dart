part of '../maplibre_ffi.dart';

/// Reads the symbol placements MapLibre resolved for the last frame.
///
/// Native placements are decoded for the Flutter text and icon overlay.
/// When label export is unavailable, the version is zero
/// and the placement list is empty.
mixin MaplibreBridgeLabelBindings {
  BridgeSessionLifecycle get _lifecycle;

  // The bridge resolves these optional native callbacks together.
  Int32VoidD? _getLabelCount;
  Pointer<Void> Function()? _getLabels;
  Int32VoidD? _getLabelStride;
  int Function()? _getLabelsVersion;

  /// Returns the version of the latest native placement snapshot.
  ///
  /// The version changes when native publishes a new snapshot. Returns zero
  /// when label export is unavailable.
  int getLabelsVersion() {
    _lifecycle.ensureActive();

    return _getLabelsVersion?.call() ?? 0;
  }

  /// Returns the text and icon placements from the latest native snapshot.
  ///
  /// Returns an empty list when no valid snapshot is available. The returned
  /// [LabelData] objects do not retain the native placement buffer.
  List<LabelData> getPlacedLabels() {
    _lifecycle.ensureActive();
    final count = _getLabelCount?.call() ?? 0;
    if (count <= 0) return const [];
    final ptr = _getLabels?.call() ?? nullptr;
    if (ptr == nullptr) return const [];
    final stride = _getLabelStride?.call() ?? 0;
    if (stride != LabelExportAbi.size) {
      debugPrint(
        '[MaplibreBridge] LabelExport stride mismatch: '
        '$stride != ${LabelExportAbi.size}',
      );

      return const [];
    }
    return decodeLabelExports(
      bytes: ptr.cast<Uint8>().asTypedList(count * stride),
      count: count,
      stride: stride,
    );
  }
}
