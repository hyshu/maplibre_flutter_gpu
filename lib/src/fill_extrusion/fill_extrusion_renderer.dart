import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../geo/camera.dart';
import 'fill_extrusion_units.dart';

/// A fill-extrusion layer of the loaded style.
final class const FillExtrusionLayer({
  /// The style layer ID.
  required final String id,

  /// The layer's position in the style's layer order.
  required final int index,
});

/// Chooses the renderer for a fill-extrusion style layer.
///
/// Return null to draw [layer] with MapLibre's built-in shading. The map calls
/// the builder again for each layer after the style or its layers change.
typedef FillExtrusionRendererBuilder = FillExtrusionRenderer? Function(
  FillExtrusionLayer layer,
);

/// Customizes how a fill-extrusion style layer is drawn.
///
/// The map keeps MapLibre's tile loading, depth testing, and render pass
/// planning. A renderer decides which building parts are drawn, may replace
/// their surface shading with a [material], and receives the extruded geometry
/// of each tile, for example to build collision shapes or effects.
///
/// Return a renderer from [FillExtrusionRendererBuilder]. The map calls its
/// methods synchronously while preparing frames on the UI isolate, so they
/// must be fast. Notify [repaint] after [isVisible] or [material] would return
/// a different result. The map then re-evaluates them and repaints the current
/// frame. The renderer must outlive its use by the map, which only adds and
/// removes listeners on [repaint].
abstract class FillExtrusionRenderer {
  /// Creates a renderer that re-evaluates its parts when [repaint] notifies.
  const FillExtrusionRenderer({this.repaint});

  /// Notifies the map that [isVisible] or [material] changed.
  final Listenable? repaint;

  /// Whether [part] is drawn.
  ///
  /// Hidden parts are omitted from color and depth passes. They remain part of
  /// MapLibre's feature data, so queries and other layers are unaffected.
  ///
  /// Defaults to drawing every part.
  bool isVisible(FillExtrusionPart part) => true;

  /// The shading used for this layer, or null for MapLibre's lighting.
  ///
  /// The material is read when the renderer is created and after each
  /// [repaint] notification.
  ///
  /// Defaults to null.
  FillExtrusionMaterial? get material => null;

  /// Called when the geometry of a tile segment becomes available.
  ///
  /// It is called again with the same [FillExtrusionTile.key] when the
  /// geometry, part identifiers, or evaluated heights change, including
  /// zoom-dependent heights. The tile and its arrays remain valid after the
  /// call and may be retained with their original values.
  void didAddTile(FillExtrusionTile tile) {}

  /// Called when a tile segment added earlier is no longer drawn.
  ///
  /// Tiles are removed some time after they leave the rendered set, and all
  /// tiles are removed when the style or the renderer changes.
  void didRemoveTile(FillExtrusionTileKey key) {}
}

/// Identifies the geometry of one segment of a rendered fill-extrusion tile.
///
/// [z], [x], and [y] name the source tile. MapLibre renders a source tile at
/// [overscaledZ] when zoomed beyond the source's maximum zoom, and [wrap]
/// counts copies of the world. Dense tiles split their geometry into several
/// segments, numbered by [segment].
@immutable
final class FillExtrusionTileKey {
  /// Creates a key for the given tile segment.
  const FillExtrusionTileKey({
    required this.z,
    required this.x,
    required this.y,
    required this.overscaledZ,
    required this.wrap,
    required this.segment,
  });

  final int z;
  final int x;
  final int y;
  final int overscaledZ;
  final int wrap;
  final int segment;

  @override
  bool operator ==(Object other) =>
      other is FillExtrusionTileKey &&
      other.z == z &&
      other.x == x &&
      other.y == y &&
      other.overscaledZ == overscaledZ &&
      other.wrap == wrap &&
      other.segment == segment;

  @override
  int get hashCode => Object.hash(z, x, y, overscaledZ, wrap, segment);

  @override
  String toString() =>
      'FillExtrusionTileKey($z/$x/$y, overscaledZ: $overscaledZ, '
      'wrap: $wrap, segment: $segment)';
}

/// One polygon of a building feature in a fill-extrusion tile segment.
///
/// Sources such as OpenMapTiles can merge buildings with equal attributes into
/// one multipolygon feature. Each polygon is a separate part, so applications
/// can show, hide, or replace individual buildings. A part is identified
/// across segments and overscaled renderings of its source tile by
/// [featureIndex] and [polygonIndex] together with the tile's z, x, and y.
@immutable
final class FillExtrusionPart {
  /// Creates a part description. Parts are normally created by the map.
  const FillExtrusionPart({
    required this.tile,
    required this.featureIndex,
    required this.polygonIndex,
    required this.featureId,
    required this.vertexOffset,
    required this.vertexCount,
    required this.indexOffset,
    required this.indexCount,
  });

  /// The tile segment that contains this part.
  final FillExtrusionTileKey tile;

  /// The feature's index within its source layer in the source tile.
  final int featureIndex;

  /// The polygon's index within the feature, in feature query order.
  final int polygonIndex;

  /// The feature identifier as an [int], [double], or [String], or null.
  ///
  /// Unsigned identifiers above 2^63 - 1 wrap to negative values.
  final Object? featureId;

  /// The range of this part's vertices in [FillExtrusionTile].
  final int vertexOffset;
  final int vertexCount;

  /// The range of this part's triangle indices in [FillExtrusionTile.indices].
  ///
  /// The wall triangles precede the roof triangles.
  final int indexOffset;
  final int indexCount;

  @override
  String toString() =>
      'FillExtrusionPart(feature: $featureIndex, polygon: $polygonIndex, '
      'id: $featureId)';
}

/// The extruded geometry of one fill-extrusion tile segment.
///
/// Positions use the source tile's coordinate space. x and y run from 0 to
/// [extent] across the tile with y pointing south, and z is the height in
/// meters. Each wall is a separate quad and roofs are triangulated polygons.
/// [indices] reference vertices of this tile and form triangles that are
/// counter-clockwise when seen from outside.
///
/// Heights are evaluated for the frame in which this snapshot was added.
/// Changed heights produce another snapshot through
/// [FillExtrusionRenderer.didAddTile]. The arrays are decoded on first access
/// and must not be modified.
abstract class FillExtrusionTile {
  /// Creates a tile. Tiles are normally created by the map.
  const FillExtrusionTile();

  /// The number of coordinate units across a tile.
  static const extent = 8192;

  /// The tile segment described by this geometry.
  FillExtrusionTileKey get key;

  /// Building parts in index order.
  List<FillExtrusionPart> get parts;

  /// Triangle indices for all parts.
  Uint16List get indices;

  /// The number of vertices.
  int get vertexCount;

  /// x, y, and z of each vertex, in tile units and meters.
  Float32List get positions;

  /// The horizontal outward normal of each wall vertex as x and y.
  ///
  /// Roof vertices have a zero normal.
  Float32List get normals;

  /// The distance of each vertex along its polygon ring, in tile units.
  ///
  /// A wall's vertices span the wall's length, so patterns continue around a
  /// building. The distance restarts at each ring.
  Float32List get edgeDistances;

  /// 1 for vertices on the top of the extrusion and 0 for vertices at its base.
  Uint8List get upperVertices;

  /// The geographic position of tile coordinates [x] and [y].
  ///
  /// The longitude is normalized, so copies of the world share positions.
  LatLng latLngAt(double x, double y) {
    final scale = math.pow(2, key.z).toDouble();
    final worldX = (key.x + x / extent) / scale;
    final worldY = (key.y + y / extent) / scale;
    final latitude =
        math.atan(_sinh(math.pi * (1 - 2 * worldY))) * 180 / math.pi;

    return LatLng(latitude, worldX * 360 - 180);
  }

  /// Approximate ground meters per tile unit at the tile's center latitude.
  double get metersPerUnit => fillExtrusionMetersPerUnit(key.z, key.y);
}

double _sinh(double value) => (math.exp(value) - math.exp(-value)) / 2;

/// Shades the surfaces of a fill-extrusion layer with an application shader.
///
/// The map draws the layer with its own vertex shader and [fragmentShader].
/// The vertex shader provides the outputs below. Declare the inputs the
/// fragment shader uses with matching locations and types. Declare `v_custom`
/// inputs only when [customAttributeCount] supplies them.
///
/// ```glsl
/// // MapLibre's lit color, premultiplied by the layer opacity.
/// layout(location = 0) in vec4 v_color;
/// // Tile x and y, and the height in meters.
/// layout(location = 1) in vec3 v_position;
/// // Outward surface normal, and 0 at the base to 1 at the top.
/// layout(location = 2) in vec4 v_surface;
/// // Ring distance and its meter scale, base height, and top height.
/// layout(location = 3) in vec4 v_extrusion;
/// // Application attributes, present with customAttributeCount > 0 and > 4.
/// layout(location = 4) in vec4 v_custom0;
/// layout(location = 5) in vec4 v_custom1;
/// layout(location = 0) out vec4 frag_color;
/// ```
///
/// `v_extrusion.x` is the ring distance in tile units and `v_extrusion.y`
/// converts tile units to meters at the tile's latitude. Base and top heights
/// are in meters. The output color must be premultiplied. The shader must not
/// declare a uniform binding used by the map's vertex shader, which uses
/// bindings 0 and 1.
abstract class FillExtrusionMaterial {
  /// Creates a material.
  const FillExtrusionMaterial();

  /// The fragment shader, typically from the application's shader bundle.
  gpu.Shader get fragmentShader;

  /// The number of floats per vertex returned by [customAttributes], from 0
  /// to 8.
  ///
  /// Defaults to 0.
  int get customAttributeCount => 0;

  /// Values for the `v_custom` inputs of [tile]'s vertices.
  ///
  /// The list holds [customAttributeCount] floats for each vertex of
  /// [FillExtrusionTile.vertexCount]. It is called for each tile snapshot and
  /// after the material changes. A null result supplies zeros.
  ///
  /// Defaults to null.
  Float32List? customAttributes(FillExtrusionTile tile) => null;

  /// Binds the fragment shader's own uniforms and textures.
  ///
  /// It is called before each run of draws that uses this material.
  void bind(gpu.RenderPass pass) {}
}
