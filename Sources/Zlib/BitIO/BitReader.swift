/// Reads least-significant-bit-first numeric fields from borrowed input.
struct BitReader: ~Copyable, ~Escapable {
  private let input: RawSpan
  private var bufferedBits: BufferedBits
  // Bits inherited from a previous chunk precede this input's logical offsets.
  private var prefixBitCount: Int
  // Refilling may advance beyond byteOffset; only consumed bits are reported.
  private var nextByteOffset = 0
  private(set) var byteOffset = 0
  private(set) var bitOffset = 0

  @_lifetime(copy input)
  init(_ input: RawSpan, bufferedBits: BufferedBits = BufferedBits()) {
    precondition((0...64).contains(bufferedBits.count))
    self.input = input
    self.bufferedBits = BufferedBits(
      value: bufferedBits.value & (UInt64.max >> (64 - bufferedBits.count)), count: bufferedBits.count)
    self.prefixBitCount = bufferedBits.count
  }

  /// Reads 0...32 bits, placing the first bit read in bit 0 of the result.
  /// A failed read leaves both offsets unchanged.
  mutating func readBits(_ bitCount: Int) throws(BitReaderError) -> UInt32 {
    guard (0...32).contains(bitCount) else {
      throw .invalidBitCount
    }
    let bits = peekBits(upTo: bitCount)
    guard bits.count == bitCount else { throw .unexpectedEndOfInput }
    dropBits(bitCount)
    return bits.value
  }

  /// Looks ahead without consuming input. Missing high bits are zero, and
  /// `count` reports how many bits are actually available at the end of input.
  @inline(__always)
  mutating func peekBits(upTo bitCount: Int) -> (value: UInt32, count: Int) {
    precondition((0...32).contains(bitCount))
    if bufferedBits.count < bitCount {
      if input.byteCount - nextByteOffset >= 4 {
        // Fewer than 32 bits are buffered here, so another word fits in UInt64.
        let word = input.load(fromByteOffset: nextByteOffset, as: UInt32.self).littleEndian
        bufferedBits.value |= UInt64(word) << bufferedBits.count
        bufferedBits.count += 32
        nextByteOffset += 4
      } else {
        while bufferedBits.count < bitCount && nextByteOffset < input.byteCount {
          appendBuffered(UInt64(input[nextByteOffset]), count: 8)
          nextByteOffset += 1
        }
      }
    }
    let mask = UInt64.max >> (64 - bitCount)
    return (UInt32(truncatingIfNeeded: bufferedBits.value & mask), min(bitCount, bufferedBits.count))
  }

  @inline(__always)
  mutating func dropBits(_ bitCount: Int) {
    precondition(bitCount >= 0 && bitCount <= bufferedBits.count)
    bufferedBits.value >>= bitCount
    bufferedBits.count -= bitCount
    let prefix = min(bitCount, prefixBitCount)
    prefixBitCount -= prefix
    let position = bitOffset + bitCount - prefix
    byteOffset += position >> 3
    bitOffset = position & 7
  }

  mutating func readFixedLiteralLengthSymbol() throws(BitReaderError) -> UInt32 {
    let symbol = try HuffmanDecoder.fixedLiteralLength.readSymbol(from: &self)
    guard symbol < 286 else { throw .forbiddenSymbol }
    return symbol
  }

  /// Copies whole bytes, retaining any progress if the input is truncated.
  mutating func copyBytes(count: Int, into output: inout OutputSpan<UInt8>) throws(BitReaderError) {
    precondition(count >= 0 && count <= output.freeCapacity)
    var remaining = count
    // A suspended field can leave whole bytes in the bit buffer. Drain those
    // first; stored blocks otherwise copy directly from their aligned input.
    while remaining > 0 && (prefixBitCount > 0 || bitOffset != 0) {
      output.append(UInt8(try readBits(8)))
      remaining -= 1
    }
    guard remaining > 0 else { return }
    let available = min(remaining, input.byteCount - byteOffset)
    output.appendBytes(Span(viewing: input.extracting(byteOffset..<(byteOffset + available))))
    byteOffset += available
    // Bulk copying bypasses the lookahead buffer. Resume refilling at the new
    // logical position, leaving prefetched but unconsumed bytes in the input.
    bufferedBits = BufferedBits()
    nextByteOffset = byteOffset
    guard available == remaining else { throw .unexpectedEndOfInput }
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
    let bits = try readBits(5)
    let code = ((bits & 1) << 4) | ((bits & 2) << 2) | (bits & 4) | ((bits & 8) >> 2) | ((bits & 16) >> 4)
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
    let padding = prefixBitCount > 0 ? prefixBitCount & 7 : (8 - bitOffset) & 7
    dropBits(padding)
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
    fileprivate let prefixBitCount: Int
    fileprivate let nextByteOffset: Int
  }

  func checkpoint() -> Checkpoint {
    Checkpoint(
      byteOffset: byteOffset, bitOffset: bitOffset, bufferedBits: bufferedBits,
      prefixBitCount: prefixBitCount, nextByteOffset: nextByteOffset)
  }

  mutating func restore(_ checkpoint: Checkpoint) {
    byteOffset = checkpoint.byteOffset
    bitOffset = checkpoint.bitOffset
    bufferedBits = checkpoint.bufferedBits
    prefixBitCount = checkpoint.prefixBitCount
    nextByteOffset = checkpoint.nextByteOffset
  }

  /// Retains partial fields between chunks without borrowing the previous input.
  /// A suspended field is at most 48 bits, so its unread tail fits in one word.
  mutating func remainder(includingUnreadBytes: Bool) -> (bits: BufferedBits, consumed: Int) {
    if includingUnreadBytes {
      while nextByteOffset < input.byteCount {
        appendBuffered(UInt64(input[nextByteOffset]), count: 8)
        nextByteOffset += 1
      }
      return (bufferedBits, input.byteCount)
    }
    // Read-ahead must not consume container trailers or bytes the caller will
    // supply again after needsOutput. Retain only the previous chunk's prefix
    // and the unread tail of a byte whose leading bits have been consumed.
    let tailBits = bitOffset == 0 ? 0 : 8 - bitOffset
    let count = prefixBitCount + tailBits
    let mask = UInt64.max >> (64 - count)
    return (
      BufferedBits(value: bufferedBits.value & mask, count: count), byteOffset + (tailBits == 0 ? 0 : 1)
    )
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
