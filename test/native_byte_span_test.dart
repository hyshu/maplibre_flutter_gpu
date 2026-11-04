import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/byte_span.dart';

void main() {
  test(
    '64-bit spans preserve tagged pointers and signed-boundary crossings',
    () {
      const tagged = 0xb400000000001000;
      expect(tagged, isNegative);
      expect(nativeByteSpanFits(tagged, 4096, addressBits: 64), isTrue);
      expect(
        nativeByteSpanFits(0x7ffffffffffffffc, 12, addressBits: 64),
        isTrue,
      );
      expect(nativeByteSpanFits(-4, 3, addressBits: 64), isTrue);
      expect(nativeByteSpanFits(-4, 4, addressBits: 64), isFalse);
      expect(nativeByteSpanFits(0, 1, addressBits: 64), isFalse);
      expect(nativeByteSpanFits(tagged, -1, addressBits: 64), isFalse);
      expect(nativeByteSpanFits(-1, 0, addressBits: 64), isTrue);
    },
  );

  test('32-bit spans reject out-of-range addresses and unsigned wrap', () {
    expect(nativeByteSpanFits(0x80000000, 24, addressBits: 32), isTrue);
    expect(nativeByteSpanFits(0xfffffffc, 3, addressBits: 32), isTrue);
    expect(nativeByteSpanFits(0xfffffffc, 4, addressBits: 32), isFalse);
    expect(nativeByteSpanFits(0x100000000, 1, addressBits: 32), isFalse);
    expect(nativeByteSpanFits(-4, 1, addressBits: 32), isFalse);
    expect(nativeByteSpanFits(-1, 0, addressBits: 32), isTrue);
  });

  test('overlap uses unsigned order for tagged and signed-crossing spans', () {
    const tagged = 0xb400000000001000;
    expect(nativeByteSpansOverlap(tagged, 32, tagged + 16, 32), isTrue);
    expect(nativeByteSpansOverlap(tagged + 16, 32, tagged, 32), isTrue);
    expect(nativeByteSpansOverlap(tagged, 32, tagged + 32, 32), isFalse);
    expect(nativeByteSpansOverlap(0x1000, 32, tagged, 32), isFalse);
    expect(nativeByteSpansOverlap(tagged, 32, 0x1000, 32), isFalse);
    expect(
      nativeByteSpansOverlap(0x7ffffffffffffffc, 12, 0x8000000000000000, 4),
      isTrue,
    );
    expect(nativeByteSpansOverlap(tagged, 0, tagged, 32), isFalse);
  });
}
