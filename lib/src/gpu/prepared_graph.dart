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
final class PreparedGraphTopologyDiagnostics {
  PreparedGraphTopologyDiagnostics._();

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
final class PreparedCommandTopology {
  const PreparedCommandTopology._({
    required this.admission,
    required this.active,
    required this.shader,
    required this.drawMode,
    required this.flags,
    required this.layer,
    required this.subLayerIndex,
    required this.stencilMode,
  });

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

  final DrawCommandAdmission admission;

  /// Whether the renderer admitted this command when the graph was built.
  final bool active;
  final int shader;
  final int drawMode;
  final int flags;
  final int layer;
  final int subLayerIndex;
  final int stencilMode;

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
final class PreparedGraphKey {
  PreparedGraphKey._({
    required this.commandCount,
    required this.commandStride,
    required this.commands,
    required this.reusable,
    required this.familyFingerprint,
  });

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

  final int commandCount;
  final int commandStride;
  final List<PreparedCommandTopology> commands;

  /// Fingerprint of command structure excluding admission/active state.
  final int familyFingerprint;

  /// Whether every otherwise-renderable command became a graph node.
  final bool reusable;

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

final class _PreparedGraphTemplateCacheValue<T> {
  const _PreparedGraphTemplateCacheValue({
    required this.bucketKey,
    required this.key,
    required this.value,
  });

  final _PreparedGraphTemplateBucketKey bucketKey;
  final PreparedGraphKey key;
  final T value;
}

/// Small LRU of previously decoded graph topologies.
final class PreparedGraphTemplateCache<T> {
  PreparedGraphTemplateCache({this.capacity = 4}) {
    if (capacity <= 0) {
      throw RangeError.value(capacity, 'capacity', 'must be positive');
    }
  }

  final int capacity;
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
final class PreparedGraphTimingSnapshot {
  const PreparedGraphTimingSnapshot({
    required this.hitCount,
    required this.rebuildCount,
    required this.hitMicros,
    required this.rebuildMicros,
  });

  final int hitCount;
  final int rebuildCount;
  final int hitMicros;
  final int rebuildMicros;

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
final class PreparedGraph<TEntry, TPartition> {
  PreparedGraph({
    required this.key,
    required this.entries,
    required this.partitions,
    required this.uniformAlignment,
    required this.uniformCursor,
    required this.hasMapGlobalUniform,
    required this.commandCount,
    required this.lastFillExtrusionLayerIndex,
  });

  final PreparedGraphKey key;
  final List<TEntry> entries;
  final List<TPartition> partitions;
  final int uniformAlignment;
  final int uniformCursor;
  final bool hasMapGlobalUniform;
  final int commandCount;
  final int? lastFillExtrusionLayerIndex;
}
