import 'package:flutter/foundation.dart';

import '../native/abi_generated.dart';
import '../native/command_payload.dart';
import '../native/draw_command.dart';

/// Whether immutable hillshade preparation outputs may be reused on Android.
bool get hillshadePreparationCachingEnabled =>
    const bool.fromEnvironment(
      'MAPLIBRE_CACHE_HILLSHADE_PREPARATION',
      defaultValue: true,
    ) &&
    defaultTargetPlatform == TargetPlatform.android;

/// Whether the optional preparation cache records interval diagnostics.
const hillshadePreparationCacheDiagnosticsEnabled = bool.fromEnvironment(
  'MAPLIBRE_HILLSHADE_CACHE_DIAGNOSTICS',
);

/// Copied native content identities for one complete hillshade preparation quad.
///
/// Address values participate in geometry identity but are never dereferenced
/// after capture. This value owns no native or GPU resources.
final class HillshadePreparationResources {
  HillshadePreparationResources._(this._geometry, this._texture);

  /// Returns null for unversioned resources or unsupported preparation shapes.
  ///
  /// [payload] must already select the command at [offset].
  static HillshadePreparationResources? capture(
    ByteData commands,
    int offset,
    CommandPayloadReader payload,
  ) {
    int u32(int field) => commands.getUint32(offset + field, Endian.little);
    int address(int field) => commands.getUint64(offset + field, Endian.little);
    final bufferId = u32(DrawCommandAbi.bufferId);
    final bufferVersion = u32(DrawCommandAbi.bufferVersion);
    final vertexAddress = address(DrawCommandAbi.vertexData);
    final indexAddress = address(DrawCommandAbi.indexData);
    if (u32(DrawCommandAbi.shaderType) != ShaderType.hillshadePrepare ||
        u32(DrawCommandAbi.drawMode) != DrawModeType.triangles ||
        u32(DrawCommandAbi.flags) != 0 ||
        u32(DrawCommandAbi.vertexStride) != 8 ||
        u32(DrawCommandAbi.vertexCount) != 4 ||
        u32(DrawCommandAbi.indexCount) != 6 ||
        bufferId == 0 ||
        bufferVersion == 0 ||
        vertexAddress == 0 ||
        indexAddress == 0 ||
        payload.textureId == 0 ||
        payload.textureVersion == 0 ||
        payload.textureAddress == 0 ||
        payload.textureWidth <= 0 ||
        payload.textureHeight <= 0 ||
        payload.textureChannels != 4 ||
        payload.drawableSize != 64 ||
        payload.propsSize != 0 ||
        payload.tilePropsSize != 32 ||
        payload.stencilMode != StencilModeType.disabled) {
      return null;
    }

    return ._(
      (bufferId, bufferVersion, vertexAddress, indexAddress),
      (
        payload.textureId,
        payload.textureVersion,
        payload.textureWidth,
        payload.textureHeight,
        payload.textureChannels,
        payload.textureFilter,
      ),
    );
  }

  // Counts, layouts and draw mode are fixed by admission above. The pipeline
  // converts the native eight-byte raster vertex to four floats.
  final (int, int, int, int) _geometry;
  final (int, int, int, int, int, int) _texture;

  bool _matches(HillshadePreparationResources other) =>
      _geometry == other._geometry && _texture == other._texture;
}

/// Complete immutable inputs for one supported preparation target.
///
/// Uniform contents are copied because the renderer reuses its staging buffer.
final class HillshadePreparationKey {
  HillshadePreparationKey._(
    this.targetId,
    this.width,
    this.height,
    this._resources,
    this._uniforms,
  );

  /// Copies the two packed shader blocks, or returns null for invalid ranges.
  static HillshadePreparationKey? capture({
    required int targetId,
    required int width,
    required int height,
    required HillshadePreparationResources resources,
    required ByteData uniforms,
    required int drawableOffset,
    required int drawableLength,
    required int propsLength,
    required int tilePropsOffset,
    required int tilePropsLength,
  }) {
    bool contains(int offset, int length) =>
        offset >= 0 && offset <= uniforms.lengthInBytes - length;
    if (targetId <= 0 ||
        width <= 0 ||
        height <= 0 ||
        drawableLength != 64 ||
        propsLength != 0 ||
        tilePropsLength != 32 ||
        !contains(drawableOffset, drawableLength) ||
        !contains(tilePropsOffset, tilePropsLength)) {
      return null;
    }
    final bytes = Uint8List(96);
    for (var i = 0; i < 64; i++) {
      bytes[i] = uniforms.getUint8(drawableOffset + i);
    }
    for (var i = 0; i < 32; i++) {
      bytes[64 + i] = uniforms.getUint8(tilePropsOffset + i);
    }

    return ._(targetId, width, height, resources, bytes);
  }

  final int targetId;
  final int width;
  final int height;
  final HillshadePreparationResources _resources;
  final Uint8List _uniforms;

  /// Compares all admitted resource identities and exact shader bytes.
  bool matches(HillshadePreparationKey other) =>
      targetId == other.targetId &&
      width == other.width &&
      height == other.height &&
      _resources._matches(other._resources) &&
      listEquals(_uniforms, other._uniforms);
}

/// A write that may publish contents only into its original active allocation.
///
/// It owns copied scalar inputs, not the target texture or renderer.
final class HillshadePreparationWrite {
  HillshadePreparationWrite._(
    this._epoch,
    this._allocation,
    this._serial,
    this._key,
  );

  final int _epoch;
  final int _allocation;
  final int _serial;
  final HillshadePreparationKey _key;
}

/// Interval counts for hillshade preparation decisions and submissions.
typedef HillshadePreparationCacheSnapshot = ({
  int eligible,
  int reused,
  int rendered,
  int invalidated,
  int pending,
  int completionFailures,
});

final class _PreparationContents {
  _PreparationContents(this.allocation);

  final int allocation;
  var serial = 0;
  var pending = false;
  HillshadePreparationKey? completed;
}

/// Tracks completed contents without owning targets or their input resources.
///
/// Register every new target allocation. Retain only active targets and clear
/// on memory trim or disposal. Command completion may arrive after either action.
final class HillshadePreparationCache {
  HillshadePreparationCache({this.diagnostics = false});

  final bool diagnostics;
  final _targets = <int, _PreparationContents>{};
  var _epoch = 0;
  var _allocation = 0;
  var _serial = 0;
  var _eligible = 0;
  var _reused = 0;
  var _rendered = 0;
  var _invalidated = 0;
  var _pending = 0;
  var _completionFailures = 0;

  /// Replaces a target's allocation and invalidates every earlier write to it.
  void replaceTarget(int targetId) {
    invalidate(targetId);
    _targets[targetId] = _PreparationContents(++_allocation);
  }

  /// Drops contents for targets no longer present in the current native frame.
  void retainTargets(Set<int> active) {
    _targets.removeWhere((id, contents) {
      if (active.contains(id)) return false;
      _recordInvalidation(contents);

      return true;
    });
  }

  /// Returns true only for matching contents whose latest write completed.
  bool canReuse(HillshadePreparationKey key) {
    final target = _targets[key.targetId];
    if (diagnostics) {
      _eligible++;
      if (target?.pending ?? false) _pending++;
    }
    final matches = target?.completed?.matches(key) ?? false;
    if (matches && diagnostics) _reused++;

    return matches;
  }

  /// Invalidates prior contents before any recording that can overwrite them.
  HillshadePreparationWrite beginWrite(HillshadePreparationKey key) {
    final target = _targets[key.targetId];
    if (target == null) throw StateError('Unregistered hillshade target');
    invalidate(key.targetId);
    target
      ..serial = ++_serial
      ..pending = true;

    return ._(_epoch, target.allocation, target.serial, key);
  }

  /// Records a preparation accepted by command-buffer submission.
  ///
  /// Completion may still fail asynchronously. Unsupported preparation shapes
  /// are included because they also submit a hillshade pass.
  void recordSubmission() {
    if (diagnostics) _rendered++;
  }

  /// Publishes successful command completion only for the latest active write.
  ///
  /// The callback confirms backend submission, not presentation or a GPU fence.
  void complete(HillshadePreparationWrite write, bool success) {
    final target = _currentTarget(write);
    if (target == null) return;
    target.pending = false;
    target.completed = success ? write._key : null;
    if (!success && diagnostics) _completionFailures++;
  }

  /// Cancels a write after synchronous recording or submission failure.
  void cancel(HillshadePreparationWrite write) {
    final target = _currentTarget(write);
    if (target == null) return;
    target.pending = false;
    target.completed = null;
  }

  _PreparationContents? _currentTarget(HillshadePreparationWrite write) {
    final target = _targets[write._key.targetId];
    if (write._epoch != _epoch ||
        target == null ||
        target.allocation != write._allocation ||
        target.serial != write._serial ||
        !target.pending) {
      return null;
    }
    return target;
  }

  /// Forgets contents and pending writes before uncached rendering.
  void invalidate(int targetId) {
    final target = _targets[targetId];
    if (target == null) return;
    _recordInvalidation(target);
    target
      ..completed = null
      ..pending = false;
  }

  void _recordInvalidation(_PreparationContents target) {
    if (diagnostics && (target.pending || target.completed != null)) {
      _invalidated++;
    }
  }

  /// Invalidates all allocations, including callbacks already queued to the UI.
  void clear() {
    for (final target in _targets.values) {
      _recordInvalidation(target);
    }
    _targets.clear();
    _epoch++;
  }

  /// Returns and resets counters, or null when diagnostics are disabled.
  HillshadePreparationCacheSnapshot? takeSnapshot() {
    if (!diagnostics) return null;
    final result = (
      eligible: _eligible,
      reused: _reused,
      rendered: _rendered,
      invalidated: _invalidated,
      pending: _pending,
      completionFailures: _completionFailures,
    );
    _eligible = _reused = _rendered = _invalidated = _pending =
        _completionFailures = 0;

    return result;
  }
}
