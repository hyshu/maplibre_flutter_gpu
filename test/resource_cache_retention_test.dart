import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('compact cached buffers retain longer than generic resources', () {
    expect(gpuVertexUnusedRetentionFrames(ShaderType.fill), 120);
    expect(gpuVertexUnusedRetentionFrames(ShaderType.fillOutline), 120);
    expect(gpuVertexUnusedRetentionFrames(ShaderType.line), 240);
    expect(gpuVertexUnusedRetentionFrames(ShaderType.lineSDF), 240);
    expect(gpuVertexUnusedRetentionFrames(ShaderType.fillExtrusion), 600);
    expect(gpuIndexUnusedRetentionFrames(), 120);
    expect(gpuIndexUnusedRetentionFrames(isFillExtrusion: true), 600);
  });

  test('generic expiry helper keeps its 60-frame default', () {
    expect(
      gpuCacheEntryExpired(frame: 69, lastUsed: 10, superseded: false),
      isFalse,
    );
    expect(
      gpuCacheEntryExpired(frame: 70, lastUsed: 10, superseded: false),
      isTrue,
    );
  });

  test('superseded generations still retire after frames in flight', () {
    expect(
      gpuCacheEntryExpired(
        frame: 13,
        lastUsed: 10,
        superseded: true,
        unusedRetentionFrames: 240,
      ),
      isFalse,
    );
    expect(
      gpuCacheEntryExpired(
        frame: 14,
        lastUsed: 10,
        superseded: true,
        unusedRetentionFrames: 240,
      ),
      isTrue,
    );
  });
}
