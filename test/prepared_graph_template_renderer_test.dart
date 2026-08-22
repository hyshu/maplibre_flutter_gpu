import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

void main() {
  test('renderer restores recurring topology from resource-free templates', () {
    final source = SourceFiles.renderer;

    expect(source, contains('PreparedGraphTemplateCache<Object?>'));
    expect(source, contains('capacity: 4'));
    expect(source, contains('_preparedGraphTemplates.remember('));
    expect(source, contains('.takeMatching('));
    expect(source, contains('_restorePreparedGraphTemplate('));
    expect(source, contains('_preparedGraphTemplates.clear();'));

    final restore = source.indexOf(
      '_PreparedGraphState? _restorePreparedGraphTemplate(',
    );
    expect(restore, greaterThanOrEqualTo(0));
    final restoreBody = source.substring(restore);
    expect(restoreBody, contains('_acquireDrawEntry('));
    expect(restoreBody, contains('_refreshPreparedEntries('));
    expect(restoreBody, contains('pipelineKeyFor('));
    expect(restoreBody, contains('depthPipelineKeyFor('));
    expect(restoreBody, isNot(contains('PreparedGraphTemplateCache<GpuBufferEntry')));
  });
}
