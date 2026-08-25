import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

void main() {
  test('native fill extrusion identity survives drawable recreation', () {
    final source = SourceFiles.commandExportDrawableOnly;

    expect(
      source,
      contains('kStableFillExtrusionBufferIdNamespace = 0xC0000000u'),
    );
    expect(source, contains('bucket->getID().id()'));
    expect(source, contains('const auto& canonical = tileID.canonical;'));
    expect(
      source,
      contains(
        'std::tie(bucketId, tileZ, tileX, tileY, layerIndex, segmentOrdinal)',
      ),
    );
    expect(
      source,
      contains(
        'state.drawableId == drawableId && state.localBufferVersion != localBufferVersion',
      ),
    );
    expect(
      source,
      contains(
        'state.vertexRevision != vertexRevision || state.indexRevision != indexRevision',
      ),
    );
    expect(source, contains('cmd.bufferId = exportedBufferId;'));
    expect(source, contains('cmd.bufferVersion = exportedBufferVersion;'));
  });
}
