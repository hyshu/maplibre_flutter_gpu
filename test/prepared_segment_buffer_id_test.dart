import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

void main() {
  test('GPU-ready bridge exports stable per-segment buffer ids', () {
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
      2,
      reason: 'fill-extrusion and line must both publish stable segment ids',
    );
    expect(source, contains('trimPreparedBufferIds(session);'));
    expect(
      source,
      isNot(contains('command.bufferVersion =')),
      reason: 'prepared segment ids must preserve generation semantics',
    );
  });
}
