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

  mutating func readFixedLiteralLengthSymbol() throws(BitReaderError) -> UInt32 {
    var code: UInt32 = 0

    for bitCount in 1...9 {
      let bit = try readBits(1)
      code = (code << 1) | bit

      if bitCount >= 7 {
        switch (bitCount, code) {
        case (8, 198...199): throw .forbiddenSymbol
        case (7, 0...23): return 256 + code
        case (8, 48...191): return code - 48
        case (8, 192...197): return 280 + code - 192
        case (9, 400...511): return 144 + code - 400
        default: continue
        }
      }
    }
    throw .invalid
  }

  /// Reads the extra bits for an already-decoded length symbol.
  mutating func readMatchLength(symbol code: UInt32) throws(BitReaderError) -> UInt32 {
    switch code {
    case 257...264: return code - 254
    case 265: return 11 + (try readBits(1))
    case 266: return 13 + (try readBits(1))
    case 267: return 15 + (try readBits(1))
    case 268: return 17 + (try readBits(1))
    case 269: return 19 + (try readBits(2))
    case 270: return 23 + (try readBits(2))
    case 271: return 27 + (try readBits(2))
    case 272: return 31 + (try readBits(2))
    case 273: return 35 + (try readBits(3))
    case 274: return 43 + (try readBits(3))
    case 275: return 51 + (try readBits(3))
    case 276: return 59 + (try readBits(3))
    case 277: return 67 + (try readBits(4))
    case 278: return 83 + (try readBits(4))
    case 279: return 99 + (try readBits(4))
    case 280: return 115 + (try readBits(4))
    case 281: return 131 + (try readBits(5))
    case 282: return 163 + (try readBits(5))
    case 283: return 195 + (try readBits(5))
    case 284: return 227 + (try readBits(5))
    case 285: return 258
    default: throw .invalid
    }
  }

  mutating func readFixedMatchDistance() throws(BitReaderError) -> UInt32 {
    var code: UInt32 = 0

    for _ in 0..<5 {
      let bit = try readBits(1)
      code = (code << 1) | bit
    }
    switch code {
    case 0...3: return code + 1
    case 4: return 5 + (try readBits(1))
    case 5: return 7 + (try readBits(1))
    case 6: return 9 + (try readBits(2))
    case 7: return 13 + (try readBits(2))
    case 8: return 17 + (try readBits(3))
    case 9: return 25 + (try readBits(3))
    case 10: return 33 + (try readBits(4))
    case 11: return 49 + (try readBits(4))
    case 12: return 65 + (try readBits(5))
    case 13: return 97 + (try readBits(5))
    case 14: return 129 + (try readBits(6))
    case 15: return 193 + (try readBits(6))
    case 16: return 257 + (try readBits(7))
    case 17: return 385 + (try readBits(7))
    case 18: return 513 + (try readBits(8))
    case 19: return 769 + (try readBits(8))
    case 20: return 1025 + (try readBits(9))
    case 21: return 1537 + (try readBits(9))
    case 22: return 2049 + (try readBits(10))
    case 23: return 3073 + (try readBits(10))
    case 24: return 4097 + (try readBits(11))
    case 25: return 6145 + (try readBits(11))
    case 26: return 8193 + (try readBits(12))
    case 27: return 12289 + (try readBits(12))
    case 28: return 16385 + (try readBits(13))
    case 29: return 24577 + (try readBits(13))
    default: throw .forbiddenSymbol
    }
  }

  mutating func alignToByte() {
    if bitOffset != 0 {
      bitOffset = 0
      byteOffset += 1
    }
  }

  mutating func parseheader() throws(BitReaderError) -> BlockHeader {
    var header = try readBits(3)
    let isLastByte = header & 1 == 1
    header = header >> 1
    let bType: BType
    switch header {
    case 0:
      bType = .stored
    case 1:
      bType = .fixedHuffman
    case 2:
      bType = .dynamicHuffman
    default:
      throw .invalid
    }
    return BlockHeader(bType: bType, isLastByte: isLastByte)
  }

  mutating func parseLenNLen() throws(BitReaderError) -> (len: UInt16, nlen: UInt16) {
    alignToByte()
    let bytes = try readBits(32)
    let len = UInt16(bytes & UInt32(UInt16.max))
    let nlen = UInt16(bytes >> 16)
    guard len ^ nlen == UInt16.max else {
      throw .invalid
    }
    return (len, nlen)
  }
}

/// Errors reported while reading and decompressing a DEFLATE stream.
public enum BitReaderError: Error {
  case invalidBitCount
  case unexpectedEndOfInput
  case invalid
  case forbiddenSymbol
  case unsupportedBlockType
}
