import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'kenney_mesh_data.dart';

enum MapSceneObjectKind { car, building }

class MapSceneObject {
  const new({
    required this.kind,
    required this.position,
    this.headingRadians = 0,
    this.scale = 1,
  });

  final MapSceneObjectKind kind;

  /// Geographic model anchor.
  final LatLng position;

  /// Model-forward direction, measured counterclockwise from east.
  final double headingRadians;

  /// Multiplier applied to the model's real-world size.
  final double scale;
}

/// Draws two colorless Kenney meshes in MapLibre's geographic 3D space.
class MapSceneRenderer {
  new(this._shaderLibrary);

  final gpu.ShaderLibrary _shaderLibrary;
  gpu.GpuContext? _gpuContext;
  gpu.RenderPipeline? _pipeline;
  gpu.HostBuffer? _uniforms;
  gpu.UniformSlot? _uniformSlot;
  Map<MapSceneObjectKind, _GpuMesh> _meshes = const {};

  void draw(
    MapLibreGpuRenderContext frame, {
    required List<MapSceneObject> objects,
  }) {
    final mapTransform = frame.mapTransform;
    if (objects.isEmpty || mapTransform == null) return;
    _ensureResources(frame.gpuContext);

    final uniforms = _uniforms!..reset();
    final renderPass = frame.renderPass;
    renderPass
      ..setPrimitiveType(.triangle)
      ..setColorBlendEnable(false)
      ..bindPipeline(_pipeline!);
    if (frame.hasDepthStencilAttachment) {
      renderPass
        ..setDepthWriteEnable(true)
        ..setDepthCompareOperation(.lessEqual);
    }

    for (final object in objects) {
      final mesh = _meshes[object.kind]!;
      final anchor = mapTransform.project(object.position);
      final modelSizeMeters = switch (object.kind) {
        .car => 8.0,
        .building => 28.0,
      };
      final values = ByteData.sublistView(
        Float32List.fromList([
          ...mapTransform.viewProjectionMatrix,
          anchor.x,
          anchor.y,
          anchor.pixelsPerMeter,
          object.headingRadians,
          modelSizeMeters * object.scale,
          0,
          0,
          0,
          0.28,
          0.34,
          0.38,
          1,
        ]),
      );
      final uniformView = uniforms.emplace(values);
      renderPass
        ..bindVertexBuffer(
          .new(
            mesh.vertices,
            offsetInBytes: 0,
            lengthInBytes: mesh.vertexBytes,
          ),
        )
        ..bindIndexBuffer(
          .new(
            mesh.indices,
            offsetInBytes: 0,
            lengthInBytes: mesh.indexBytes,
          ),
          .int16,
        )
        ..bindUniform(_uniformSlot!, uniformView)
        ..drawIndexed(mesh.indexCount);
    }
  }

  void _ensureResources(gpu.GpuContext context) {
    if (identical(_gpuContext, context)) return;

    final vertexShader = _shaderLibrary['OverlayVertex'];
    final fragmentShader = _shaderLibrary['OverlayFragment'];
    if (vertexShader == null || fragmentShader == null) {
      throw StateError('Overlay shaders are missing from the shader bundle');
    }

    _gpuContext = context;
    _pipeline = context.createRenderPipeline(vertexShader, fragmentShader);
    _uniforms = context.createHostBuffer(blockLengthInBytes: 8192);
    _uniformSlot = vertexShader.getUniformSlot('OverlayUniforms');
    _meshes = {
      .car: _GpuMesh.create(context, kenneySedanMesh),
      .building: _GpuMesh.create(context, kenneyBuildingMesh),
    };
  }

  void releaseReferences() {
    _meshes = const {};
    _uniformSlot = null;
    _uniforms = null;
    _pipeline = null;
    _gpuContext = null;
  }
}

class _GpuMesh {
  const new({
    required this.vertices,
    required this.indices,
    required this.vertexBytes,
    required this.indexBytes,
    required this.indexCount,
  });

  factory create(gpu.GpuContext context, KenneyMeshData data) {
    final vertices = ByteData.sublistView(Float32List.fromList(data.vertices));
    final indices = ByteData.sublistView(Uint16List.fromList(data.indices));

    return .new(
      vertices: context.createDeviceBufferWithCopy(vertices),
      indices: context.createDeviceBufferWithCopy(indices),
      vertexBytes: vertices.lengthInBytes,
      indexBytes: indices.lengthInBytes,
      indexCount: data.indices.length,
    );
  }

  final gpu.DeviceBuffer vertices;
  final gpu.DeviceBuffer indices;
  final int vertexBytes;
  final int indexBytes;
  final int indexCount;
}
