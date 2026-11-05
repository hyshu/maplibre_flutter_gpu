/// Whether an address and byte length fit the native pointer width.
///
/// Addresses retain their raw bit pattern, including Android heap tags. Empty
/// spans ignore the address. Nonempty spans reject null and unsigned wrap.
bool nativeByteSpanFits(int address, int length, {required int addressBits}) {
  if (length < 0) return false;
  if (length == 0) return true;
  if (address == 0) return false;
  if (addressBits == 32) {
    return address > 0 &&
        address <= 0xffffffff &&
        length <= 0xffffffff - address;
  }
  if (addressBits != 64) {
    throw ArgumentError.value(addressBits, 'addressBits');
  }
  return !_unsignedLess(address + length, address);
}

/// Whether two validated native byte spans overlap in unsigned address order.
bool nativeByteSpansOverlap(
  int firstAddress,
  int firstLength,
  int secondAddress,
  int secondLength,
) {
  if (firstLength == 0 || secondLength == 0) return false;

  return _unsignedLess(firstAddress, secondAddress + secondLength) &&
      _unsignedLess(secondAddress, firstAddress + firstLength);
}

bool _unsignedLess(int left, int right) =>
    (left ^ -0x8000000000000000) < (right ^ -0x8000000000000000);
