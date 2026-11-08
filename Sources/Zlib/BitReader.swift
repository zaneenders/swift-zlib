/// Reads least-significant-bit-first numeric fields from borrowed input.
struct BitReader: ~Copyable, ~Escapable {
  private let input: RawSpan
  private(set) var byteOffset = 0
  private(set) var bitOffset = 0

  @_lifetime(copy input)
  init(_ input: RawSpan) {
    self.input = input
  }

  /// Reads 0...32 bits, placing the first bit read in bit 0 of the result.
  /// A failed read leaves both offsets unchanged.
  mutating func readBits(_ bitCount: Int) throws(BitReaderError) -> UInt32 {
    guard (0...32).contains(bitCount) else {
      throw .invalidBitCount
    }
    var nextByteOffset = byteOffset
    var nextBitOffset = bitOffset
    var out: UInt32 = 0

    for resultBitIndex in 0..<bitCount {
      guard nextByteOffset < input.byteCount else {
        throw .unexpectedEndOfInput
      }
      let byte = input[nextByteOffset]
      let bit = (byte >> nextBitOffset) & 1
      out |= UInt32(bit) << resultBitIndex

      nextBitOffset += 1
      if nextBitOffset == 8 {
        nextBitOffset = 0
        nextByteOffset += 1
      }
    }

    byteOffset = nextByteOffset
    bitOffset = nextBitOffset
    return out
  }
}

enum BitReaderError: Error {
  case invalidBitCount
  case unexpectedEndOfInput
}
