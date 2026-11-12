/// Reads least-significant-bit-first numeric fields from borrowed input.
struct BitReader: ~Copyable, ~Escapable {
  private let input: RawSpan
  private var bufferedBits: BufferedBits
  private(set) var byteOffset = 0
  private(set) var bitOffset = 0

  @_lifetime(copy input)
  init(_ input: RawSpan, bufferedBits: BufferedBits = BufferedBits()) {
    self.input = input
    self.bufferedBits = bufferedBits
  }

  /// Reads 0...32 bits, placing the first bit read in bit 0 of the result.
  /// A failed read leaves both offsets unchanged.
  mutating func readBits(_ bitCount: Int) throws(BitReaderError) -> UInt32 {
    guard (0...32).contains(bitCount) else {
      throw .invalidBitCount
    }
    var nextByteOffset = byteOffset
    var nextBitOffset = bitOffset
    var nextBufferedBits = bufferedBits
    var out: UInt32 = 0

    for resultBitIndex in 0..<bitCount {
      if nextBufferedBits.count > 0 {
        out |= UInt32(nextBufferedBits.value & 1) << resultBitIndex
        nextBufferedBits.value >>= 1
        nextBufferedBits.count -= 1
        continue
      }
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
    bufferedBits = nextBufferedBits
    return out
  }

  mutating func readFixedLiteralLengthSymbol() throws(BitReaderError) -> UInt32 {
    var code: UInt32 = 0

    for bitCount in 1...9 {
      let bit = try readBits(1)
      code = (code << 1) | bit

      if bitCount >= 7 {
        switch (bitCount, code) {
        case (7, 0...23): return 256 + code
        case (8, 48...191): return code - 48
        case (8, 192...197): return 280 + code - 192
        case (8, 198...199): throw .forbiddenSymbol
        case (9, 400...511): return 144 + code - 400
        default: continue
        }
      }
    }
    throw .invalidHuffmanTable
  }

  /// Reads the extra bits for an already-decoded length symbol.
  mutating func readMatchLength(symbol code: UInt32) throws(BitReaderError) -> UInt32 {
    guard (257...285).contains(code) else {
      throw .forbiddenSymbol
    }
    let index = Int(code) - 257
    return UInt32(MatchCode.lengthBases[index]) + (try readBits(MatchCode.lengthExtraBits[index]))
  }

  mutating func readFixedMatchDistance() throws(BitReaderError) -> UInt32 {
    var code: UInt32 = 0

    for _ in 0..<5 {
      let bit = try readBits(1)
      code = (code << 1) | bit
    }
    return try readMatchDistance(symbol: code)
  }

  /// Reads the extra bits for an already-decoded distance symbol.
  mutating func readMatchDistance(symbol code: UInt32) throws(BitReaderError) -> UInt32 {
    guard code < 30 else {
      throw .forbiddenSymbol
    }
    let index = Int(code)
    return UInt32(MatchCode.distanceBases[index]) + (try readBits(MatchCode.distanceExtraBits[index]))
  }

  mutating func alignToByte() {
    if bufferedBits.count > 0 {
      let padding = bufferedBits.count % 8
      bufferedBits.value >>= padding
      bufferedBits.count -= padding
      return
    }
    if bitOffset != 0 {
      bitOffset = 0
      byteOffset += 1
    }
  }

  mutating func readBlockHeader() throws(BitReaderError) -> BlockHeader {
    var header = try readBits(3)
    let isFinal = header & 1 == 1
    header = header >> 1
    let blockType: BlockType
    switch header {
    case 0:
      blockType = .stored
    case 1:
      blockType = .fixedHuffman
    case 2:
      blockType = .dynamicHuffman
    default:
      throw .unsupportedBlockType
    }
    return BlockHeader(blockType: blockType, isFinal: isFinal)
  }

  mutating func readStoredLength() throws(BitReaderError) -> (len: UInt16, nlen: UInt16) {
    alignToByte()
    let bytes = try readBits(32)
    let len = UInt16(bytes & UInt32(UInt16.max))
    let nlen = UInt16(bytes >> 16)
    guard len ^ nlen == UInt16.max else {
      throw .invalidStoredLength
    }
    return (len, nlen)
  }

  struct Checkpoint {
    fileprivate let byteOffset: Int
    fileprivate let bitOffset: Int
    fileprivate let bufferedBits: BufferedBits
  }

  func checkpoint() -> Checkpoint {
    Checkpoint(byteOffset: byteOffset, bitOffset: bitOffset, bufferedBits: bufferedBits)
  }

  mutating func restore(_ checkpoint: Checkpoint) {
    byteOffset = checkpoint.byteOffset
    bitOffset = checkpoint.bitOffset
    bufferedBits = checkpoint.bufferedBits
  }

  /// Retains partial fields between chunks without borrowing the previous input.
  /// A suspended field is at most 48 bits, so its unread tail fits in one word.
  mutating func remainder(includingUnreadBytes: Bool) -> (bits: BufferedBits, consumed: Int) {
    if bitOffset > 0 {
      appendBuffered(UInt64(input[byteOffset] >> bitOffset), count: 8 - bitOffset)
      byteOffset += 1
      bitOffset = 0
    }
    if includingUnreadBytes {
      while byteOffset < input.byteCount {
        appendBuffered(UInt64(input[byteOffset]), count: 8)
        byteOffset += 1
      }
    }
    return (bufferedBits, byteOffset)
  }

  private mutating func appendBuffered(_ value: UInt64, count: Int) {
    precondition(bufferedBits.count + count <= UInt64.bitWidth)
    bufferedBits.value |= value << bufferedBits.count
    bufferedBits.count += count
  }
}

struct BufferedBits {
  var value: UInt64 = 0
  var count = 0
}
