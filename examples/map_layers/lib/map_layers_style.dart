import 'dart:convert';
import 'dart:io';

import 'heatmap_style.dart';
import 'hillshade_style.dart';

/// Loads the shared basemap and both layer demos, with hillshade hidden.
/// Network and decoding failures propagate so the page can offer a retry.
Future<({String style, int pointCount})> loadMapLayersStyle() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    Future<Map<String, dynamic>> readJson(String url) async {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      final body = await response.transform(utf8.decoder).join();

      return jsonDecode(body) as Map<String, dynamic>;
    }

    final documents = await Future.wait([
      readJson(basemapStyleUrl),
      readJson(earthquakeDataUrl),
    ]).timeout(const Duration(seconds: 30));
    final style = buildHillshadeStyle(
      buildHeatmapStyle(documents[0], documents[1]),
      visible: false,
    );

    return (
      style: jsonEncode(style),
      pointCount: (documents[1]['features'] as List).length,
    );
  } finally {
    client.close(force: true);
  }
}
