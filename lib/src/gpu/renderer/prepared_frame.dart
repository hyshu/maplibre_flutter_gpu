part of '../renderer.dart';

typedef _PreparedFrameKey = ({
  int frameSequence,
  int commandsAddress,
  int payloadAddress,
  int payloadSize,
  int commandCount,
  int commandStride,
  int physicalWidth,
  int physicalHeight,
  double logicalWidth,
  double logicalHeight,
  double devicePixelRatio,
});

final class _PreparedDrawPartition {
  final entries = <DrawEntry>[];
  GpuStyleLayerRange range = (minimumLayerIndex: null, maximumLayerIndex: null);
  var needsMainDepthStencil = false;
}

final class _PreparedGraphState {
  new(this.graph)
    : offscreenTopology = OffscreenPassTopology.capture(graph.entries);

  final PreparedGraph<DrawEntry, _PreparedDrawPartition> graph;
  final OffscreenPassTopology offscreenTopology;
  var layerRanges = const <GpuStyleLayerRange>[];
}

/// Per-frame bindings that replay one persistent decoded GPU graph.
///
/// The graph survives native frame generations while its structural command
/// topology remains unchanged. Uniforms and frame-owned resources are refreshed
/// before this value is created.
final class GpuPreparedFrame {
  /// Creates an empty frame without native memory or GPU resources.
  @visibleForTesting
  factory emptyForTesting({
    FrameClearColor? clearColor,
    MapLibreGpuMapTransform? mapTransform,
  }) => GpuPreparedFrame._(
    key: (
      frameSequence: 0,
      commandsAddress: 0,
      payloadAddress: 0,
      payloadSize: 0,
      commandCount: 0,
      commandStride: DrawCommandAbi.size,
      physicalWidth: 0,
      physicalHeight: 0,
      logicalWidth: 0,
      logicalHeight: 0,
      devicePixelRatio: 1,
    ),
    graphState: _PreparedGraphState(
      PreparedGraph(
        key: PreparedGraphKey.nonReusable(
          commandCount: 0,
          commandStride: DrawCommandAbi.size,
        ),
        entries: [],
        partitions: [],
        uniformAlignment: RendererUboAbi.minimumUniformByteAlignment,
        uniformCursor: 0,
        hasMapGlobalUniform: false,
        commandCount: 0,
        lastFillExtrusionLayerIndex: null,
      ),
    ),
    binder: null,
    uniformData: ByteData(0),
    clearColor: clearColor,
    mapTransform: mapTransform,
    shouldLog: false,
    uboMicros: 0,
  );

  new _({
    required this._key,
    required this._graphState,
    required this.binder,
    required this.uniformData,
    required this.clearColor,
    required this.mapTransform,
    required this.shouldLog,
    required this.uboMicros,
  });

  final _PreparedFrameKey _key;
  final _PreparedGraphState _graphState;
  late final _offscreenPlans = _graphState.offscreenTopology.plan(
    _graphState.graph.entries,
  );
  List<GpuStyleLayerRange> get layerRanges => _graphState.layerRanges;
  final FrameBinder? binder;
  final ByteData uniformData;

  /// The copied native clear color used when replaying without a snapshot.
  final FrameClearColor? clearColor;

  /// The copied camera transform for callbacks during retained frame replay.
  final MapLibreGpuMapTransform? mapTransform;
  int get commandCount => _graphState.graph.commandCount;
  int? get lastFillExtrusionLayerIndex =>
      _graphState.graph.lastFillExtrusionLayerIndex;
  bool shouldLog;
  final int uboMicros;
  var drawCount = 0;
  var renderPassCount = 0;

  /// Whether [stratumIndex] contains at least one admitted native command.
  bool hasCommandsInStratum(int stratumIndex) =>
      stratumIndex >= 0 &&
      stratumIndex < layerRanges.length &&
      _graphState.graph.partitions[stratumIndex].entries.isNotEmpty;
}
