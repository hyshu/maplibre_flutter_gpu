part of '../maplibre_ffi.dart';

/// Reads the symbol placements MapLibre resolved for the last frame.
///
/// Native placements are decoded for the Flutter text and icon overlay.
/// When label export is unavailable, the version is zero
/// and the placement list is empty.
mixin MaplibreBridgeLabelBindings {
  BridgeSessionLifecycle get _lifecycle;
  NativeSymbolTable get _symbols;

  // The bridge resolves these optional native callbacks together.
  Int32VoidD? _getLabelCount;
  Pointer<Void> Function()? _getLabels;
  Int32VoidD? _getLabelStride;
  Pointer<Void> Function()? _getLabelBlob;
  Int32VoidD? _getLabelBlobSize;
  int Function()? _getLabelsVersion;

  Int32VoidD? _getLabelStaticCount;
  Pointer<Void> Function()? _getLabelStaticRecords;
  Int32VoidD? _getLabelStaticStride;
  Pointer<Void> Function()? _getLabelStaticBlob;
  Int32VoidD? _getLabelStaticBlobSize;
  int Function()? _getLabelStaticVersion;
  int Function()? _getLabelStaticContentVersion;
  Int32VoidD? _getLabelDynamicCount;
  Pointer<Void> Function()? _getLabelDynamicRecords;
  Int32VoidD? _getLabelDynamicStride;
  Pointer<Void> Function()? _getLabelDynamicBlob;
  Int32VoidD? _getLabelDynamicBlobSize;
  int Function()? _getLabelDynamicVersion;

  var _cachedLabelStaticVersion = -1;
  var _cachedLabelStaticContentVersion = -1;
  var _cachedLabelStatics = const <DecodedLabelStatic>[];

  /// Returns the version of the latest native placement snapshot.
  ///
  /// The version changes when native publishes a new snapshot. Returns zero
  /// when label export is unavailable.
  int getLabelsVersion() {
    _lifecycle.ensureActive();
    if (_symbols.provides('split label placement export')) {
      final staticVersion = _getLabelStaticVersion!.call();
      final dynamicVersion = _getLabelDynamicVersion!.call();

      return (staticVersion << 32) | dynamicVersion;
    }

    return _getLabelsVersion?.call() ?? 0;
  }

  /// Returns the text and icon placements from the latest native snapshot.
  ///
  /// Returns an empty list when no valid snapshot is available. The returned
  /// [LabelData] objects do not retain the native placement buffer.
  List<LabelData> getPlacedLabels() {
    _lifecycle.ensureActive();
    if (_symbols.provides('split label placement export')) {
      final labels = _tryGetSplitPlacedLabels();
      if (labels != null) return labels;
    }

    return _getLegacyPlacedLabels();
  }

  List<LabelData> _getLegacyPlacedLabels() {
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
    final blobSize = _getLabelBlobSize?.call() ?? 0;
    final blobPtr = _getLabelBlob?.call() ?? nullptr;
    if (blobSize < 0 || (blobSize > 0 && blobPtr == nullptr)) return const [];
    return decodeLabelExports(
      bytes: ptr.cast<Uint8>().asTypedList(count * stride),
      blob: blobSize == 0
          ? Uint8List(0)
          : blobPtr.cast<Uint8>().asTypedList(blobSize),
      count: count,
      stride: stride,
    );
  }

  List<LabelData>? _tryGetSplitPlacedLabels() {
    final staticVersion = _getLabelStaticVersion!.call();
    if (_cachedLabelStaticVersion != staticVersion) {
      final contentVersion = _getLabelStaticContentVersion!.call();
      final count = _getLabelStaticCount!.call();
      if (count < 0) return null;
      List<DecodedLabelStatic> nextStatics;
      if (count == 0) {
        nextStatics = const [];
      } else {
        final ptr = _getLabelStaticRecords!.call();
        final stride = _getLabelStaticStride!.call();
        if (ptr == nullptr || stride != LabelStaticExportAbi.size) {
          return null;
        }
        final bytes = ptr.cast<Uint8>().asTypedList(count * stride);
        if (_cachedLabelStaticContentVersion == contentVersion &&
            _cachedLabelStatics.length == count) {
          nextStatics = decodeLabelStaticScalarExports(
            bytes: bytes,
            count: count,
            stride: stride,
            previous: _cachedLabelStatics,
          );
        } else {
          final blobSize = _getLabelStaticBlobSize!.call();
          final blobPtr = _getLabelStaticBlob!.call();
          if (blobSize < 0 || (blobSize > 0 && blobPtr == nullptr)) {
            return null;
          }
          nextStatics = decodeLabelStaticExports(
            bytes: bytes,
            blob: blobSize == 0
                ? Uint8List(0)
                : blobPtr.cast<Uint8>().asTypedList(blobSize),
            count: count,
            stride: stride,
          );
        }
      }
      if (nextStatics.length != count) return null;
      _cachedLabelStatics = nextStatics;
      _cachedLabelStaticVersion = staticVersion;
      _cachedLabelStaticContentVersion = contentVersion;
    }

    final count = _getLabelDynamicCount!.call();
    if (count < 0) return null;
    if (count == 0) return const [];
    final ptr = _getLabelDynamicRecords!.call();
    final stride = _getLabelDynamicStride!.call();
    final blobSize = _getLabelDynamicBlobSize!.call();
    final blobPtr = _getLabelDynamicBlob!.call();
    if (ptr == nullptr ||
        stride != LabelDynamicExportAbi.size ||
        blobSize < 0 ||
        (blobSize > 0 && blobPtr == nullptr)) {
      return null;
    }

    final labels = decodeLabelDynamicExports(
      bytes: ptr.cast<Uint8>().asTypedList(count * stride),
      blob: blobSize == 0
          ? Uint8List(0)
          : blobPtr.cast<Uint8>().asTypedList(blobSize),
      count: count,
      stride: stride,
      staticLabels: _cachedLabelStatics,
    );
    if (labels.length != count) return null;

    return labels;
  }
}
