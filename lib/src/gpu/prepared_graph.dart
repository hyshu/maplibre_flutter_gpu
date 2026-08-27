import 'dart:typed_data';

import '../frame/draw_command_admission.dart';
import '../frame/ubo_abi.dart';
import '../native/abi_generated.dart';

const int _topologyFingerprintMask = 0xffffffffffffffff;
const int _topologyFingerprintOffset = 0xcbf29ce484222325;
const int _topologyFingerprintPrime = 0x100000001b3;

int _mixTopologyFingerprint(int hash, int value) =>
    ((hash ^ (value & _topologyFingerprintMask)) * _topologyFingerprintPrime) &
    _topologyFingerprintMask;

/// The first stable-field difference that prevented prepared-graph reuse.
enum PreparedGraphTopologyMismatchReason {
  nonReusable,
  commandCount,
  commandStride,
  commandBytes,
  shader,
  drawMode,
  flags,
  layer,
  subLayer,
  stencil,
  admission,
  unknown,
}

/// Carries the active graph's mismatch through template-cache probing.
///
/// Template candidates also call [PreparedGraphKey.matches]. Their mismatches
/// are deliberately hidden by [PreparedGraphTemplateCache.takeMatching], so a
/// later full rebuild reports the active graph difference rather than the last
/// rejected template candidate.
final class PreparedGraphTopologyDiagnostics._() {
  static PreparedGraphTopologyMismatchReason? _pendingMismatch;

  static PreparedGraphTopologyMismatchReason? consumePendingMismatch() {
    final mismatch = _pendingMismatch;
    _pendingMismatch = null;
    return mismatch;
  }

  static void clearPendingMismatch() {
    _pendingMismatch = null;
  }
}

/// Structural state of one native command in a persistent preparation graph.
///
/// Per-frame uniforms, geometry sizes, resource identities, stencil references,
/// and native addresses are refreshed without rebuilding this value.
final class const PreparedCommandTopology._({
  required final DrawCommandAdmission admission,

  /// Whether the renderer admitted this command when the graph was built.
  required final bool active,
  required final int shader,
  required final int drawMode,
  required final int flags,
  required final int layer,
  required final int subLayerIndex,
  required final int stencilMode,
}) {
  factory PreparedCommandTopology.capture(
    ByteData data,
    int offset, {
    required bool active,
  }) {
    final shader = data.getUint32(
      offset + DrawCommandAbi.shaderType,
      Endian.little,
    );
    final stencilMode = data.getUint32(
      offset + DrawCommandAbi.stencilMode,
      Endian.little,
    );

    return PreparedCommandTopology._(
      admission: _commandAdmission(data, offset, shader, stencilMode),
      active: active,
      shader: shader,
      drawMode: data.getUint32(offset + DrawCommandAbi.drawMode, Endian.little),
      flags: data.getUint32(offset + DrawCommandAbi.flags, Endian.little),
      layer: data.getUint32(offset + DrawCommandAbi.layerIndex, Endian.little),
      subLayerIndex: data.getInt32(
        offset + DrawCommandAbi.subLayerIndex,
        Endian.little,
      ),
      stencilMode: stencilMode,
    );
  }

  int appendFamilyFingerprint(int hash) {
    hash = _mixTopologyFingerprint(hash, shader);
    hash = _mixTopologyFingerprint(hash, drawMode);
    hash = _mixTopologyFingerprint(hash, flags);
    hash = _mixTopologyFingerprint(hash, layer);
    hash = _mixTopologyFingerprint(hash, subLayerIndex);
    return _mixTopologyFingerprint(hash, stencilMode);
  }

  bool sameTopologyAs(PreparedCommandTopology other) =>
      admission == other.admission &&
      active == other.active &&
      shader == other.shader &&
      drawMode == other.drawMode &&
      flags == other.flags &&
      layer == other.layer &&
      subLayerIndex == other.subLayerIndex &&
      stencilMode == other.stencilMode;

  /// Returns the first field at [offset] that prevents graph-node reuse.
  PreparedGraphTopologyMismatchReason? firstMismatch(
    ByteData data,
    int offset,
  ) {
    final nextShader = data.getUint32(
      offset + DrawCommandAbi.shaderType,
      Endian.little,
    );
    if (shader != nextShader) {
      return PreparedGraphTopologyMismatchReason.shader;
    }
    final nextDrawMode = data.getUint32(
      offset + DrawCommandAbi.drawMode,
      Endian.little,
    );
    if (drawMode != nextDrawMode) {
      return PreparedGraphTopologyMismatchReason.drawMode;
    }
    final nextFlags = data.getUint32(
      offset + DrawCommandAbi.flags,
      Endian.little,
    );
    if (flags != nextFlags) {
      return PreparedGraphTopologyMismatchReason.flags;
    }
    final nextLayer = data.getUint32(
      offset + DrawCommandAbi.layerIndex,
      Endian.little,
    );
    if (layer != nextLayer) {
      return PreparedGraphTopologyMismatchReason.layer;
    }
    final nextSubLayer = data.getInt32(
      offset + DrawCommandAbi.subLayerIndex,
      Endian.little,
    );
    if (subLayerIndex != nextSubLayer) {
      return PreparedGraphTopologyMismatchReason.subLayer;
    }
    final nextStencilMode = data.getUint32(
      offset + DrawCommandAbi.stencilMode,
      Endian.little,
    );
    if (stencilMode != nextStencilMode) {
      return PreparedGraphTopologyMismatchReason.stencil;
    }
    if (admission !=
        _commandAdmission(data, offset, nextShader, nextStencilMode)) {
      return PreparedGraphTopologyMismatchReason.admission;
    }

    return null;
  }

  /// Whether the command at [offset] can reuse this graph node.
  bool matches(ByteData data, int offset) =>
      firstMismatch(data, offset) == null;
}

DrawCommandAdmission _commandAdmission(
  ByteData data,
  int offset,
  int shader,
  int stencilMode,
) => admitDrawCommand(
  shader: shader,
  stencilMode: stencilMode,
  vertexCount: data.getUint32(
    offset + DrawCommandAbi.vertexCount,
    Endian.little,
  ),
  indexCount: data.getUint32(offset + DrawCommandAbi.indexCount, Endian.little),
  vertexDataAddress: data.getUint64(
    offset + DrawCommandAbi.vertexData,
    Endian.little,
  ),
  indexDataAddress: data.getUint64(
    offset + DrawCommandAbi.indexData,
    Endian.little,
  ),
  drawableMatrixM00: data.getFloat32(
    offset + DrawCommandAbi.drawableUBO,
    Endian.little,
  ),
  drawableMatrixM11: data.getFloat32(
    offset +
        DrawCommandAbi.drawableUBO +
        RendererUboAbi.drawableMatrixM11Offset,
    Endian.little,
  ),
);

int _topologyFamilyFingerprintFromCommands(
  List<PreparedCommandTopology> commands,
) {
  var hash = _topologyFingerprintOffset;
  for (final command in commands) {
    hash = command.appendFamilyFingerprint(hash);
  }
  return hash;
}

int _topologyFamilyFingerprintFromBytes(
  ByteData data,
  int commandCount,
  int commandStride,
) {
  var hash = _topologyFingerprintOffset;
  for (var index = 0; index < commandCount; index += 1) {
    final offset = index * commandStride;
    hash = _mixTopologyFingerprint(
      hash,
      data.getUint32(offset + DrawCommandAbi.shaderType, Endian.little),
    );
    hash = _mixTopologyFingerprint(
      hash,
      data.getUint32(offset + DrawCommandAbi.drawMode, Endian.little),
    );
    hash = _mixTopologyFingerprint(
      hash,
      data.getUint32(offset + DrawCommandAbi.flags, Endian.little),
    );
    hash = _mixTopologyFingerprint(
      hash,
      data.getUint32(offset + DrawCommandAbi.layerIndex, Endian.little),
    );
    hash = _mixTopologyFingerprint(
      hash,
      data.getInt32(offset + DrawCommandAbi.subLayerIndex, Endian.little),
    );
    hash = _mixTopologyFingerprint(
      hash,
      data.getUint32(offset + DrawCommandAbi.stencilMode, Endian.little),
    );
  }
  return hash;
}

/// Exact structural identity of a decoded native command stream.
final class PreparedGraphKey._({
  required final int commandCount,
  required final int commandStride,
  required final List<PreparedCommandTopology> commands,

  /// Whether every otherwise-renderable command became a graph node.
  required final bool reusable,

  /// Fingerprint of command structure excluding admission/active state.
  required final int familyFingerprint,
}) {
  /// Captures graph topology without retaining native memory.
  factory PreparedGraphKey.capture({
    required Uint8List commandBytes,
    required int commandCount,
    required int commandStride,
    required Iterable<int> activeCommandOffsets,
  }) {
    if (commandCount < 0 ||
        commandStride != DrawCommandAbi.size ||
        commandBytes.lengthInBytes < commandCount * commandStride) {
      throw ArgumentError('Invalid DrawCommand block');
    }
    final activeOffsets = Set<int>.of(activeCommandOffsets);
    final data = ByteData.sublistView(commandBytes);
    final commands = List<PreparedCommandTopology>.generate(commandCount, (
      index,
    ) {
      final offset = index * commandStride;

      return PreparedCommandTopology.capture(
        data,
        offset,
        active: activeOffsets.contains(offset),
      );
    }, growable: false);
    final reusable = commands.every(
      (command) =>
          command.admission == DrawCommandAdmission.drop || command.active,
    );

    return PreparedGraphKey._(
      commandCount: commandCount,
      commandStride: commandStride,
      commands: List<PreparedCommandTopology>.unmodifiable(commands),
      reusable: reusable,
      familyFingerprint: _topologyFamilyFingerprintFromCommands(commands),
    );
  }

  /// Creates a key that always requires a graph rebuild.
  factory PreparedGraphKey.nonReusable({
    required int commandCount,
    required int commandStride,
  }) => PreparedGraphKey._(
    commandCount: commandCount,
    commandStride: commandStride,
    commands: const <PreparedCommandTopology>[],
    reusable: false,
    familyFingerprint: 0,
  );

  bool sameTopologyAs(PreparedGraphKey other) {
    if (commandCount != other.commandCount ||
        commandStride != other.commandStride ||
        familyFingerprint != other.familyFingerprint ||
        reusable != other.reusable ||
        commands.length != other.commands.length) {
      return false;
    }
    for (var index = 0; index < commands.length; index += 1) {
      if (!commands[index].sameTopologyAs(other.commands[index])) return false;
    }
    return true;
  }

  /// Returns the first stable-field difference from this retained graph.
  PreparedGraphTopologyMismatchReason? firstMismatch({
    required Uint8List commandBytes,
    required int commandCount,
    required int commandStride,
  }) {
    if (!reusable) {
      return PreparedGraphTopologyMismatchReason.nonReusable;
    }
    if (commandCount != this.commandCount) {
      return PreparedGraphTopologyMismatchReason.commandCount;
    }
    if (commandStride != this.commandStride) {
      return PreparedGraphTopologyMismatchReason.commandStride;
    }
    if (commandBytes.lengthInBytes < commandCount * commandStride) {
      return PreparedGraphTopologyMismatchReason.commandBytes;
    }
    final data = ByteData.sublistView(commandBytes);
    for (var index = 0; index < commands.length; index += 1) {
      final mismatch = commands[index].firstMismatch(
        data,
        index * commandStride,
      );
      if (mismatch != null) return mismatch;
    }

    return null;
  }

  /// Whether [commandBytes] has exactly the same stable work description.
  bool matches({
    required Uint8List commandBytes,
    required int commandCount,
    required int commandStride,
  }) {
    final mismatch = firstMismatch(
      commandBytes: commandBytes,
      commandCount: commandCount,
      commandStride: commandStride,
    );
    PreparedGraphTopologyDiagnostics._pendingMismatch = mismatch;
    return mismatch == null;
  }
}

/// One cached graph topology and its renderer-owned structural payload.
typedef PreparedGraphTemplateCacheEntry<T> = ({PreparedGraphKey key, T value});

typedef _PreparedGraphTemplateBucketKey = ({
  int commandCount,
  int commandStride,
  int familyFingerprint,
});

final class const _PreparedGraphTemplateCacheValue<T>({
  required final _PreparedGraphTemplateBucketKey bucketKey,
  required final PreparedGraphKey key,
  required final T value,
});

/// Small LRU of previously decoded graph topologies.
final class PreparedGraphTemplateCache<T>({final int capacity = 4}) {
  this {
    if (capacity <= 0) {
      throw RangeError.value(capacity, 'capacity', 'must be positive');
    }
  }

  final Map<
    _PreparedGraphTemplateBucketKey,
    List<_PreparedGraphTemplateCacheValue<T>>
  >
  _buckets = {};
  final List<_PreparedGraphTemplateCacheValue<T>> _recency = [];

  int get length => _recency.length;

  /// Remembers one reusable graph as the most recently displaced topology.
  void remember({required PreparedGraphKey key, required T value}) {
    if (!key.reusable) return;
    final bucketKey = (
      commandCount: key.commandCount,
      commandStride: key.commandStride,
      familyFingerprint: key.familyFingerprint,
    );
    final entries = _buckets.putIfAbsent(
      bucketKey,
      () => <_PreparedGraphTemplateCacheValue<T>>[],
    );
    for (var index = entries.length - 1; index >= 0; index -= 1) {
      final entry = entries[index];
      if (!entry.key.sameTopologyAs(key)) continue;
      entries.removeAt(index);
      _recency.remove(entry);
    }
    final entry = _PreparedGraphTemplateCacheValue(
      bucketKey: bucketKey,
      key: key,
      value: value,
    );
    entries.insert(0, entry);
    _recency.insert(0, entry);
    if (_recency.length > capacity) {
      final oldest = _recency.removeLast();
      final oldestBucket = _buckets[oldest.bucketKey]!;
      oldestBucket.remove(oldest);
      if (oldestBucket.isEmpty) _buckets.remove(oldest.bucketKey);
    }
  }

  /// Removes and returns the first cached topology matching this command block.
  PreparedGraphTemplateCacheEntry<T>? takeMatching({
    required Uint8List commandBytes,
    required int commandCount,
    required int commandStride,
  }) {
    final preservedMismatch = PreparedGraphTopologyDiagnostics._pendingMismatch;
    try {
      if (commandCount < 0 ||
          commandStride != DrawCommandAbi.size ||
          commandBytes.lengthInBytes < commandCount * commandStride) {
        return null;
      }
      final data = ByteData.sublistView(commandBytes);
      final bucketKey = (
        commandCount: commandCount,
        commandStride: commandStride,
        familyFingerprint: _topologyFamilyFingerprintFromBytes(
          data,
          commandCount,
          commandStride,
        ),
      );
      final entries = _buckets[bucketKey];
      if (entries == null) return null;
      for (var index = 0; index < entries.length; index += 1) {
        final entry = entries[index];
        if (entry.key.matches(
          commandBytes: commandBytes,
          commandCount: commandCount,
          commandStride: commandStride,
        )) {
          entries.removeAt(index);
          _recency.remove(entry);
          if (entries.isEmpty) _buckets.remove(bucketKey);
          return (key: entry.key, value: entry.value);
        }
      }
      return null;
    } finally {
      PreparedGraphTopologyDiagnostics._pendingMismatch = preservedMismatch;
    }
  }

  void clear() {
    _buckets.clear();
    _recency.clear();
  }
}

/// Timing totals for persistent graph reuse over one logging interval.
final class const PreparedGraphTimingSnapshot({
  required final int hitCount,
  required final int rebuildCount,
  required final int hitMicros,
  required final int rebuildMicros,
}) {
  int get sampleCount => hitCount + rebuildCount;

  double get hitRate => sampleCount == 0 ? 0 : hitCount / sampleCount;

  double? get averageHitMicros => hitCount == 0 ? null : hitMicros / hitCount;

  double? get averageRebuildMicros =>
      rebuildCount == 0 ? null : rebuildMicros / rebuildCount;
}

/// Accumulates graph reuse and rebuild timing until the next renderer log.
final class PreparedGraphTimingMetrics {
  int _hitCount = 0;
  int _rebuildCount = 0;
  int _hitMicros = 0;
  int _rebuildMicros = 0;

  void record({required bool reused, required int micros}) {
    if (micros < 0) {
      throw RangeError.value(micros, 'micros', 'must not be negative');
    }
    if (reused) {
      _hitCount += 1;
      _hitMicros += micros;
    } else {
      _rebuildCount += 1;
      _rebuildMicros += micros;
    }
  }

  PreparedGraphTimingSnapshot takeSnapshotAndReset() {
    final snapshot = PreparedGraphTimingSnapshot(
      hitCount: _hitCount,
      rebuildCount: _rebuildCount,
      hitMicros: _hitMicros,
      rebuildMicros: _rebuildMicros,
    );
    _hitCount = 0;
    _rebuildCount = 0;
    _hitMicros = 0;
    _rebuildMicros = 0;

    return snapshot;
  }
}

/// Stable decoded GPU work retained across native frame generations.
final class PreparedGraph<TEntry, TPartition>({
  required final PreparedGraphKey key,
  required final List<TEntry> entries,
  required final List<TPartition> partitions,
  required final int uniformAlignment,
  required final int uniformCursor,
  required final bool hasMapGlobalUniform,
  required final int commandCount,
  required final int? lastFillExtrusionLayerIndex,
});
