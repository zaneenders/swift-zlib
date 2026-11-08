import Testing

@testable import Zlib

@Test(arguments: [
  (UInt8(0xA8), BType.stored, false),
  (UInt8(0xA9), BType.stored, true),
  (UInt8(0xAA), BType.fixedHuffman, false),
  (UInt8(0xAB), BType.fixedHuffman, true),
  (UInt8(0xAC), BType.dynamicHuffman, false),
  (UInt8(0xAD), BType.dynamicHuffman, true),
])
func blockHeaderDecodesValidCombinations(
  testCase: (byte: UInt8, bType: BType, isLastByte: Bool)
) throws {
  let input: [UInt8] = [testCase.byte]
  var reader = BitReader(input.span.bytes)

  let header = try reader.parseheader()

  #expect(header.bType == testCase.bType)
  #expect(header.isLastByte == testCase.isLastByte)
  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == 3)
  #expect(try reader.readBits(5) == 0b10101)
}

@Test(arguments: 0...7)
func blockHeaderReadsFromTheCurrentBitPosition(bitOffset: Int) throws {
  // A final fixed-Huffman header (011), followed by five bits (10101).
  let packed = UInt16(0b10101_011) << bitOffset
  let input: [UInt8] = [
    0xA5,
    UInt8(truncatingIfNeeded: packed),
    UInt8(truncatingIfNeeded: packed >> 8),
  ]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(8 + bitOffset)

  let header = try reader.parseheader()

  #expect(header.bType == .fixedHuffman)
  #expect(header.isLastByte == true)
  #expect(reader.byteOffset == 1 + (bitOffset + 3) / 8)
  #expect(reader.bitOffset == (bitOffset + 3) % 8)
  #expect(try reader.readBits(5) == 0b10101)
}

@Test func blockHeaderCanUseTheLastThreeBitsOfInput() throws {
  let input: [UInt8] = [0b1011_1111]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(5)

  let header = try reader.parseheader()

  #expect(header.bType == .dynamicHuffman)
  #expect(header.isLastByte == true)
  #expect(reader.byteOffset == 1)
  #expect(reader.bitOffset == 0)
  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    try reader.readBits(1)
  }
}

@Test(arguments: [UInt8(0x06), 0x07])
func blockHeaderRejectsReservedBlockType(byte: UInt8) {
  let input: [UInt8] = [byte]
  var reader = BitReader(input.span.bytes)

  #expect(throws: (any Error).self) {
    _ = try reader.parseheader()
  }
}

@Test func blockHeaderRejectsEmptyInput() {
  let input: [UInt8] = []
  var reader = BitReader(input.span.bytes)

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    _ = try reader.parseheader()
  }
  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == 0)
}

@Test(arguments: [0, 1, 2])
func blockHeaderPreservesPositionAfterTruncation(remainingBits: Int) throws {
  let input: [UInt8] = [0xFF]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(8 - remainingBits)
  let originalByteOffset = reader.byteOffset
  let originalBitOffset = reader.bitOffset

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    _ = try reader.parseheader()
  }
  #expect(reader.byteOffset == originalByteOffset)
  #expect(reader.bitOffset == originalBitOffset)
}
