import 'dart:io';

/// Aggregated line coverage from an LCOV report.
final class CoverageSummary {
  const new({required this.linesFound, required this.linesHit});

  /// Number of executable lines reported by LCOV.
  final int linesFound;

  /// Number of executable lines reached by tests.
  final int linesHit;

  /// Percentage of executable lines reached by tests.
  double get percentage => linesHit * 100 / linesFound;
}

/// Parses and validates LCOV `LF` and `LH` records.
CoverageSummary parseLcov(String contents) {
  var totalFound = 0;
  var totalHit = 0;
  int? recordFound;
  int? recordHit;

  void finishRecord() {
    if (recordFound == null && recordHit == null) return;
    if (recordFound == null || recordHit == null) {
      throw const FormatException('Each LCOV record must contain LF and LH.');
    }
    if (recordHit! > recordFound!) {
      throw const FormatException('LCOV lines hit cannot exceed lines found.');
    }
    totalFound += recordFound!;
    totalHit += recordHit!;
    recordFound = null;
    recordHit = null;
  }

  final lines = contents.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index].trim();
    if (line == 'end_of_record') {
      finishRecord();
      continue;
    }
    if (line.startsWith('LF:')) {
      if (recordFound != null) {
        throw FormatException('Duplicate LF at line ${index + 1}.');
      }
      recordFound = _parseCount(line.substring(3), 'LF', index + 1);
    } else if (line.startsWith('LH:')) {
      if (recordHit != null) {
        throw FormatException('Duplicate LH at line ${index + 1}.');
      }
      recordHit = _parseCount(line.substring(3), 'LH', index + 1);
    }
  }
  finishRecord();

  if (totalFound == 0) {
    throw const FormatException('LCOV report contains no executable lines.');
  }

  return .new(linesFound: totalFound, linesHit: totalHit);
}

/// Parses a minimum line coverage percentage in the inclusive range 0 to 100.
double parseMinimumCoverage(String value) {
  final minimum = double.tryParse(value);
  if (minimum == null || !minimum.isFinite || minimum < 0 || minimum > 100) {
    throw FormatException('Invalid minimum coverage: $value');
  }

  return minimum;
}

/// Whether [summary] reaches [minimum] percent line coverage.
bool meetsCoverageMinimum(CoverageSummary summary, double minimum) =>
    summary.percentage >= minimum;

int _parseCount(String value, String field, int lineNumber) {
  final count = int.tryParse(value);
  if (count == null || count < 0) {
    throw FormatException('Invalid $field count at line $lineNumber.');
  }

  return count;
}

({String lcovPath, double minimum}) _parseArguments(List<String> arguments) {
  String? lcovPath;
  double? minimum;

  for (var index = 0; index < arguments.length; index += 1) {
    final option = arguments[index];
    if (index + 1 >= arguments.length) {
      throw FormatException('Missing value for $option.');
    }
    final value = arguments[index + 1];
    switch (option) {
      case '--lcov':
        if (lcovPath != null || value.isEmpty) {
          throw const FormatException('Invalid --lcov option.');
        }
        lcovPath = value;
      case '--minimum':
        if (minimum != null) {
          throw const FormatException('Duplicate --minimum option.');
        }
        minimum = parseMinimumCoverage(value);
      default:
        throw FormatException('Unknown option: $option');
    }
    index += 1;
  }

  if (lcovPath == null || minimum == null) {
    throw const FormatException('--lcov and --minimum are required.');
  }

  return (lcovPath: lcovPath, minimum: minimum);
}

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseArguments(arguments);
    final report = File(options.lcovPath);
    if (!await report.exists()) {
      throw FileSystemException('LCOV report does not exist', report.path);
    }
    final summary = parseLcov(await report.readAsString());
    final percentage = summary.percentage;
    stdout.writeln(
      'Line coverage ${percentage.toStringAsFixed(2)}% '
      '(${summary.linesHit}/${summary.linesFound}), '
      'minimum ${options.minimum.toStringAsFixed(2)}%.',
    );
    if (!meetsCoverageMinimum(summary, options.minimum)) {
      stderr.writeln('Line coverage is below the required minimum.');
      exitCode = 1;
    }
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 66;
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(
        'Usage: dart run tool/ci/check_coverage.dart '
        '--lcov <path> --minimum <0..100>',
      );
    exitCode = 64;
  }
}
