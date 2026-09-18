part of '../resource_metrics.dart';

void _logRepackLayouts(List<GpuRepackLayoutSnapshot> layouts) {
  if (layouts.isEmpty) {
    debugPrint('[GpuRepack] none');

    return;
  }

  String megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  final values = layouts
      .take(6)
      .map((layout) {
        final name = _shaderName(layout.shader);
        final average = layout.averageMicros.toStringAsFixed(0);

        return '$name[${layout.sourceStride}>${layout.gpuStride}]='
            '${layout.count}/${megabytes(layout.inputBytes)}>'
            '${megabytes(layout.outputBytes)}/${average}us/${layout.maxMicros}us';
      })
      .join(' ');
  final omitted = layouts.length > 6 ? ' +${layouts.length - 6}more' : '';
  debugPrint('[GpuRepack] $values$omitted');
}

void _logUploadSizes(
  Map<GpuUploadSizeClass, _GpuUploadSizeTotals> vertex,
  Map<GpuUploadSizeClass, _GpuUploadSizeTotals> index,
) {
  if (vertex.isEmpty && index.isEmpty) {
    debugPrint('[GpuUploadSize] none');

    return;
  }

  String megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  String className(GpuUploadSizeClass sizeClass) => switch (sizeClass) {
    .small => '<=16K',
    .medium => '<=256K',
    .large => '>256K',
  };
  String describe(
    String prefix,
    Map<GpuUploadSizeClass, _GpuUploadSizeTotals> totals,
  ) {
    final values = <String>[];
    for (final sizeClass in GpuUploadSizeClass.values) {
      final value = totals[sizeClass];
      if (value == null || value.count == 0) continue;
      final average = (value.micros / value.count).toStringAsFixed(0);
      values.add(
        '$prefix${className(sizeClass)}=${value.count}/'
        '${megabytes(value.bytes)}/${value.micros}us/${average}us/'
        '${value.maxMicros}us',
      );
    }
    return values.join(' ');
  }

  final vertexText = describe('v', vertex);
  final indexText = describe('i', index);
  final values = [
    vertexText,
    indexText,
  ].where((value) => value.isNotEmpty).join(' ');
  debugPrint('[GpuUploadSize] $values');
}

String _shaderName(int shader) => switch (shader) {
  ShaderType.fill => 'fill',
  ShaderType.fillOutline => 'fillOutline',
  ShaderType.line => 'line',
  ShaderType.background => 'background',
  ShaderType.fillExtrusion => 'fillExtrusion',
  ShaderType.lineSDF => 'lineSDF',
  ShaderType.lineGradient => 'lineGradient',
  ShaderType.linePattern => 'linePattern',
  ShaderType.circle => 'circle',
  ShaderType.raster => 'raster',
  ShaderType.fillOutlineTriangulated => 'fillOutlineTri',
  ShaderType.clippingMask => 'clippingMask',
  ShaderType.backgroundPattern => 'backgroundPattern',
  _ => 'shader$shader',
};
