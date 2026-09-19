part of '../prepared_graph.dart';

const _topologyFingerprintMask = 0xffff_ffff_ffff_ffff;
const _topologyFingerprintOffset = 0xcbf2_9ce4_8422_2325;
const _topologyFingerprintPrime = 0x0100_0000_01b3;

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
  factory capture(ByteData data, int offset, {required bool active}) {
    final shader = data.getUint32(
      offset + DrawCommandAbi.shaderType,
      Endian.little,
    );
    final stencilMode = data.getUint32(
      offset + DrawCommandAbi.stencilMode,
      Endian.little,
    );

    return ._(
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
    if (shader != nextShader) return .shader;
    final nextDrawMode = data.getUint32(
      offset + DrawCommandAbi.drawMode,
      Endian.little,
    );
    if (drawMode != nextDrawMode) return .drawMode;
    final nextFlags = data.getUint32(
      offset + DrawCommandAbi.flags,
      Endian.little,
    );
    if (flags != nextFlags) return .flags;
    final nextLayer = data.getUint32(
      offset + DrawCommandAbi.layerIndex,
      Endian.little,
    );
    if (layer != nextLayer) return .layer;
    final nextSubLayer = data.getInt32(
      offset + DrawCommandAbi.subLayerIndex,
      Endian.little,
    );
    if (subLayerIndex != nextSubLayer) return .subLayer;
    final nextStencilMode = data.getUint32(
      offset + DrawCommandAbi.stencilMode,
      Endian.little,
    );
    if (stencilMode != nextStencilMode) return .stencil;
    if (admission !=
        _commandAdmission(data, offset, nextShader, nextStencilMode)) {
      return .admission;
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
