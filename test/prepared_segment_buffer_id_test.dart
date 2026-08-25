import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

void main() {
  test(
    'bridge content-addresses fill extrusion geometry without ABI changes',
    () {
      final source = SourceFiles.bridgeMergeOnly;

      expect(
        source,
        contains('kContentAddressedFillExtrusionNamespace = 0xC0000000u'),
      );
      expect(source, contains('struct FillExtrusionContentSourceKey'));
      expect(source, contains('struct FillExtrusionHashFingerprint'));
      expect(source, contains('fillExtrusionStructuralIds'));
      expect(source, contains('fillExtrusionBufferIdFor('));
      expect(source, contains('fillExtrusionBufferVersionFor('));
      expect(source, contains('structural.versionContents.find(version)'));
      expect(
        source,
        contains('candidate = avalanche64(candidate + 0xc2b2ae3d27d4eb4fULL);'),
      );
      expect(source, contains('fillExtrusionContentIdentityFor('));
      expect(
        source,
        contains('hashBytes(content, command.vertexData, vertexBytes);'),
      );
      expect(
        source,
        contains('hashBytes(content, command.indexData, indexBytes);'),
      );
      expect(source, contains('command.bufferId = identity->bufferId;'));
      expect(
        source,
        contains('command.bufferVersion = identity->bufferVersion;'),
      );
      expect(
        source,
        contains('kFillExtrusionContentSourceRetentionFrames = 120'),
      );
      expect(source, contains('assignPackedFillExtrusionBufferIds(commands);'));
      expect(
        source,
        isNot(contains('\n    prepareFillExtrusionGpuVertices(commands);')),
        reason: 'packed fill-extrusion vertices must not be expanded again',
      );

      // Line expansion keeps the legacy prepared-ID namespace independently.
      expect(source, contains('struct PreparedBufferIds'));
      expect(source, contains('kPreparedBufferIdNamespace = 0x80000000u'));
      expect(
        source,
        contains('preparedBufferIdFor(MergeSessionState& session'),
      );
    },
  );
}
