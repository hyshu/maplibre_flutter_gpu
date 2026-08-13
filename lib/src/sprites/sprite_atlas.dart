// Loads the sprite sheet referenced by a style and exposes its icons for
// widget rendering.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

@visibleForTesting
/// Returns the image and filter colors used to paint a sprite.
({Color imageColor, Color? filterColor}) spritePaintColors(
  double opacity,
  Color? tint,
) {
  final clampedOpacity = opacity.clamp(0.0, 1.0);
  if (tint != null) {
    return (
      imageColor: const Color(0xFFFFFFFF),
      filterColor: tint.withValues(alpha: tint.a * clampedOpacity),
    );
  }
  return (
    imageColor: Color.fromRGBO(255, 255, 255, clampedOpacity),
    filterColor: null,
  );
}

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

/// One icon in the sprite sheet.
class SpriteIcon {
  /// Image containing this icon.
  final ui.Image atlas;

  /// Horizontal offset of the icon in atlas pixels.
  final double x;

  /// Vertical offset of the icon in atlas pixels.
  final double y;

  /// Width of the icon in atlas pixels.
  final double width;

  /// Height of the icon in atlas pixels.
  final double height;

  /// Ratio between atlas pixels and logical pixels.
  final double pixelRatio;

  /// Whether the icon contains signed distance field data.
  final bool sdf;

  const SpriteIcon({
    required this.atlas,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.pixelRatio,
    required this.sdf,
  });

  /// Logical display size after applying [pixelRatio].
  Size get displaySize => Size(width / pixelRatio, height / pixelRatio);
}

/// Provides named icons from a style's sprite sheet.
class SpriteAtlas {
  final Map<String, SpriteIcon> _icons;
  final ui.Image _image;
  var _disposed = false;

  SpriteAtlas._(this._icons, this._image);

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
      final sprite = styleJson['sprite'];
      // A sprite reference can be a URL string or a list of named URLs.
      String? spriteBase;
      if (sprite is String) {
        spriteBase = sprite;
      } else if (sprite is List && sprite.isNotEmpty) {
        final first = sprite.first;
        if (first is Map && first['url'] is String) {
          spriteBase = first['url'] as String;
        }
      }
      if (spriteBase == null) return null;

      for (final suffix in ['@2x', '']) {
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
          final pngBytes = await _fetchBytes(pngUri);
          final codec = await ui.instantiateImageCodec(pngBytes);
          late final ui.Image atlas;
          try {
            atlas = (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }

          try {
            final icons = <String, SpriteIcon>{};
            manifest.forEach((name, dynamic entry) {
              if (entry is! Map) return;
              final fields = entry.cast<String, dynamic>();
              icons[name] = SpriteIcon(
                atlas: atlas,
                x: (fields['x'] as num?)?.toDouble() ?? 0,
                y: (fields['y'] as num?)?.toDouble() ?? 0,
                width: (fields['width'] as num?)?.toDouble() ?? 0,
                height: (fields['height'] as num?)?.toDouble() ?? 0,
                pixelRatio: (fields['pixelRatio'] as num?)?.toDouble() ?? 1,
                sdf: fields['sdf'] == true,
              );
            });
            debugPrint(
              '[SpriteAtlas] loaded ${icons.length} icons '
              '(${suffix.isEmpty ? '1x' : suffix})',
            );

            return SpriteAtlas._(icons, atlas);
          } catch (_) {
            atlas.dispose();
            rethrow;
          }
        } catch (_) {
          // Try the next resolution variant.
        }
      }
      return null;
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
    _image.dispose();
  }

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

/// Draws an icon cropped from a sprite sheet.
///
/// A tint is applied only when [SpriteIcon.sdf] is true.
class SpriteIconWidget extends StatelessWidget {
  /// Icon to draw.
  final SpriteIcon icon;

  /// Display scale applied to [SpriteIcon.displaySize].
  final double scale;

  /// Opacity applied while drawing the icon.
  final double opacity;

  /// Color applied to signed distance field icons.
  final Color? tint;

  const SpriteIconWidget({
    super.key,
    required this.icon,
    this.scale = 1.0,
    this.opacity = 1.0,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final size = icon.displaySize * scale;

    return CustomPaint(
      size: size,
      painter: _SpritePainter(icon, opacity, icon.sdf ? tint : null),
    );
  }
}

class _SpritePainter extends CustomPainter {
  final SpriteIcon icon;
  final double opacity;
  final Color? tint;

  _SpritePainter(this.icon, this.opacity, this.tint);

  @override
  void paint(Canvas canvas, Size size) {
    final colors = spritePaintColors(opacity, tint);
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = colors.imageColor;
    if (colors.filterColor != null) {
      paint.colorFilter = ColorFilter.mode(
        colors.filterColor!,
        BlendMode.srcIn,
      );
    }
    canvas.drawImageRect(
      icon.atlas,
      Rect.fromLTWH(icon.x, icon.y, icon.width, icon.height),
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpritePainter old) =>
      old.icon != icon || old.opacity != opacity || old.tint != tint;
}
