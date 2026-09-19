import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('cached buffers keep a thirty-second reuse window', () {
    expect(gpuVertexUnusedRetentionFrames(ShaderType.fill), 1800);
    expect(gpuVertexUnusedRetentionFrames(ShaderType.fillOutline), 1800);
    expect(gpuVertexUnusedRetentionFrames(ShaderType.line), 1800);
    expect(gpuVertexUnusedRetentionFrames(ShaderType.lineSDF), 1800);
    expect(gpuVertexUnusedRetentionFrames(ShaderType.fillExtrusion), 1800);
    expect(gpuIndexUnusedRetentionFrames(), 1800);
    expect(gpuIndexUnusedRetentionFrames(isFillExtrusion: true), 1800);
  });

  test('generic expiry helper keeps its 60-frame default', () {
    expect(
      gpuCacheEntryExpiryReason(frame: 69, lastUsed: 10, superseded: false),
      isNull,
    );
    expect(
      gpuCacheEntryExpiryReason(frame: 70, lastUsed: 10, superseded: false),
      GpuCacheExpiryReason.unused,
    );
  });

  test('superseded generations still retire after frames in flight', () {
    expect(
      gpuCacheEntryExpiryReason(
        frame: 13,
        lastUsed: 10,
        superseded: true,
        unusedRetentionFrames: 1800,
      ),
      isNull,
    );
    expect(
      gpuCacheEntryExpiryReason(
        frame: 14,
        lastUsed: 10,
        superseded: true,
        unusedRetentionFrames: 1800,
      ),
      GpuCacheExpiryReason.superseded,
    );
  });
}
