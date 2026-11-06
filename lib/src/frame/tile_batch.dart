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
