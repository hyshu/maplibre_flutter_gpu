import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/symbol_table.dart';

void main() {
  group('lookUpGroup', () {
    test('reports a group whose symbols all resolve', () {
      final symbols = NativeSymbolTable();
      var ran = 0;

      expect(symbols.lookUpGroup('camera', () => ran++), isTrue);

      expect(ran, 1);
      expect(symbols.provides('camera'), isTrue);
      expect(symbols.missingFeatures, isEmpty);
    });

    test('reports a group whose lookup throws', () {
      final symbols = NativeSymbolTable();

      expect(
        symbols.lookUpGroup('camera', () => throw ArgumentError('absent')),
        isFalse,
      );

      expect(symbols.provides('camera'), isFalse);
      expect(symbols.missingFeatures, contains('camera'));
    });

    test('abandons the rest of a group after the first missing symbol', () {
      // This is the behaviour the bridge depends on: these entry points enter
      // the C ABI together, so a library that lacks the first lacks them all.
      // Resolving the remainder would expose an inconsistent subset.
      final symbols = NativeSymbolTable();
      var first = false;
      var second = false;

      symbols.lookUpGroup('camera', () {
        first = true;
        throw ArgumentError('absent');
        // ignore: dead_code
        second = true;
      });

      expect(first, isTrue);
      expect(second, isFalse, reason: 'later symbols must stay unresolved');
    });

    test('keeps groups independent of each other', () {
      final symbols = NativeSymbolTable();

      symbols.lookUpGroup('camera', () {});
      symbols.lookUpGroup('style', () => throw ArgumentError('absent'));

      expect(symbols.provides('camera'), isTrue);
      expect(symbols.provides('style'), isFalse);
      expect(symbols.missingFeatures, <String>['style']);
    });

    test('an unknown feature is not reported as provided', () {
      expect(NativeSymbolTable().provides('never-attempted'), isFalse);
    });

    test('a failed retry clears an earlier successful resolution', () {
      final symbols = NativeSymbolTable();

      expect(symbols.lookUpGroup('camera', () {}), isTrue);
      expect(
        symbols.lookUpGroup('camera', () => throw ArgumentError('absent')),
        isFalse,
      );

      expect(symbols.provides('camera'), isFalse);
      expect(symbols.missingFeatures, <String>['camera']);
    });

    test('a successful retry clears an earlier failure', () {
      final symbols = NativeSymbolTable();

      expect(
        symbols.lookUpGroup('camera', () => throw ArgumentError('absent')),
        isFalse,
      );
      expect(symbols.lookUpGroup('camera', () {}), isTrue);

      expect(symbols.provides('camera'), isTrue);
      expect(symbols.missingFeatures, isEmpty);
    });
  });

  group('requireSymbol', () {
    test('returns a resolved symbol unchanged', () {
      final symbols = NativeSymbolTable();
      int call() => 7;

      expect(
        symbols.requireSymbol<int Function()>(call, 'setStyle'),
        same(call),
      );
    });

    test('names the API the caller asked for', () {
      final symbols = NativeSymbolTable();

      expect(
        () => symbols.requireSymbol<int>(null, 'setStyle'),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            'setStyle is not supported by the loaded native library',
          ),
        ),
      );
    });

    test('names the missing feature group when one is given', () {
      final symbols = NativeSymbolTable();

      expect(
        () => symbols.requireSymbol<int>(
          null,
          'setStyle',
          feature: 'runtime style mutation',
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            'setStyle requires native support for runtime style mutation',
          ),
        ),
      );
    });
  });
}
