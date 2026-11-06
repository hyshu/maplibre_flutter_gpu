import 'draw_flags.dart';
import 'ubo_abi.dart';

/// Whether native concatenates the tiles of a layer into batched commands.
///
/// Enabled by default. Set `--dart-define=MAPLIBRE_TILE_BATCHING=false` to
/// keep one native command per tile for diagnostics.
const tileBatchingEnabled = bool.fromEnvironment(
  'MAPLIBRE_TILE_BATCHING',
  defaultValue: true,
);

/// Returns the tiles a batched command covers, or zero when the command is
/// not batched or its payload does not hold whole members.
///
/// A batched drawable payload holds one exported drawable per member followed
/// by one table entry per member.
int tileBatchMemberCount({
  required int shader,
  required int flags,
  required int drawableSize,
}) {
  if (!drawCommandIsTileBatched(flags)) return 0;
  final memberBytes =
      rendererUboLayoutForShader(shader).drawableBytes +
      RendererUboAbi.tileBatchTableEntryBytes;
  if (drawableSize <= 0 || drawableSize % memberBytes != 0) return 0;
  final members = drawableSize ~/ memberBytes;

  return members > RendererUboAbi.tileBatchMembers ? 0 : members;
}

/// Returns the clipping-mask group of each command in stream order.
///
/// MapLibre renders tile clipping masks again inside a frame whenever a layer
/// group's tiles differ from the masks already in the stencil, and the new
/// tiles take the next references. The stencil keeps the earlier masks for the
/// layers already drawn, but one mask texture cannot, so each run of mask
/// commands forms a group and gets its own texture. A command belongs to the
/// group that most recently preceded it. Commands before any mask belong to
/// group zero. [clippingMasks] holds whether each command draws a clipping
/// mask.
List<int> tileMaskGroupsFor(List<bool> clippingMasks) {
  final groups = List<int>.filled(clippingMasks.length, 0);
  var group = -1;
  var inMasks = false;
  for (var index = 0; index < clippingMasks.length; index += 1) {
    if (clippingMasks[index]) {
      if (!inMasks) {
        group += 1;
        inMasks = true;
      }
      groups[index] = group;
    } else {
      inMasks = false;
      groups[index] = group < 0 ? 0 : group;
    }
  }
  return groups;
}
