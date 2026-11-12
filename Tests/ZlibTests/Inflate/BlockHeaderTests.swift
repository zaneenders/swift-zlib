import Testing

@testable import Zlib

@Test(arguments: [
  (UInt8(0xA8), BlockType.stored, false),
  (UInt8(0xA9), BlockType.stored, true),
  (UInt8(0xAA), BlockType.fixedHuffman, false),
  (UInt8(0xAB), BlockType.fixedHuffman, true),
  (UInt8(0xAC), BlockType.dynamicHuffman, false),
  (UInt8(0xAD), BlockType.dynamicHuffman, true)
])
func blockHeaderDecodesValidCombinations(
  testCase: (byte: UInt8, blockType: BlockType, isFinal: Bool)
) throws {
  let input: [UInt8] = [testCase.byte]
  var reader = BitReader(input.span.bytes)

  let header = try reader.readBlockHeader()

  #expect(header.blockType == testCase.blockType)
  #expect(header.isFinal == testCase.isFinal)
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
    UInt8(truncatingIfNeeded: packed >> 8)
  ]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(8 + bitOffset)

  let header = try reader.readBlockHeader()

  #expect(header.blockType == .fixedHuffman)
  #expect(header.isFinal == true)
  #expect(reader.byteOffset == 1 + (bitOffset + 3) / 8)
  #expect(reader.bitOffset == (bitOffset + 3) % 8)
  #expect(try reader.readBits(5) == 0b10101)
}

@Test func blockHeaderCanUseTheLastThreeBitsOfInput() throws {
  let input: [UInt8] = [0b1011_1111]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(5)

  let header = try reader.readBlockHeader()

  #expect(header.blockType == .dynamicHuffman)
  #expect(header.isFinal == true)
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
    _ = try reader.readBlockHeader()
  }
}

@Test func blockHeaderRejectsEmptyInput() {
  let input: [UInt8] = []
  var reader = BitReader(input.span.bytes)

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    _ = try reader.readBlockHeader()
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
    _ = try reader.readBlockHeader()
  }
  #expect(reader.byteOffset == originalByteOffset)
  #expect(reader.bitOffset == originalBitOffset)
}
