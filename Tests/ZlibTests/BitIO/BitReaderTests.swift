import Testing

@testable import Zlib

@Test func bitReaderReadsLowBitsFirst() throws {
  let input: [UInt8] = [0b1011_0110]
  var reader = BitReader(input.span.bytes)

  #expect(try reader.readBits(3) == 0b110)
  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == 3)
  #expect(try reader.readBits(5) == 0b10110)
  #expect(reader.byteOffset == 1)
  #expect(reader.bitOffset == 0)
}

@Test func bitReaderReadsAcrossByteBoundaries() throws {
  let input: [UInt8] = [0xB6, 0x69]
  var reader = BitReader(input.span.bytes)

  #expect(try reader.readBits(12) == 0x9B6)
  #expect(reader.byteOffset == 1)
  #expect(reader.bitOffset == 4)
  #expect(try reader.readBits(4) == 6)
  #expect(reader.byteOffset == 2)
  #expect(reader.bitOffset == 0)
}

@Test func bitReaderReadsAFullUInt32() throws {
  let input: [UInt8] = [0x12, 0x34, 0x56, 0x78]
  var reader = BitReader(input.span.bytes)

  #expect(try reader.readBits(32) == 0x7856_3412)
  #expect(reader.byteOffset == 4)
  #expect(reader.bitOffset == 0)
}

@Test func bitReaderReadsAnUnalignedUInt32AcrossFiveBytes() throws {
  let input: [UInt8] = [0xB6, 0x12, 0x34, 0x56, 0x78]
  var reader = BitReader(input.span.bytes)
  #expect(try reader.readBits(4) == 6)

  #expect(try reader.readBits(32) == 0x8563_412B)
  #expect(reader.byteOffset == 4)
  #expect(reader.bitOffset == 4)
  #expect(try reader.readBits(4) == 7)
  #expect(reader.byteOffset == 5)
  #expect(reader.bitOffset == 0)
}

@Test(arguments: 0...7, 0...32)
func bitReaderWordReadsMatchPackedBits(offset: Int, width: Int) throws {
  let input: [UInt8] = [0xB6, 0x69, 0xA5, 0x12, 0x34, 0x56, 0x78, 0xCD, 0xEF]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(offset)
  var expected: UInt32 = 0
  for bit in 0..<width {
    let position = offset + bit
    expected |= UInt32((input[position / 8] >> (position % 8)) & 1) << bit
  }

  #expect(try reader.readBits(width) == expected)
  #expect(reader.byteOffset == (offset + width) / 8)
  #expect(reader.bitOffset == (offset + width) % 8)
}

@Test(arguments: [0, 1, 7, 8, 15, 31, 32, 47, 63, 64])
func bitReaderCombinesBufferedPrefixesWithNewWords(prefixCount: Int) throws {
  let prefix: UInt64 = 0xA596_1234_ABCD_EF78
  let input: [UInt8] = [0xB6, 0x69, 0xA5, 0x12, 0x34, 0x56, 0x78, 0xCD, 0xEF, 0x41]
  var reader = BitReader(input.span.bytes, bufferedBits: BufferedBits(value: prefix, count: prefixCount))
  var consumed = 0
  for width in [1, 15, 32, 8, 0, 16] {
    var expected: UInt32 = 0
    for bit in 0..<width {
      let position = consumed + bit
      let value: UInt32
      if position < prefixCount {
        value = UInt32((prefix >> position) & 1)
      } else {
        let index = position - prefixCount
        value = UInt32((input[index / 8] >> (index % 8)) & 1)
      }
      expected |= value << bit
    }
    #expect(try reader.readBits(width) == expected)
    consumed += width
    let inputBits = max(0, consumed - prefixCount)
    #expect(reader.byteOffset == inputBits / 8)
    #expect(reader.bitOffset == inputBits % 8)
  }
}

@Test func bitReaderCheckpointRestoresWordLookahead() throws {
  let input: [UInt8] = [0xB6, 0x69, 0xA5, 0x12, 0x34, 0x56, 0x78, 0xCD]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(3)
  let checkpoint = reader.checkpoint()
  let expected = try reader.readBits(32)
  _ = try reader.readBits(16)

  reader.restore(checkpoint)

  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == 3)
  #expect(try reader.readBits(32) == expected)
}

@Test func bitReaderRemainderLeavesPrefetchedBytesUnconsumed() throws {
  let input: [UInt8] = [0xB6, 0x69, 0xA5, 0x12, 0x34, 0x56]
  var reader = BitReader(input.span.bytes)
  #expect(try reader.readBits(3) == 6)
  let remainder = reader.remainder(includingUnreadBytes: false)

  #expect(remainder.consumed == 1)
  #expect(remainder.bits.count == 5)
  var resumed = BitReader(input.span.extracting(remainder.consumed...).bytes, bufferedBits: remainder.bits)
  #expect(try resumed.readBits(5) == 22)
  #expect(try resumed.readBits(16) == 0xA569)
}

@Test func bitReaderRemainderRetainsTruncatedFields() throws {
  let input: [UInt8] = [0xB6, 0x69, 0xA5]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(3)
  #expect(throws: BitReaderError.unexpectedEndOfInput) { try reader.readBits(32) }
  let remainder = reader.remainder(includingUnreadBytes: true)
  #expect(remainder.consumed == input.count)
  #expect(remainder.bits.count == 21)

  let next: [UInt8] = [0x12, 0x34]
  var resumed = BitReader(next.span.bytes, bufferedBits: remainder.bits)
  #expect(try resumed.readBits(32) == UInt32((UInt64(0x3412_A569_B6) >> 3) & 0xFFFF_FFFF))
}

@Test func bitReaderCanReadZeroBitsFromEmptyInput() throws {
  let input: [UInt8] = []
  var reader = BitReader(input.span.bytes)

  #expect(try reader.readBits(0) == 0)
  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == 0)
}

@Test func bitReaderZeroBitReadPreservesPartialByte() throws {
  let input: [UInt8] = [0xB6]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(3)

  #expect(try reader.readBits(0) == 0)
  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == 3)
}

@Test func bitReaderPreservesPositionAfterTruncatedRead() throws {
  let input: [UInt8] = [0xB6]
  var reader = BitReader(input.span.bytes)
  #expect(try reader.readBits(3) == 6)

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    try reader.readBits(6)
  }

  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == 3)
  #expect(try reader.readBits(5) == 22)
  #expect(reader.byteOffset == 1)
  #expect(reader.bitOffset == 0)
}

@Test func bitReaderRejectsReadingPastTheEnd() throws {
  let input: [UInt8] = [0xB6]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(8)

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    try reader.readBits(1)
  }

  #expect(reader.byteOffset == 1)
  #expect(reader.bitOffset == 0)
}

@Test func bitReaderPreservesPositionAfterTruncationAcrossBytes() throws {
  let input: [UInt8] = [0xB6, 0x69]
  var reader = BitReader(input.span.bytes)
  #expect(try reader.readBits(3) == 6)

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    try reader.readBits(14)
  }

  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == 3)
  #expect(try reader.readBits(5) == 22)
  #expect(try reader.readBits(8) == 0x69)
  #expect(reader.byteOffset == 2)
  #expect(reader.bitOffset == 0)
}

@Test(arguments: [-1, 33, Int.min, Int.max])
func bitReaderRejectsInvalidWidths(bitCount: Int) throws {
  let input: [UInt8] = [0xB6]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(3)
  let originalByteOffset = reader.byteOffset
  let originalBitOffset = reader.bitOffset

  #expect(throws: BitReaderError.invalidBitCount) {
    try reader.readBits(bitCount)
  }

  #expect(reader.byteOffset == originalByteOffset)
  #expect(reader.bitOffset == originalBitOffset)
}

@Test(arguments: 1...7, [0, 1])
func bitReaderAlignmentDiscardsRemainingBits(bitCount: Int, completedBytes: Int) throws {
  let input: [UInt8] = Array(repeating: 0xA5, count: completedBytes) + [0xFF, 0x69, 0xAB]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(completedBytes * 8 + bitCount)

  reader.alignToByte()

  #expect(reader.byteOffset == completedBytes + 1)
  #expect(reader.bitOffset == 0)
  #expect(try reader.readBits(16) == 0xAB69)
}

@Test(arguments: [0, 1])
func bitReaderAlignmentPreservesAnAlignedPosition(completedBytes: Int) throws {
  let input: [UInt8] = [0x12, 0x34]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(completedBytes * 8)

  reader.alignToByte()

  #expect(reader.byteOffset == completedBytes)
  #expect(reader.bitOffset == 0)
  #expect(try reader.readBits(8) == UInt32(input[completedBytes]))
}

@Test func bitReaderAlignmentIsIdempotent() throws {
  let input: [UInt8] = [0xFF, 0x69]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(3)

  reader.alignToByte()
  reader.alignToByte()

  #expect(reader.byteOffset == 1)
  #expect(reader.bitOffset == 0)
  #expect(try reader.readBits(8) == 0x69)
}

@Test func bitReaderCanAlignEmptyInput() {
  let input: [UInt8] = []
  var reader = BitReader(input.span.bytes)

  reader.alignToByte()

  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == 0)
  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    try reader.readBits(1)
  }
}

@Test(arguments: 1...8)
func bitReaderCanAlignAtEndOfInput(bitCount: Int) throws {
  let input: [UInt8] = [0xFF]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(bitCount)

  reader.alignToByte()

  #expect(reader.byteOffset == 1)
  #expect(reader.bitOffset == 0)
  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    try reader.readBits(1)
  }
}
