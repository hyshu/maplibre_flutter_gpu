part of '../prepared_graph.dart';

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
  factory capture({
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

    return ._(
      commandCount: commandCount,
      commandStride: commandStride,
      commands: .unmodifiable(commands),
      reusable: reusable,
      familyFingerprint: _topologyFamilyFingerprintFromCommands(commands),
    );
  }

  /// Creates a key that always requires a graph rebuild.
  factory nonReusable({
    required int commandCount,
    required int commandStride,
  }) => ._(
    commandCount: commandCount,
    commandStride: commandStride,
    commands: const [],
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
    if (!reusable) return .nonReusable;
    if (commandCount != this.commandCount) return .commandCount;
    if (commandStride != this.commandStride) return .commandStride;
    if (commandBytes.lengthInBytes < commandCount * commandStride) {
      return .commandBytes;
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
