import 'dart:typed_data';

import '../frame/draw_command_admission.dart';
import '../frame/ubo_abi.dart';
import '../native/abi_generated.dart';

part 'prepared_graph/topology.dart';
part 'prepared_graph/key.dart';
part 'prepared_graph/template_cache.dart';
part 'prepared_graph/timing.dart';

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
