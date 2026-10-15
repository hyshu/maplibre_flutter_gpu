import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../fill_extrusion/fill_extrusion_geometry.dart';
import '../fill_extrusion/fill_extrusion_renderer.dart';
import '../native/abi_generated.dart';
import '../native/command_payload.dart';
import '../native/draw_command.dart';
import 'resource_cache.dart';
import 'draw_entry.dart';
import 'pipeline_registry.dart';

/// The customization applied to one fill-extrusion draw entry.
///
/// Entries keep this between native frames so a renderer notification can be
/// applied to the current frame without reading native memory again.
final class FillExtrusionEntryCustomization {
  FillExtrusionEntryCustomization._(this._layer, this._tile);

  final _FillExtrusionLayerState _layer;
  final _FillExtrusionTileState _tile;
}

/// Applies application fill-extrusion renderers to decoded draw entries.
///
/// Tiles are recognized by the feature parts that native exports with each
/// fill-extrusion command. Native vertices and indices are copied once per
/// tile geometry, so visibility and material changes can be applied while
/// replaying a frame. Listeners are notified when a renderer requests a
/// repaint.
final class FillExtrusionCustomizer extends ChangeNotifier {
  /// Creates a customizer that draws materials with the map's [shaders].
  FillExtrusionCustomizer(gpu.ShaderLibrary shaders)
    : _createPipeline = ((material, dataDriven, custom) =>
          _createMaterialPipeline(shaders, material, dataDriven, custom)),
      _uploadBuffer = _upload;

  /// Creates a customizer with resource factories that do not require a GPU.
  @visibleForTesting
  FillExtrusionCustomizer.withResources({
    required this._createPipeline,
    required this._uploadBuffer,
  });

  /// Frames a tile may go unrendered before its renderer is told it was
  /// removed.
  static const retainedFrames = 120;

  final ResolvedPipeline? Function(FillExtrusionMaterial, bool, bool)
  _createPipeline;
  final GpuBufferEntry Function(Uint8List) _uploadBuffer;
  FillExtrusionRendererBuilder? _builder;
  final _layers = <String, _FillExtrusionLayerSelection>{};
  var _frame = 0;
  var _layerRevision = 0;
  var _repaintRevision = 0;
  var _needsReapply = false;
  var _customizedEntries = false;
  var _disposed = false;
  var _memoryBudgetBytes = 64 * 1024 * 1024;

  /// Whether a builder may customize fill-extrusion layers.
  bool get isActive => _builder != null;

  /// Whether a renderer changed since the entries were last customized.
  bool get needsReapply => _needsReapply;

  /// Monotonic revision of renderer changes that require every stratum to paint.
  int get repaintRevision => _repaintRevision;

  /// Soft limit for retained geometry and customization GPU buffers in bytes.
  ///
  /// Tiles in the current frame stay available for replay even when their
  /// combined size exceeds this limit.
  int get memoryBudgetBytes => _memoryBudgetBytes;

  /// Bytes held by geometry arrays and GPU buffers owned by this customizer.
  ///
  /// Native GPU buffers, feature metadata, pipelines, and objects retained by
  /// application renderers are excluded.
  int get retainedBytes => _layers.values.fold<int>(
    0,
    (total, selection) =>
        total +
        (selection.state?.tiles.values.fold<int>(
              0,
              (bytes, tile) => bytes + tile.retainedBytes,
            ) ??
            0),
  );

  /// Changes the byte limit and evicts the oldest tiles outside this frame.
  ///
  /// A zero budget retains only tiles needed to replay the current frame.
  void updateMemoryBudget(int bytes) {
    RangeError.checkNotNegative(bytes, 'bytes');
    _memoryBudgetBytes = bytes;
    _trimToBudget();
  }

  /// Releases tiles outside the current frame without disposing renderers.
  ///
  /// Current entries remain valid for replay. Removed tiles are decoded again
  /// and reported to their renderer if they return to view.
  void reduceMemoryUse() {
    for (final selection in _layers.values) {
      selection.state?.expireTiles(_frame);
    }
  }

  /// Sets the builder that chooses renderers for fill-extrusion layers.
  ///
  /// Layers are rebuilt when the builder changes. A layer keeps its tiles when
  /// the new builder returns the same renderer instance for it. Returns
  /// whether a renderer changed, in which case a new native frame is needed to
  /// apply it.
  bool updateBuilder(FillExtrusionRendererBuilder? value) {
    if (value == _builder) return false;
    final enabledChanged = (value == null) != (_builder == null);
    _builder = value;
    var changed = enabledChanged;
    for (final selection in _layers.values.toList()) {
      if (_selectRenderer(selection)) changed = true;
    }
    if (value == null) _layers.clear();
    if (changed) {
      _needsReapply = true;
      _repaintRevision += 1;
    }

    return changed;
  }

  /// Rebuilds every layer's renderer for a replaced style.
  void styleChanged() {
    for (final selection in _layers.values) {
      selection.state?.dispose();
    }
    _layers.clear();
    _needsReapply = true;
    _repaintRevision += 1;
  }

  /// Re-evaluates rendered layers after a style layer mutation.
  ///
  /// A selection that returns the same renderer keeps its tiles and listeners.
  void layersChanged() {
    _layerRevision += 1;
    _needsReapply = true;
    _repaintRevision += 1;
  }

  /// Customizes the fill-extrusion entries of a newly prepared native frame.
  ///
  /// [commandData] and [payload] borrow the frame's native memory, which must
  /// stay valid during the call.
  void apply(
    List<DrawEntry> entries,
    ByteData commandData,
    CommandPayloadReader payload,
  ) {
    _needsReapply = false;
    if (_builder == null && _layers.isEmpty) {
      if (_customizedEntries) {
        _customizedEntries = false;
        for (final entry in entries) {
          entry.clearFillExtrusionCustomization();
        }
      }
      return;
    }
    _frame += 1;
    _customizedEntries = true;
    for (final entry in entries) {
      entry.clearFillExtrusionCustomization();
      if (entry.shader != ShaderType.fillExtrusion ||
          entry.stencilMode == StencilModeType.clear ||
          !payload.read(commandData, entry.commandOffset) ||
          !payload.hasFillExtrusionFeatures) {
        continue;
      }
      final layerId = _layerId(payload);
      if (layerId == null) continue;
      final layer = _layerState(layerId, entry.layer);
      if (layer == null) continue;
      final tile = layer.tileFor(entry, commandData, payload, _frame);
      if (tile == null) continue;
      tile.nativeIndexBuffer = entry.indexBuffer;
      tile.nativeIndexCount = entry.indexCount;
      _customize(entry, layer, tile);
    }
    for (final selection in _layers.values) {
      selection.state?.expireTiles(_frame - retainedFrames);
    }
    _trimToBudget();
  }

  /// Applies renderer changes to entries of the current frame.
  void reapply(List<DrawEntry> entries) {
    _needsReapply = false;
    for (final entry in entries) {
      final customization = entry.fillExtrusionCustomization;
      if (customization == null) continue;
      final layer = customization._layer;
      if (layer.disposed) {
        entry.clearFillExtrusionCustomization();
        final tile = customization._tile;
        entry
          ..indexBuffer = tile.nativeIndexBuffer
          ..indexCount = tile.nativeIndexCount;
        continue;
      }
      _customize(entry, layer, customization._tile);
    }
    _trimToBudget();
  }

  void _trimToBudget() {
    var bytes = retainedBytes;
    if (bytes <= _memoryBudgetBytes) return;
    final candidates = <(_FillExtrusionLayerState, _FillExtrusionTileState)>[
      for (final selection in _layers.values)
        if (selection.state case final layer?)
          for (final tile in layer.tiles.values)
            if (tile.lastFrame < _frame) (layer, tile),
    ]..sort((a, b) => a.$2.lastFrame.compareTo(b.$2.lastFrame));
    for (final (layer, tile) in candidates) {
      if (bytes <= _memoryBudgetBytes) break;
      bytes -= tile.retainedBytes;
      layer.removeTile(tile.tile.key);
    }
  }

  void _customize(
    DrawEntry entry,
    _FillExtrusionLayerState layer,
    _FillExtrusionTileState tile,
  ) {
    tile.updateVisibility(layer, _uploadBuffer);
    final visibleBuffer = tile.visibleIndexBuffer;
    entry
      ..indexBuffer = visibleBuffer ?? tile.nativeIndexBuffer
      ..indexCount = tile.visibleIndexCount ?? tile.nativeIndexCount
      ..fillExtrusionCustomization = FillExtrusionEntryCustomization._(
        layer,
        tile,
      );
    final material = layer.materialResources(
      tile,
      _createPipeline,
      _uploadBuffer,
    );
    entry
      ..customPipeline = material?.pipeline
      ..materialVertexBuffer = material?.vertices
      ..customVertexBuffer = material?.custom;
  }

  String? _layerId(CommandPayloadReader payload) {
    final address = payload.fillExtrusionLayerIdAddress;
    final length = payload.fillExtrusionLayerIdLength;
    if (address == 0 || length == 0) return null;

    return decodeFillExtrusionId(
      Pointer<Uint8>.fromAddress(address).asTypedList(length),
    );
  }

  _FillExtrusionLayerState? _layerState(String id, int index) {
    var selection = _layers[id];
    if (selection == null) {
      selection = _FillExtrusionLayerSelection(
        FillExtrusionLayer(id: id, index: index),
      );
      _layers[id] = selection;
    } else if (selection.layer.index != index) {
      selection.layer = FillExtrusionLayer(id: id, index: index);
      selection.revision = -1;
    }
    if (selection.revision != _layerRevision) _selectRenderer(selection);

    return selection.state;
  }

  bool _selectRenderer(_FillExtrusionLayerSelection selection) {
    final builder = _builder;
    final renderer = builder == null ? null : _build(builder, selection.layer);
    selection.revision = _layerRevision;
    final previous = selection.state;
    if (identical(renderer, previous?.renderer)) return false;
    previous?.dispose();
    selection.state = renderer == null
        ? null
        : _FillExtrusionLayerState(renderer, _onRendererChanged);

    return true;
  }

  FillExtrusionRenderer? _build(
    FillExtrusionRendererBuilder builder,
    FillExtrusionLayer layer,
  ) {
    try {
      return builder(layer);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'while building a fill-extrusion renderer');

      return null;
    }
  }

  void _onRendererChanged() {
    if (_disposed) return;
    _needsReapply = true;
    _repaintRevision += 1;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final selection in _layers.values) {
      selection.state?.dispose();
    }
    _layers.clear();
    super.dispose();
  }
}

void _report(Object error, StackTrace stackTrace, String context) =>
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'maplibre_flutter_gpu',
        context: ErrorDescription(context),
      ),
    );

final class _FillExtrusionLayerSelection {
  _FillExtrusionLayerSelection(this.layer);

  FillExtrusionLayer layer;
  _FillExtrusionLayerState? state;
  var revision = -1;
}

final class _FillExtrusionLayerState {
  _FillExtrusionLayerState(this.renderer, this._onChanged) {
    _material = _readMaterial();
    renderer.repaint?.addListener(_handleRepaint);
  }

  final FillExtrusionRenderer renderer;
  final VoidCallback _onChanged;
  final tiles = <FillExtrusionTileKey, _FillExtrusionTileState>{};
  final _pipelines = <int, ResolvedPipeline?>{};
  FillExtrusionMaterial? _material;
  var revision = 0;
  var disposed = false;

  void _handleRepaint() {
    revision += 1;
    final material = _readMaterial();
    if (!identical(material, _material)) {
      _material = material;
      _pipelines.clear();
    }
    _onChanged();
  }

  FillExtrusionMaterial? _readMaterial() {
    try {
      return renderer.material;
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'while reading a fill-extrusion material');

      return null;
    }
  }

  bool isVisible(FillExtrusionPart part) {
    try {
      return renderer.isVisible(part);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'while evaluating fill-extrusion visibility');

      return true;
    }
  }

  /// Returns the tile state for [entry], decoding new geometry when needed.
  _FillExtrusionTileState? tileFor(
    DrawEntry entry,
    ByteData commandData,
    CommandPayloadReader payload,
    int frame,
  ) {
    final offset = entry.commandOffset;
    final bufferId = commandData.getUint32(
      offset + DrawCommandAbi.bufferId,
      Endian.little,
    );
    final bufferVersion = commandData.getUint32(
      offset + DrawCommandAbi.bufferVersion,
      Endian.little,
    );
    final key = FillExtrusionTileKey(
      z: payload.fillExtrusionTileZ,
      x: payload.fillExtrusionTileX,
      y: payload.fillExtrusionTileY,
      overscaledZ: payload.fillExtrusionTileOverscaledZ,
      wrap: payload.fillExtrusionTileWrap,
      segment: payload.fillExtrusionSegmentIndex,
    );
    if (payload.drawableSize < 96 || payload.propsSize < 52) return null;
    final vertexStride = commandData.getUint32(
      offset + DrawCommandAbi.vertexStride,
      Endian.little,
    );
    final dataDriven = vertexStride == fillExtrusionDataDrivenVertexStride;
    final data = payload.data;
    final heights = FillExtrusionHeights(
      base: dataDriven
          ? 0
          : data.getFloat32(payload.propsOffset + 44, Endian.little),
      height: dataDriven
          ? 0
          : data.getFloat32(payload.propsOffset + 48, Endian.little),
      baseT: dataDriven
          ? data.getFloat32(payload.drawableOffset + 88, Endian.little)
          : 0,
      heightT: dataDriven
          ? data.getFloat32(payload.drawableOffset + 92, Endian.little)
          : 0,
    );
    final metadataId = payload.fillExtrusionMetadataId;
    var state = tiles[key];
    var updated = false;
    if (state == null ||
        state.bufferId != bufferId ||
        state.bufferVersion != bufferVersion) {
      final tile = _decodeTile(key, entry, commandData, payload, heights);
      if (tile == null) return null;
      state = _FillExtrusionTileState(
        tile,
        bufferId,
        bufferVersion,
        metadataId,
      );
      tiles[key] = state;
      updated = true;
    } else if (state.metadataId != metadataId ||
        !state.tile.hasHeights(heights)) {
      final parts = state.metadataId == metadataId
          ? state.tile.parts
          : _decodeParts(key, payload);
      state.updateMetadata(
        state.tile.withMetadata(parts: parts, heights: heights),
        metadataId,
      );
      updated = true;
    }
    if (updated) {
      try {
        renderer.didAddTile(state.tile);
      } catch (error, stackTrace) {
        _report(error, stackTrace, 'while adding a fill-extrusion tile');
      }
    }
    state.lastFrame = frame;

    return state;
  }

  DecodedFillExtrusionTile? _decodeTile(
    FillExtrusionTileKey key,
    DrawEntry entry,
    ByteData commandData,
    CommandPayloadReader payload,
    FillExtrusionHeights heights,
  ) {
    final offset = entry.commandOffset;
    final vertexAddress = commandData.getUint64(
      offset + DrawCommandAbi.vertexData,
      Endian.little,
    );
    final vertexCount = commandData.getUint32(
      offset + DrawCommandAbi.vertexCount,
      Endian.little,
    );
    final vertexStride = commandData.getUint32(
      offset + DrawCommandAbi.vertexStride,
      Endian.little,
    );
    final indexAddress = commandData.getUint64(
      offset + DrawCommandAbi.indexData,
      Endian.little,
    );
    final indexCount = commandData.getUint32(
      offset + DrawCommandAbi.indexCount,
      Endian.little,
    );
    if ((vertexStride != fillExtrusionConstantVertexStride &&
            vertexStride != fillExtrusionDataDrivenVertexStride) ||
        vertexAddress == 0 ||
        indexAddress == 0) {
      return null;
    }
    final vertices = Uint8List.fromList(
      Pointer<Uint8>.fromAddress(vertexAddress)
          .asTypedList(vertexCount * vertexStride),
    );
    final indices = Uint16List.fromList(
      Pointer<Uint16>.fromAddress(indexAddress).asTypedList(indexCount),
    );

    return DecodedFillExtrusionTile(
      key: key,
      parts: _decodeParts(key, payload),
      indices: indices,
      vertexData: vertices,
      vertexStride: vertexStride,
      heights: heights,
    );
  }

  List<FillExtrusionPart> _decodeParts(
    FillExtrusionTileKey key,
    CommandPayloadReader payload,
  ) {
    final partStride = payload.fillExtrusionPartStride;
    final partCount = payload.fillExtrusionPartCount;
    final partsAddress = payload.fillExtrusionPartsAddress;

    return partsAddress == 0
        ? const <FillExtrusionPart>[]
        : parseFillExtrusionParts(
            ByteData.sublistView(
              Pointer<Uint8>.fromAddress(partsAddress)
                  .asTypedList(partCount * partStride),
            ),
            count: partCount,
            stride: partStride,
            tile: key,
            readString: (address, length) => address == 0 || length == 0
                ? ''
                : decodeFillExtrusionId(
                    Pointer<Uint8>.fromAddress(address).asTypedList(length),
                  ),
          );
  }

  /// Returns the pipeline and vertex streams for [tile], or null without a
  /// usable material.
  _MaterialResources? materialResources(
    _FillExtrusionTileState tile,
    ResolvedPipeline? Function(FillExtrusionMaterial, bool, bool)
    createPipeline,
    GpuBufferEntry Function(Uint8List) uploadBuffer,
  ) {
    final material = _material;
    if (material == null) return null;
    final dataDriven = tile.tile.isDataDriven;
    final customCount = material.customAttributeCount.clamp(0, 8);
    final variant = (dataDriven ? 1 : 0) | (customCount > 0 ? 2 : 0);
    final pipeline = _pipelines.putIfAbsent(
      variant,
      () => createPipeline(material, dataDriven, customCount > 0),
    );
    if (pipeline == null) return null;

    return tile.materialResources(
      material,
      customCount,
      pipeline,
      uploadBuffer,
    );
  }

  /// Removes tiles last rendered before [frame].
  void expireTiles(int frame) {
    if (tiles.isEmpty) return;
    final expired = [
      for (final entry in tiles.entries)
        if (entry.value.lastFrame < frame) entry.key,
    ];
    for (final key in expired) {
      removeTile(key);
    }
  }

  void removeTile(FillExtrusionTileKey key) {
    if (tiles.remove(key) == null) return;
    _didRemoveTile(key);
  }

  void _didRemoveTile(FillExtrusionTileKey key) {
    try {
      renderer.didRemoveTile(key);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'while removing a fill-extrusion tile');
    }
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    renderer.repaint?.removeListener(_handleRepaint);
    for (final key in tiles.keys) {
      _didRemoveTile(key);
    }
    tiles.clear();
    _pipelines.clear();
  }
}

final class const _MaterialResources(
  final ResolvedPipeline pipeline,
  final GpuBufferEntry vertices,
  final GpuBufferEntry? custom,
);

final class _FillExtrusionTileState {
  _FillExtrusionTileState(
    this.tile,
    this.bufferId,
    this.bufferVersion,
    this.metadataId,
  );

  DecodedFillExtrusionTile tile;
  int metadataId;
  final int bufferId;
  final int bufferVersion;
  var lastFrame = 0;
  GpuBufferEntry? nativeIndexBuffer;
  var nativeIndexCount = 0;
  GpuBufferEntry? visibleIndexBuffer;
  int? visibleIndexCount;
  int? _visibilityRevision;
  GpuBufferEntry? _materialVertices;
  FillExtrusionMaterial? _customMaterial;
  int? _customCount;
  GpuBufferEntry? _customVertices;

  int get retainedBytes =>
      tile.retainedByteLength +
      (visibleIndexBuffer?.lengthInBytes ?? 0) +
      (_materialVertices?.lengthInBytes ?? 0) +
      (_customVertices?.lengthInBytes ?? 0);

  void updateMetadata(DecodedFillExtrusionTile value, int nextMetadataId) {
    if (!tile.hasSamePartVertices(value.parts)) _materialVertices = null;
    tile = value;
    metadataId = nextMetadataId;
    _visibilityRevision = null;
    _customMaterial = null;
    _customCount = null;
    _customVertices = null;
  }

  void updateVisibility(
    _FillExtrusionLayerState layer,
    GpuBufferEntry Function(Uint8List) uploadBuffer,
  ) {
    if (_visibilityRevision == layer.revision) return;
    _visibilityRevision = layer.revision;
    final parts = tile.parts;
    final visible = [for (final part in parts) layer.isVisible(part)];
    final indices = visibleFillExtrusionIndices(tile.indices, parts, visible);
    visibleIndexCount = indices?.length;
    visibleIndexBuffer = indices == null || indices.isEmpty
        ? null
        : uploadBuffer(Uint8List.sublistView(indices));
  }

  _MaterialResources materialResources(
    FillExtrusionMaterial material,
    int customCount,
    ResolvedPipeline pipeline,
    GpuBufferEntry Function(Uint8List) uploadBuffer,
  ) {
    final vertices = _materialVertices ??= uploadBuffer(
      Uint8List.sublistView(tile.materialVertices()),
    );
    GpuBufferEntry? custom;
    if (customCount > 0) {
      if (!identical(_customMaterial, material) ||
          _customCount != customCount) {
        _customMaterial = material;
        _customCount = customCount;
        _customVertices = uploadBuffer(
          Uint8List.sublistView(
            packFillExtrusionCustomAttributes(
              _customAttributes(material),
              vertexCount: tile.vertexCount,
              count: customCount,
            ),
          ),
        );
      }
      custom = _customVertices;
    }

    return _MaterialResources(pipeline, vertices, custom);
  }

  Float32List? _customAttributes(FillExtrusionMaterial material) {
    try {
      return material.customAttributes(tile);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'while computing fill-extrusion attributes');

      return null;
    }
  }
}

ResolvedPipeline? _createMaterialPipeline(
  gpu.ShaderLibrary shaders,
  FillExtrusionMaterial material,
  bool dataDriven,
  bool custom,
) {
  final name =
      'FillExtrusionMaterial${dataDriven ? 'DD' : ''}'
      '${custom ? 'Custom' : ''}Vertex';
  try {
    final vertex = shaders[name];
    if (vertex == null) throw StateError('Shader not found: $name');
    const floatBytes = 4;
    final buffers = <gpu.VertexBuffer>[
      gpu.VertexBuffer(
        strideInBytes: (dataDriven ? 16 : 8) * floatBytes,
        attributes: [
          const gpu.VertexAttribute(
            name: 'a_position',
            format: gpu.VertexFormat.float32x4,
          ),
          const gpu.VertexAttribute(
            name: 'a_normal',
            format: gpu.VertexFormat.float32x4,
            offsetInBytes: 4 * floatBytes,
          ),
          if (dataDriven) ...const [
            gpu.VertexAttribute(
              name: 'a_base_range',
              format: gpu.VertexFormat.float32x2,
              offsetInBytes: 8 * floatBytes,
            ),
            gpu.VertexAttribute(
              name: 'a_height_range',
              format: gpu.VertexFormat.float32x2,
              offsetInBytes: 10 * floatBytes,
            ),
            gpu.VertexAttribute(
              name: 'a_color_range',
              format: gpu.VertexFormat.float32x4,
              offsetInBytes: 12 * floatBytes,
            ),
          ],
        ],
      ),
      if (custom)
        const gpu.VertexBuffer(
          strideInBytes: 8 * floatBytes,
          attributes: [
            gpu.VertexAttribute(
              name: 'a_custom0',
              format: gpu.VertexFormat.float32x4,
            ),
            gpu.VertexAttribute(
              name: 'a_custom1',
              format: gpu.VertexFormat.float32x4,
              offsetInBytes: 4 * floatBytes,
            ),
          ],
        ),
    ];

    return ResolvedPipeline(
      pipeline: gpu.gpuContext.createRenderPipeline(
        vertex,
        material.fragmentShader,
        vertexLayout: gpu.VertexLayout(buffers: buffers),
      ),
      vertexDrawable: vertex.getUniformSlot('FillExtrusionDrawableUBO'),
      vertexProps: vertex.getUniformSlot('FillExtrusionPropsUBO'),
      fillExtrusionMaterial: material,
    );
  } catch (error, stackTrace) {
    _report(error, stackTrace, 'while creating a fill-extrusion material');

    return null;
  }
}

GpuBufferEntry _upload(Uint8List bytes) => GpuBufferEntry(
  // Device buffers cannot be empty. An empty stream is never drawn.
  gpu.gpuContext.createDeviceBufferWithCopy(
    ByteData.sublistView(bytes.isEmpty ? Uint8List(4) : bytes),
  ),
  bytes.lengthInBytes,
);
