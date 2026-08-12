import 'package:flutter_test/flutter_test.dart';

import '../tool/ci/check_coverage.dart';

void main() {
  test('parses one passing LCOV record', () {
    final summary = parseLcov('''
SF:lib/example.dart
LF:10
LH:8
end_of_record
''');

    expect(summary.linesFound, 10);
    expect(summary.linesHit, 8);
    expect(summary.percentage, 80);
  });

  test('aggregates records before evaluating coverage', () {
    final summary = parseLcov('''
SF:lib/first.dart
LF:10
LH:4
end_of_record
SF:lib/second.dart
LF:30
LH:26
end_of_record
''');

    expect(summary.linesFound, 40);
    expect(summary.linesHit, 30);
    expect(summary.percentage, 75);
  });

  test('reports coverage below a proposed threshold', () {
    final summary = parseLcov('LF:5\nLH:2\nend_of_record\n');

    expect(meetsCoverageMinimum(summary, parseMinimumCoverage('40')), isTrue);
    expect(
      meetsCoverageMinimum(summary, parseMinimumCoverage('40.01')),
      isFalse,
    );
  });

  test('rejects malformed and inconsistent records', () {
    expect(() => parseLcov('LF:many\nLH:1\n'), throwsFormatException);
    expect(() => parseLcov('LF:1\nLH:2\n'), throwsFormatException);
    expect(() => parseLcov('LF:1\n'), throwsFormatException);
    expect(() => parseLcov('LF:0\nLH:0\n'), throwsFormatException);
  });

  test('minimum coverage must be finite and within range', () {
    expect(parseMinimumCoverage('40'), 40);
    expect(parseMinimumCoverage('40.5'), 40.5);
    for (final value in <String>['', '-1', '101', 'NaN', 'Infinity']) {
      expect(
        () => parseMinimumCoverage(value),
        throwsFormatException,
        reason: value,
      );
    }
  });
}
