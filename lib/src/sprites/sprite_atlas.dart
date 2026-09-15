// Loads the sprite sheet referenced by a style and exposes its icons for
// widget rendering.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

part 'sprite_layout.dart';
part 'sprite_icon.dart';
part 'sprite_sources.dart';
part 'sprite_icon_widget.dart';

/// Provides named icons from a style's sprite sheet.
class SpriteAtlas._(
  final Map<String, SpriteIcon> _icons,
  final List<ui.Image> _images,
) {
  var _disposed = false;

  /// Returns the icon named [name], or null when it is not present.
  SpriteIcon? operator [](String name) => _icons[name];

  /// Loads the sprite atlas referenced by [styleSource].
  ///
  /// [styleSource] may be a URL or raw JSON. [baseStyleUrl] resolves relative
  /// sprite references when the source is raw JSON. The `@2x` variant is tried
  /// before the 1x variant. Returns null when no atlas can be loaded.
  static Future<SpriteAtlas?> load(
    String styleSource, {
    String? baseStyleUrl,
  }) async {
    try {
      final isRawJson = styleSource.trimLeft().startsWith('{');
      final styleJson = json.decode(
        isRawJson ? styleSource : await _fetchString(Uri.parse(styleSource)),
      ) as Map<String, dynamic>;
      final resolutionBase = baseStyleUrl ?? styleSource;
      final sources = spriteSources(styleJson['sprite']);
      if (sources.isEmpty) return null;

      final icons = <String, SpriteIcon>{};
      final images = <ui.Image>[];
      try {
        for (final source in sources) {
          final sheet = await _loadSheet(resolutionBase, source.id, source.url);
          if (sheet == null) continue;
          images.add(sheet.image);
          icons.addAll(sheet.icons);
        }
        if (images.isEmpty) return null;
        debugPrint(
          '[SpriteAtlas] loaded ${icons.length} icons from '
          '${images.length} sprite source${images.length == 1 ? '' : 's'}',
        );

        return ._(icons, images);
      } catch (_) {
        for (final image in images) {
          image.dispose();
        }
        rethrow;
      }
    } catch (e) {
      debugPrint('[SpriteAtlas] failed to load sprite for $styleSource: $e');

      return null;
    }
  }

  /// Releases the atlas image and removes all icons.
  ///
  /// Repeated calls do nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _icons.clear();
    for (final image in _images) {
      image.dispose();
    }
    _images.clear();
  }

  static Future<_SpriteSheet?> _loadSheet(
    String resolutionBase,
    String spriteId,
    String spriteBase,
  ) async {
    for (final suffix in ['@2x', '']) {
      ui.Image? image;
      try {
        final manifestUri = spriteAssetUri(
          resolutionBase,
          spriteBase,
          suffix,
          'json',
        );
        final pngUri = spriteAssetUri(
          resolutionBase,
          spriteBase,
          suffix,
          'png',
        );
        final manifest = json.decode(
          await _fetchString(manifestUri),
        ) as Map<String, dynamic>;
        final codec = await ui.instantiateImageCodec(await _fetchBytes(pngUri));
        try {
          image = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
        final atlas = image;

        final icons = <String, SpriteIcon>{};
        manifest.forEach((name, dynamic entry) {
          if (entry is! Map) return;
          final fields = entry.cast<String, dynamic>();
          final x = (fields['x'] as num?)?.toDouble() ?? 0;
          final y = (fields['y'] as num?)?.toDouble() ?? 0;
          final width = (fields['width'] as num?)?.toDouble() ?? 0;
          final height = (fields['height'] as num?)?.toDouble() ?? 0;
          final pixelRatio = (fields['pixelRatio'] as num?)?.toDouble() ?? 1;
          if (x < 0 ||
              y < 0 ||
              width <= 0 ||
              height <= 0 ||
              pixelRatio <= 0 ||
              x + width > atlas.width ||
              y + height > atlas.height) {
            return;
          }
          icons[spriteImageName(spriteId, name)] = .new(
            atlas: atlas,
            x: x,
            y: y,
            width: width,
            height: height,
            pixelRatio: pixelRatio,
            sdf: fields['sdf'] == true,
            stretchX: _parseStretch(fields['stretchX'], width),
            stretchY: _parseStretch(fields['stretchY'], height),
            content: _parseContent(fields['content'], width, height),
            textFitWidth: _parseTextFit(fields['textFitWidth']),
            textFitHeight: _parseTextFit(fields['textFitHeight']),
          );
        });

        return .new(atlas, icons);
      } catch (_) {
        image?.dispose();
        // Try the next resolution variant for this source.
      }
    }

    return null;
  }

  static List<(double, double)> _parseStretch(Object? value, double extent) {
    if (value is! List) return const [];
    final ranges = <(double, double)>[];
    for (final item in value) {
      if (item is! List || item.length != 2) continue;
      final start = item[0];
      final end = item[1];
      if (start is! num || end is! num) continue;
      final from = start.toDouble();
      final to = end.toDouble();
      if (from < 0 || to <= from || to > extent) continue;
      ranges.add((from, to));
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));

    return List.unmodifiable(ranges);
  }

  static Rect? _parseContent(Object? value, double width, double height) {
    if (value is! List || value.length != 4) return null;
    final left = value[0];
    final top = value[1];
    final right = value[2];
    final bottom = value[3];
    if (left is! num || top is! num || right is! num || bottom is! num) {
      return null;
    }
    final rect = Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    );
    if (rect.left < 0 ||
        rect.top < 0 ||
        rect.right <= rect.left ||
        rect.bottom <= rect.top ||
        rect.right > width ||
        rect.bottom > height) {
      return null;
    }

    return rect;
  }

  static SpriteTextFit? _parseTextFit(Object? value) => switch (value) {
    'stretchOrShrink' => .stretchOrShrink,
    'stretchOnly' => .stretchOnly,
    'proportional' => .proportional,
    _ => null,
  };

  static Future<String> _fetchString(Uri uri) async =>
      utf8.decode(await _fetchBytes(uri));

  /// Reads bytes from a file URI, local path, bundled asset, or network URI.
  static Future<Uint8List> _fetchBytes(Uri uri) async {
    if (uri.scheme == 'file') return File.fromUri(uri).readAsBytes();
    if (uri.scheme.isEmpty) {
      if (File(uri.path).isAbsolute) return File(uri.path).readAsBytes();
      final data = await rootBundle.load(uri.path);

      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} for $uri');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }
}

class const _SpriteSheet(
  final ui.Image image,
  final Map<String, SpriteIcon> icons,
);
