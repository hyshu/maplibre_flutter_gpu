part of '../renderer.dart';

typedef _PreparedFrameKey = ({
  int frameSequence,
  int commandsAddress,
  int commandCount,
  int commandStride,
  int physicalWidth,
  int physicalHeight,
  double logicalWidth,
  double logicalHeight,
  double devicePixelRatio,
});

final class _PreparedDrawPartition {
  final List<DrawEntry> entries = [];
  GpuStyleLayerRange range = (minimumLayerIndex: null, maximumLayerIndex: null);
  bool needsMainDepthStencil = false;
}

final class _PreparedGraphState {
  new(this.graph);

  final PreparedGraph<DrawEntry, _PreparedDrawPartition> graph;
  List<GpuStyleLayerRange> layerRanges = const [];
}

/// Per-frame bindings that replay one persistent decoded GPU graph.
///
/// The graph survives native frame generations while its structural command
/// topology remains unchanged. Uniforms and frame-owned resources are refreshed
/// before this value is created.
final class GpuPreparedFrame {
  new _({
    required this._key,
    required this._graphState,
    required this.binder,
    required this.uniformData,
    required this.shouldLog,
    required this.uboMicros,
  });

  final _PreparedFrameKey _key;
  final _PreparedGraphState _graphState;
  List<GpuStyleLayerRange> get layerRanges => _graphState.layerRanges;
  final FrameBinder? binder;
  final ByteData uniformData;
  int get commandCount => _graphState.graph.commandCount;
  int? get lastFillExtrusionLayerIndex =>
      _graphState.graph.lastFillExtrusionLayerIndex;
  bool shouldLog;
  final int uboMicros;
  int drawCount = 0;
  int renderPassCount = 0;

  /// Whether [stratumIndex] contains at least one admitted native command.
  bool hasCommandsInStratum(int stratumIndex) =>
      stratumIndex >= 0 &&
      stratumIndex < layerRanges.length &&
      _graphState.graph.partitions[stratumIndex].entries.isNotEmpty;
}
