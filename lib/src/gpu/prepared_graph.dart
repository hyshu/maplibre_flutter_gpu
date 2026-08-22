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

  /// Whether the command at [offset] can reuse this graph node.
  ///
  /// This compares fields that affect pipeline selection, pass planning,
  /// partitioning, command order, or admission. Geometry and resource fields
  /// that remain renderable are dynamic.
  bool matches(ByteData data, int offset) {
    final nextShader = data.getUint32(
      offset + DrawCommandAbi.shaderType,
      Endian.little,
    );
    if (shader != nextShader) return false;
    final nextStencilMode = data.getUint32(
      offset + DrawCommandAbi.stencilMode,
      Endian.little,
    );
    if (stencilMode != nextStencilMode ||
        drawMode !=
            data.getUint32(offset + DrawCommandAbi.drawMode, Endian.little) ||
        flags != data.getUint32(offset + DrawCommandAbi.flags, Endian.little) ||
        layer !=
            data.getUint32(offset + DrawCommandAbi.layerIndex, Endian.little) ||
        subLayerIndex !=
            data.getInt32(
              offset + DrawCommandAbi.subLayerIndex,
              Endian.little,
            )) {
      return false;
    }

    return admission ==
        _commandAdmission(data, offset, nextShader, nextStencilMode);
  }
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
  ///
  /// Template cache buckets use this only to avoid unrelated topology families
  /// evicting each other. Exact matching still verifies every command, so a
  /// fingerprint collision cannot produce unsafe reuse.
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

  /// Whether [commandBytes] has exactly the same stable work description.
  bool matches({
    required Uint8List commandBytes,
    required int commandCount,
    required int commandStride,
  }) {
    if (!reusable ||
        commandCount != this.commandCount ||
        commandStride != this.commandStride ||
        commandBytes.lengthInBytes < commandCount * commandStride) {
      return false;
    }
    final data = ByteData.sublistView(commandBytes);
    for (var index = 0; index < commands.length; index += 1) {
      if (!commands[index].matches(data, index * commandStride)) return false;
    }

    return true;
  }
}

/// One cached graph topology and its renderer-owned structural payload.
typedef PreparedGraphTemplateCacheEntry<T> = ({
  PreparedGraphKey key,
  T value,
});

typedef _PreparedGraphTemplateBucketKey = ({
  int commandCount,
  int commandStride,
  int familyFingerprint,
});

/// Small LRU of previously decoded graph topologies.
///
/// Payloads must not retain per-frame native memory or GPU resources. Matching
/// removes an entry so callers can promote it back to the active graph and
/// remember the graph being displaced.
///
/// [capacity] applies independently to each structural topology family. The
/// family key includes `(commandCount, commandStride)` plus a fingerprint of
/// shader/draw-mode/flags/layer/sublayer/stencil fields while deliberately
/// excluding admission state. This prevents unrelated command streams with the
/// same command count from evicting recurring placement/admission variants.
final class PreparedGraphTemplateCache<T> {
  PreparedGraphTemplateCache({this.capacity = 4}) {
    if (capacity <= 0) {
      throw RangeError.value(capacity, 'capacity', 'must be positive');
    }
  }

  final int capacity;
  final Map<
    _PreparedGraphTemplateBucketKey,
    List<PreparedGraphTemplateCacheEntry<T>>
  > _buckets = {};

  int get length {
    var total = 0;
    for (final entries in _buckets.values) {
      total += entries.length;
    }
    return total;
  }

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
      () => <PreparedGraphTemplateCacheEntry<T>>[],
    );
    entries.removeWhere((entry) => entry.key.sameTopologyAs(key));
    entries.insert(0, (key: key, value: value));
    if (entries.length > capacity) {
      entries.removeRange(capacity, entries.length);
    }
  }

  /// Removes and returns the first cached topology matching this command block.
  PreparedGraphTemplateCacheEntry<T>? takeMatching({
    required Uint8List commandBytes,
    required int commandCount,
    required int commandStride,
  }) {
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
        if (entries.isEmpty) _buckets.remove(bucketKey);
        return entry;
      }
    }
    return null;
  }

  void clear() => _buckets.clear();
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

  double? get averageHitMicros =>
      hitCount == 0 ? null : hitMicros / hitCount;

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
///
/// [entries] and [partitions] are renderer-owned mutable storage. Their
/// identities remain fixed for this graph, while per-frame uniforms and native
/// resource references are refreshed separately.
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
