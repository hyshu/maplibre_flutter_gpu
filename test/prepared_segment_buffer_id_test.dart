import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

void main() {
  test('GPU-ready line bridge exports stable per-segment buffer ids', () {
    final source = SourceFiles.bridgeMergeOnly;

    expect(source, contains('struct PreparedBufferIds'));
    expect(source, contains('kPreparedBufferIdNamespace = 0x80000000u'));
    expect(source, contains('kPreparedBufferIdRetentionFrames = 600'));
    expect(source, contains('preparedBufferIdFor(MergeSessionState& session'));
    expect(source, contains('segmentOrdinals[sourceBufferId]++'));
    expect(
      RegExp(r'command\.bufferId = preparedBufferIdFor\(')
          .allMatches(source)
          .length,
      1,
      reason: 'only bridge-expanded line vertices need prepared segment ids',
    );
    expect(
      source,
      isNot(contains('\n    prepareFillExtrusionGpuVertices(commands);')),
    );
    expect(source, contains('trimPreparedBufferIds(session);'));
    expect(
      source,
      isNot(contains('command.bufferVersion =')),
      reason: 'prepared segment ids must preserve generation semantics',
    );
  });
}
