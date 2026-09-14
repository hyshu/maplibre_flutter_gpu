part of '../visual_e2e_shared.dart';

Future<void> stopVisualE2eAssetServer() => _VisualAssetServer.stop();

const _assetBasePlaceholder = '__VISUAL_E2E_ASSET_BASE__';
const _mbtilesPlaceholders = {
  '__VISUAL_E2E_MBTILES_URL__': 'map.mbtiles',
  '__VISUAL_E2E_MBTILES_VECTOR_URL__': 'map-vector.mbtiles',
  '__VISUAL_E2E_MBTILES_MLT_URL__': 'map-mlt.mbtiles',
};

final _rasterTilePattern = RegExp(r'^/raster/\d+/\d+/\d+\.png$');
final _jpegTilePattern = RegExp(r'^/raster-jpeg/\d+/\d+/\d+\.jpg$');
final _webpTilePattern = RegExp(r'^/raster-webp/\d+/\d+/\d+\.webp$');
final _tmsTilePattern = RegExp(r'^/tms/\d+/\d+/([01])\.png$');
final _wmtsTilePattern = RegExp(r'^/wmts/\d+/\d+/\d+\.png$');
final _pmtilesArchivePattern = RegExp(
  r'^/archives/(map(?:-vector|-mlt)?\.pmtiles)$',
);
final _vectorTilePattern = RegExp(
  r'^/vector/(point|line|polygon|map)/\d+/\d+/\d+\.pbf$',
);
final _mltTilePattern = RegExp(r'^/vector/map/\d+/\d+/\d+\.mlt$');
final _glyphPattern = RegExp(r'^/glyphs/([^/]+)/(\d+-\d+)\.pbf$');

@visibleForTesting
String? visualE2eGlyphAssetPath(String requestPath) {
  final normalized = requestPath.replaceFirst('@2x', '');
  final match = _glyphPattern.firstMatch(normalized);
  if (match == null) return null;
  final fontStack = Uri.decodeComponent(match.group(1)!);
  final fixtureFont = fontStack == 'Noto Sans Regular,Noto Sans Hebrew Regular'
      ? 'NotoSansHebrew'
      : 'NotoCJK';

  return 'packages/visual_e2e_shared/assets/resources/glyphs/$fixtureFont/'
      '${match.group(2)}.pbf';
}

@visibleForTesting
String? visualE2eSpriteAssetPath(String requestPath) {
  final normalized = requestPath.replaceFirst('@2x', '');

  return switch (normalized) {
    '/sprite.json' || '/sprite-alt.json' =>
      'packages/visual_e2e_shared/assets/resources/sprite.json',
    '/sprite.png' || '/sprite-alt.png' =>
      'packages/visual_e2e_shared/assets/resources/sprite.png',
    _ => null,
  };
}

class _VisualAssetServer {
  new _(this._server);

  static _VisualAssetServer? _instance;
  static final _materializedMbtiles = <String, File>{};

  final HttpServer _server;

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}/');

  static Future<_VisualAssetServer> start() async {
    final existing = _instance;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = _VisualAssetServer._(server);
    _instance = instance;
    unawaited(instance._serve());

    return instance;
  }

  static Future<void> stop() async {
    final instance = _instance;
    _instance = null;
    await instance?._server.close(force: true);
    final materialized = _materializedMbtiles.values.toList();
    _materializedMbtiles.clear();
    for (final mbtiles in materialized) {
      try {
        if (await mbtiles.exists()) await mbtiles.delete();
      } on FileSystemException {
        // Teardown remains best-effort if the temporary fixture is gone.
      }
    }
  }

  static Future<String> materializeMbtiles(String name) async {
    final existing = _materializedMbtiles[name];
    if (existing != null) return 'mbtiles://${existing.path}';
    final data = await rootBundle.load(
      'packages/visual_e2e_shared/assets/resources/archives/$name',
    );
    final file = File(
      '${Directory.systemTemp.path}/maplibre-flutter-gpu-visual-$pid-$name',
    );
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    _materializedMbtiles[name] = file;

    return 'mbtiles://${file.path}';
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      try {
        final archiveMatch = _pmtilesArchivePattern.firstMatch(
          request.uri.path,
        );
        if (archiveMatch != null) {
          final name = archiveMatch.group(1)!;
          await _serveRangeAsset(
            request,
            'packages/visual_e2e_shared/assets/resources/archives/$name',
          );
          continue;
        }
        if (request.uri.path == '/tilejson/vector.json') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'tilejson': '3.0.0',
              'tiles': [
                '${baseUri.toString().replaceFirst(RegExp(r'/$'), '')}'
                    '/vector/map/{z}/{x}/{y}.pbf',
              ],
              'minzoom': 0,
              'maxzoom': 0,
            }),
          );
          continue;
        }
        if (request.uri.path == '/geojson/features.json') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'type': 'FeatureCollection',
              'features': [
                {
                  'type': 'Feature',
                  'properties': {'kind': 'url-fixture'},
                  'geometry': {
                    'type': 'Polygon',
                    'coordinates': [
                      [
                        [-100.0, -45.0],
                        [100.0, -45.0],
                        [100.0, 45.0],
                        [-100.0, 45.0],
                        [-100.0, -45.0],
                      ],
                    ],
                  },
                },
              ],
            }),
          );
          continue;
        }
        final asset = _assetForPath(request.uri.path);
        if (asset == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          final data = await rootBundle.load(asset.path);
          request.response.headers
            ..contentType = asset.contentType
            ..set(HttpHeaders.cacheControlHeader, 'public, max-age=3600');
          request.response.add(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        }
      } catch (error, stackTrace) {
        debugPrint('visual asset server error: $error\n$stackTrace');
        request.response.statusCode = HttpStatus.internalServerError;
      } finally {
        await request.response.close();
      }
    }
  }

  Future<void> _serveRangeAsset(HttpRequest request, String asset) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    request.response.headers
      ..contentType = ContentType.binary
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.cacheControlHeader, 'public, max-age=3600');
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range == null) {
      request.response.contentLength = bytes.length;
      request.response.add(bytes);

      return;
    }
    final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
    if (match == null) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */${bytes.length}',
      );

      return;
    }
    final start = int.parse(match.group(1)!);
    final requestedEnd = match.group(2)!.isEmpty
        ? bytes.length - 1
        : int.parse(match.group(2)!);
    if (start >= bytes.length || requestedEnd < start) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */${bytes.length}',
      );

      return;
    }
    final end = requestedEnd.clamp(start, bytes.length - 1);
    request.response
      ..statusCode = HttpStatus.partialContent
      ..contentLength = end - start + 1;
    request.response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/${bytes.length}',
    );
    request.response.add(bytes.sublist(start, end + 1));
  }

  ({String path, ContentType contentType})? _assetForPath(String path) {
    final normalized = path.replaceFirst('@2x', '');
    final glyphAsset = visualE2eGlyphAssetPath(normalized);
    if (glyphAsset != null) {
      return (path: glyphAsset, contentType: ContentType.binary);
    }
    final spriteAsset = visualE2eSpriteAssetPath(normalized);
    if (spriteAsset != null) {
      return (
        path: spriteAsset,
        contentType: normalized.endsWith('.json')
            ? ContentType.json
            : ContentType('image', 'png'),
      );
    }

    return switch (normalized) {
      // Every {z}/{x}/{y} serves the same tile. The scene only needs the
      // raster pipeline exercised with a real texture, and a single asymmetric
      // tile makes a flipped or transposed UV visible in the baseline.
      _ when _rasterTilePattern.hasMatch(normalized) => (
        path: 'packages/visual_e2e_shared/assets/resources/raster-tile.png',
        contentType: ContentType('image', 'png'),
      ),
      _ when _jpegTilePattern.hasMatch(normalized) => (
        path: 'packages/visual_e2e_shared/assets/resources/raster-tile.jpg',
        contentType: ContentType('image', 'jpeg'),
      ),
      _ when _webpTilePattern.hasMatch(normalized) => (
        path: 'packages/visual_e2e_shared/assets/resources/raster-tile.webp',
        contentType: ContentType('image', 'webp'),
      ),
      _ when _tmsTilePattern.hasMatch(normalized) => (
        path:
            'packages/visual_e2e_shared/assets/resources/'
            'tms-${_tmsTilePattern.firstMatch(normalized)!.group(1)}.png',
        contentType: ContentType('image', 'png'),
      ),
      _ when _wmtsTilePattern.hasMatch(normalized) => (
        path: 'packages/visual_e2e_shared/assets/resources/raster-tile.png',
        contentType: ContentType('image', 'png'),
      ),
      _ when _vectorTilePattern.hasMatch(normalized) => (
        path:
            'packages/visual_e2e_shared/assets/resources/vector/'
            '${_vectorTilePattern.firstMatch(normalized)!.group(1)}.pbf',
        contentType: ContentType.binary,
      ),
      _ when _mltTilePattern.hasMatch(normalized) => (
        path: 'packages/visual_e2e_shared/assets/resources/vector/map.mlt',
        contentType: ContentType.binary,
      ),
      _ => null,
    };
  }
}
