// Guards the shape of the package's public surface.
//
// A file under lib/src is private by convention, but only until something the
// barrel exports re-exports it: `export` is transitive, so one such line makes
// every public declaration in the target part of the API. That is how a dozen
// internal helpers became public without anyone deciding to publish them.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _barrelPath = 'lib/maplibre_flutter_gpu.dart';

/// Paths the barrel exports, as written in the export directives.
List<String> _barrelExports() {
  final source = File(_barrelPath).readAsStringSync();

  return RegExp(r"export '([^']+)'")
      .allMatches(source)
      .map((match) => 'lib/${match.group(1)!}')
      .toList(growable: false);
}

void main() {
  test('the barrel exports only files that exist', () {
    final exports = _barrelExports();
    expect(exports, isNotEmpty);
    for (final path in exports) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: '$_barrelPath exports a missing file: $path',
      );
    }
  });

  test('no publicly exported file re-exports another source file', () {
    // Re-exporting is not forbidden in general. It is only forbidden from a
    // file the barrel exports, where it silently widens the public API.
    for (final path in _barrelExports()) {
      final source = File(path).readAsStringSync();
      final reExports = RegExp(
        r"^export '([^']+)'",
        multiLine: true,
      ).allMatches(source).map((match) => match.group(1)!).toList();
      expect(
        reExports,
        isEmpty,
        reason:
            '$path is exported from $_barrelPath, so its exports of '
            '${reExports.join(', ')} are public too. Export them from the '
            'barrel deliberately, or let callers import lib/src directly.',
      );
    }
  });

  test('internal helpers do not carry a redundant package prefix', () {
    // Inside lib/src the library name already scopes every declaration, so a
    // `maplibre` prefix on a helper signals "public API" where none exists.
    // The exceptions are declarations that name MapLibre the upstream project.
    final offenders = <String>[];
    for (final entity in Directory('lib/src').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final matches = RegExp(
        r'^(?:[A-Za-z_][\w<>?, .]*\s+)?(maplibre[A-Z]\w*)\s*[({=]',
        multiLine: true,
      ).allMatches(entity.readAsStringSync());
      for (final match in matches) {
        offenders.add('${entity.path}: ${match.group(1)}');
      }
    }
    expect(offenders, isEmpty);
  });
}
