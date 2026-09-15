part of 'sprite_atlas.dart';

@visibleForTesting
/// Parses the sprite sources accepted by the MapLibre style specification.
List<({String id, String url})> spriteSources(Object? sprite) {
  if (sprite is String && sprite.isNotEmpty) {
    return [(id: 'default', url: sprite)];
  }
  if (sprite is! List) return const [];

  final sources = <({String id, String url})>[];
  final ids = <String>{};
  for (final entry in sprite) {
    if (entry is! Map) continue;
    final id = entry['id'];
    final url = entry['url'];
    if (id is! String || id.isEmpty || url is! String || url.isEmpty) {
      continue;
    }
    if (!ids.add(id)) continue;
    sources.add((id: id, url: url));
  }

  return sources;
}

@visibleForTesting
/// Applies the namespace used by sprite arrays to an image name.
String spriteImageName(String spriteId, String imageName) =>
    spriteId == 'default' ? imageName : '$spriteId:$imageName';

@visibleForTesting
/// Resolves a sprite asset URI from its style and sprite references.
Uri spriteAssetUri(
  String styleUrl,
  String spriteBase,
  String suffix,
  String extension,
) {
  final spriteUri = Uri.parse(spriteBase);
  final base = spriteUri.hasScheme || styleUrl.trimLeft().startsWith('{')
      ? spriteUri
      : Uri.parse(styleUrl).resolveUri(spriteUri);

  return base.replace(path: '${base.path}$suffix.$extension');
}
