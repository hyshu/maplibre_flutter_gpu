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

/// One source-to-destination slice used to draw a stretchable sprite axis.
typedef SpriteAxisSegment = ({
  double sourceStart,
  double sourceEnd,
  double destStart,
  double destEnd,
});

/// Maps one sprite axis while preserving fixed pixels around its content area.
@visibleForTesting
List<SpriteAxisSegment> spriteAxisSegments({
  required double sourceExtent,
  required List<(double, double)> stretches,
  required double destExtent,
  required double pixelRatio,
  required double scale,
  double? contentStart,
  double? contentEnd,
}) {
  if (sourceExtent <= 0 || destExtent <= 0) {
    return [
      (
        sourceStart: 0,
        sourceEnd: sourceExtent,
        destStart: 0,
        destEnd: destExtent,
      ),
    ];
  }
  final ranges = <(double, double)>[];
  var lastEnd = 0.0;
  for (final stretch in stretches) {
    if (stretch.$1 < lastEnd ||
        stretch.$1 < 0 ||
        stretch.$2 <= stretch.$1 ||
        stretch.$2 > sourceExtent) {
      continue;
    }
    ranges.add(stretch);
    lastEnd = stretch.$2;
  }
  final hasContent =
      contentStart != null &&
      contentEnd != null &&
      contentStart >= 0 &&
      contentEnd > contentStart &&
      contentEnd <= sourceExtent;
  if (ranges.isEmpty && !hasContent) {
    return [
      (
        sourceStart: 0,
        sourceEnd: sourceExtent,
        destStart: 0,
        destEnd: destExtent,
      ),
    ];
  }
  if (ranges.isEmpty) ranges.add((0, sourceExtent));

  double stretchLength(double start, double end) {
    var result = 0.0;
    for (final range in ranges) {
      final overlapStart = start > range.$1 ? start : range.$1;
      final overlapEnd = end < range.$2 ? end : range.$2;
      if (overlapEnd > overlapStart) result += overlapEnd - overlapStart;
    }

    return result;
  }

  final safePixelRatio = pixelRatio.isFinite && pixelRatio > 0
      ? pixelRatio
      : 1.0;
  final contentFrom = hasContent ? contentStart : 0.0;
  final contentTo = hasContent ? contentEnd : sourceExtent;
  final totalStretch = stretchLength(0, sourceExtent);
  final stretchBeforeContent = stretchLength(0, contentFrom);
  final contentStretch = stretchLength(contentFrom, contentTo);
  final contentLength = contentTo - contentFrom;
  final contentFixed = contentLength - contentStretch;
  final fixedBeforeContent = contentFrom - stretchBeforeContent;
  if (totalStretch <= 0 || contentStretch <= 0) {
    return [
      (
        sourceStart: 0,
        sourceEnd: sourceExtent,
        destStart: 0,
        destEnd: destExtent,
      ),
    ];
  }

  // MapLibre keeps fixed sprite pixels at their intrinsic logical size. The
  // stretch coordinate supplies the fitted extent, while the pixel offset
  // compensates fixed cuts both inside and outside the content rectangle.
  double destination(double source) {
    final stretch = stretchLength(0, source);
    final fixed = source - stretch;
    final fitted =
        destExtent * (stretch - stretchBeforeContent) / contentStretch;
    final pixelOffset =
        (fixed - fixedBeforeContent - contentFixed * stretch / totalStretch) /
        safePixelRatio;

    return fitted + pixelOffset;
  }

  final boundaries = <double>{0, sourceExtent};
  for (final range in ranges) {
    boundaries
      ..add(range.$1)
      ..add(range.$2);
  }
  if (hasContent) {
    boundaries
      ..add(contentStart)
      ..add(contentEnd);
  }
  final sorted = boundaries.toList()..sort();

  return [
    for (var index = 0; index < sorted.length - 1; index += 1)
      (
        sourceStart: sorted[index],
        sourceEnd: sorted[index + 1],
        destStart: destination(sorted[index]),
        destEnd: destination(sorted[index + 1]),
      ),
  ];
}

/// Aspect-ratio constraint applied to an icon-text-fit content rectangle.
enum SpriteTextFit {
  /// The content may grow or shrink independently on this axis.
  stretchOrShrink,

  /// The content may grow but preserves its minimum fixed-pixel extent.
  stretchOnly,

  /// The other axis determines this axis from the content aspect ratio.
  proportional,
}

@visibleForTesting
/// Evaluates one antialiased edge of a signed distance field.
double spriteSdfCoverage(double distance, double edge, double gamma) {
  if (!distance.isFinite || !edge.isFinite || !gamma.isFinite) return 0;
  if (gamma <= 0) return distance >= edge ? 1 : 0;
  final t = ((distance - (edge - gamma)) / (gamma * 2)).clamp(0.0, 1.0);

  return t * t * (3 - 2 * t);
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
class const SpriteIcon({
  /// Image containing this icon.
  required final ui.Image atlas,

  /// Horizontal offset of the icon in atlas pixels.
  required final double x,

  /// Vertical offset of the icon in atlas pixels.
  required final double y,

  /// Width of the icon in atlas pixels.
  required final double width,

  /// Height of the icon in atlas pixels.
  required final double height,

  /// Ratio between atlas pixels and logical pixels.
  required final double pixelRatio,

  /// Whether the icon contains signed distance field data.
  final bool sdf = false,

  /// Horizontal source ranges that may stretch for icon-text-fit.
  ///
  /// Values use pixels relative to this icon's source rectangle.
  final List<(double, double)> stretchX = const [],

  /// Vertical source ranges that may stretch for icon-text-fit.
  ///
  /// Values use pixels relative to this icon's source rectangle.
  final List<(double, double)> stretchY = const [],

  /// Source rectangle that icon-text-fit maps to the shaped text bounds.
  final Rect? content,

  /// Horizontal constraint applied before mapping [content].
  final SpriteTextFit? textFitWidth,

  /// Vertical constraint applied before mapping [content].
  final SpriteTextFit? textFitHeight,
}) {
  /// Logical display size after applying [pixelRatio].
  Size get displaySize => .new(width / pixelRatio, height / pixelRatio);

  /// Applies sprite-level proportional constraints to fitted content bounds.
  Size fittedContentSize(Size requested) {
    final contentRect = content;
    final widthFit = textFitWidth;
    final heightFit = textFitHeight;
    var result = requested;
    if (contentRect != null && widthFit != null && heightFit != null) {
      final contentAspectRatio = contentRect.width / contentRect.height;
      final requestedAspectRatio = requested.width / requested.height;
      if (heightFit == .proportional &&
          ((widthFit == .stretchOnly &&
                  requestedAspectRatio < contentAspectRatio) ||
              widthFit == .proportional)) {
        result = .new(
          (requested.height * contentAspectRatio).ceilToDouble(),
          requested.height,
        );
      } else if (widthFit == .proportional &&
          heightFit == .stretchOnly &&
          requestedAspectRatio > contentAspectRatio) {
        result = .new(
          requested.width,
          (requested.width / contentAspectRatio).ceilToDouble(),
        );
      }
    }
    return result;
  }

  /// Smallest fitted extent that preserves every fixed source pixel.
  Size get minimumFittedContentSize {
    final fittedContent = content ?? Rect.fromLTWH(0, 0, width, height);
    final safePixelRatio = pixelRatio.isFinite && pixelRatio > 0
        ? pixelRatio
        : 1.0;

    return .new(
      _fixedContentExtent(fittedContent.left, fittedContent.right, stretchX) /
          safePixelRatio,
      _fixedContentExtent(fittedContent.top, fittedContent.bottom, stretchY) /
          safePixelRatio,
    );
  }

  static double _fixedContentExtent(
    double start,
    double end,
    List<(double, double)> stretches,
  ) {
    if (stretches.isEmpty) return 0;
    var stretchExtent = 0.0;
    for (final stretch in stretches) {
      final overlapStart = math.max(start, stretch.$1);
      final overlapEnd = math.min(end, stretch.$2);
      if (overlapEnd > overlapStart) stretchExtent += overlapEnd - overlapStart;
    }

    return math.max(0, end - start - stretchExtent);
  }
}

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

/// Draws an icon cropped from a sprite sheet.
///
/// A tint is applied only when [SpriteIcon.sdf] is true.
class const SpriteIconWidget({
  super.key,

  /// Icon to draw.
  required final SpriteIcon icon,

  /// Display scale applied to [SpriteIcon.displaySize].
  final double scale = 1.0,

  /// Opacity applied while drawing the icon.
  ///
  /// Values at or below zero retain the icon's layout size without creating a
  /// painter.
  final double opacity = 1.0,

  /// Color applied to signed distance field icons.
  final Color? tint,

  /// Target display size used by icon-text-fit.
  ///
  /// For sprites with [SpriteIcon.content], this size describes that content
  /// rectangle and fixed borders paint outside it. A null value preserves the
  /// sprite's intrinsic aspect ratio and [scale].
  final Size? fitSize,

  /// Whether [fitSize] already includes sprite proportional constraints.
  final bool fitSizeConstrained = false,

  /// Halo color applied to signed distance field icons.
  final Color? haloColor,

  /// Halo width in logical pixels.
  final double haloWidth = 0,

  /// Halo blur radius in logical pixels.
  final double haloBlur = 0,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final naturalSize = icon.displaySize * scale;
    final requestedSize = fitSize;
    final usesTextFit =
        requestedSize != null &&
        requestedSize.width.isFinite &&
        requestedSize.height.isFinite &&
        requestedSize.width > 0 &&
        requestedSize.height > 0;
    var size = usesTextFit
        ? fitSizeConstrained
              ? requestedSize
              : icon.fittedContentSize(requestedSize)
        : naturalSize;
    if (usesTextFit) {
      final minimum = icon.minimumFittedContentSize;
      size = Size(
        math.max(size.width, minimum.width),
        math.max(size.height, minimum.height),
      );
    }
    if (opacity <= 0) return SizedBox.fromSize(size: size);

    return CustomPaint(
      size: size,
      painter: _SpritePainter(
        icon,
        opacity,
        icon.sdf ? tint : null,
        scale,
        icon.sdf ? haloColor : null,
        haloWidth,
        haloBlur,
        MediaQuery.devicePixelRatioOf(context),
        usesTextFit,
      ),
    );
  }
}

class _SpritePainter(
  final SpriteIcon icon,
  final double opacity,
  final Color? tint,
  final double scale,
  final Color? haloColor,
  final double haloWidth,
  final double haloBlur,
  final double devicePixelRatio,
  final bool usesTextFit,
) extends CustomPainter {
  Size? _cachedSegmentSize;
  List<({Rect source, Rect destination})>? _cachedSegments;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final segments = _segmentsFor(size);
    if (icon.sdf) {
      _paintSdf(canvas, segments, tint ?? const Color(0xFF000000));

      return;
    }
    final colors = spritePaintColors(opacity, tint);
    final paint = Paint()
      ..filterQuality = .medium
      ..color = colors.imageColor;
    if (colors.filterColor != null) {
      paint.colorFilter = .mode(
        colors.filterColor!,
        .srcIn,
      );
    }
    _drawSprite(canvas, segments, paint);
  }

  void _paintSdf(
    Canvas canvas,
    List<({Rect source, Rect destination})> segments,
    Color fillColor,
  ) {
    final effectiveScale = scale.isFinite && scale > 0 ? scale : 1.0;
    final dpr = devicePixelRatio.isFinite && devicePixelRatio > 0
        ? devicePixelRatio
        : 1.0;
    final fillGamma = 0.105 / (effectiveScale * dpr);
    final haloGamma =
        (haloBlur.clamp(0.0, double.infinity) * 1.19 / 8 + 0.105) /
        (effectiveScale * dpr);
    final clampedOpacity = opacity.clamp(0.0, 1.0);
    final halo = haloColor;
    if (halo != null && halo.a > 0 && haloWidth > 0) {
      final haloEdge =
          (6 - haloWidth.clamp(0.0, double.infinity) / effectiveScale) / 8;
      canvas.saveLayer(
        null,
        Paint()
          ..color = const Color(0xFFFFFFFF)
              .withValues(alpha: clampedOpacity * halo.a),
      );
      _drawSprite(canvas, segments, _sdfPaint(halo, haloEdge, haloGamma));
      _drawSprite(
        canvas,
        segments,
        _sdfPaint(
          const Color(0xFFFFFFFF),
          0.75,
          haloGamma,
          blendMode: .dstOut,
        ),
      );
      canvas.restore();
    }
    final fillOpacity = clampedOpacity * fillColor.a;
    if (fillOpacity <= 0) return;
    if (fillOpacity < 1) {
      canvas.saveLayer(
        null,
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: fillOpacity),
      );
    }
    _drawSprite(canvas, segments, _sdfPaint(fillColor, 0.75, fillGamma));
    if (fillOpacity < 1) canvas.restore();
  }

  Paint _sdfPaint(
    Color color,
    double edge,
    double gamma, {
    BlendMode blendMode = .srcOver,
  }) {
    final safeGamma = gamma.clamp(1 / 255, 1.0);
    final slope = 1 / (safeGamma * 2);
    final intercept = -(edge - safeGamma) * slope * 255;

    return Paint()
      ..filterQuality = .medium
      ..blendMode = blendMode
      ..colorFilter = .matrix([
        0,
        0,
        0,
        0,
        color.r * 255,
        0,
        0,
        0,
        0,
        color.g * 255,
        0,
        0,
        0,
        0,
        color.b * 255,
        0,
        0,
        0,
        slope,
        intercept,
      ]);
  }

  List<({Rect source, Rect destination})> _segmentsFor(Size size) {
    final cached = _cachedSegments;
    if (_cachedSegmentSize == size && cached != null) return cached;
    final content = usesTextFit ? icon.content : null;
    final xSegments = spriteAxisSegments(
      sourceExtent: icon.width,
      stretches: usesTextFit ? icon.stretchX : const [],
      destExtent: size.width,
      pixelRatio: icon.pixelRatio,
      scale: scale,
      contentStart: content?.left,
      contentEnd: content?.right,
    );
    final ySegments = spriteAxisSegments(
      sourceExtent: icon.height,
      stretches: usesTextFit ? icon.stretchY : const [],
      destExtent: size.height,
      pixelRatio: icon.pixelRatio,
      scale: scale,
      contentStart: content?.top,
      contentEnd: content?.bottom,
    );
    final segments = [
      for (final x in xSegments)
        for (final y in ySegments)
          (
            source: Rect.fromLTRB(
              icon.x + x.sourceStart,
              icon.y + y.sourceStart,
              icon.x + x.sourceEnd,
              icon.y + y.sourceEnd,
            ),
            destination: Rect.fromLTRB(
              x.destStart,
              y.destStart,
              x.destEnd,
              y.destEnd,
            ),
          ),
    ];
    _cachedSegmentSize = size;
    _cachedSegments = segments;

    return segments;
  }

  void _drawSprite(
    Canvas canvas,
    List<({Rect source, Rect destination})> segments,
    Paint paint,
  ) {
    for (final segment in segments) {
      canvas.drawImageRect(
        icon.atlas,
        segment.source,
        segment.destination,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpritePainter old) =>
      old.icon != icon ||
      old.opacity != opacity ||
      old.tint != tint ||
      old.scale != scale ||
      old.haloColor != haloColor ||
      old.haloWidth != haloWidth ||
      old.haloBlur != haloBlur ||
      old.devicePixelRatio != devicePixelRatio ||
      old.usesTextFit != usesTextFit;
}
