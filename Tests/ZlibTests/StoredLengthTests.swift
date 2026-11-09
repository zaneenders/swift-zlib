import Testing

@testable import Zlib

@Test(arguments: [
  ([UInt8(0x00), 0x00, 0xFF, 0xFF], UInt16(0), UInt16(0xFFFF)),
  ([UInt8(0x01), 0x00, 0xFE, 0xFF], UInt16(1), UInt16(0xFFFE)),
  ([UInt8(0x34), 0x12, 0xCB, 0xED], UInt16(0x1234), UInt16(0xEDCB)),
  ([UInt8(0x00), 0x80, 0xFF, 0x7F], UInt16(0x8000), UInt16(0x7FFF)),
  ([UInt8(0xFF), 0xFF, 0x00, 0x00], UInt16(0xFFFF), UInt16(0))
])
func storedLengthDecodesValidLittleEndianPairs(
  testCase: (bytes: [UInt8], len: UInt16, nlen: UInt16)
) throws {
  var reader = BitReader(testCase.bytes.span.bytes)

  let result = try reader.parseLenNLen()

  #expect(result.len == testCase.len)
  #expect(result.nlen == testCase.nlen)
  #expect(reader.byteOffset == 4)
  #expect(reader.bitOffset == 0)
  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    try reader.readBits(1)
  }
}

@Test(arguments: 1...7, [UInt8(0x00), 0xFF])
func storedLengthSkipsPaddingBits(bitOffset: Int, padding: UInt8) throws {
  let input: [UInt8] = [0xA5, padding, 0x34, 0x12, 0xCB, 0xED, 0x69, 0xAB]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(8 + bitOffset)

  let result = try reader.parseLenNLen()

  #expect(result.len == 0x1234)
  #expect(result.nlen == 0xEDCB)
  #expect(reader.byteOffset == 6)
  #expect(reader.bitOffset == 0)
  #expect(try reader.readBits(16) == 0xAB69)
}

@Test func storedLengthReadsFromAnAlignedPositionAfterEarlierBytes() throws {
  let input: [UInt8] = [0xA5, 0x34, 0x12, 0xCB, 0xED, 0x69]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(8)

  let result = try reader.parseLenNLen()

  #expect(result.len == 0x1234)
  #expect(result.nlen == 0xEDCB)
  #expect(reader.byteOffset == 5)
  #expect(reader.bitOffset == 0)
  #expect(try reader.readBits(8) == 0x69)
}

@Test(arguments: [
  [UInt8(0xFF), 0xFF, 0xFF, 0xFF],  // Both fields have every bit set.
  [UInt8(0x00), 0x00, 0x00, 0x00],  // Both fields have every bit clear.
  [UInt8(0x34), 0x12, 0xDB, 0xED],  // OR gives 0xFFFF despite an overlapping set bit.
  [UInt8(0x34), 0x12, 0xCA, 0xED],  // A complement bit is missing in the low byte.
  [UInt8(0x34), 0x12, 0xCB, 0xCD]  // A complement bit is missing in the high byte.
])
func storedLengthRejectsInvalidComplements(input: [UInt8]) {
  var reader = BitReader(input.span.bytes)

  #expect(throws: BitReaderError.invalid) {
    _ = try reader.parseLenNLen()
  }
}

@Test(arguments: 0..<4, [0, 1])
func storedLengthRejectsTruncatedAlignedInput(
  availableBytes: Int, completedBytes: Int
) throws {
  let fields: [UInt8] = [0x34, 0x12, 0xCB, 0xED]
  let input =
    Array(repeating: UInt8(0xA5), count: completedBytes)
    + Array(fields.prefix(availableBytes))
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(completedBytes * 8)

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    _ = try reader.parseLenNLen()
  }
  #expect(reader.byteOffset == completedBytes)
  #expect(reader.bitOffset == 0)
}

@Test(arguments: 0..<4, 1...7)
func storedLengthRejectsTruncatedInputAfterPadding(
  availableBytes: Int, bitOffset: Int
) throws {
  let fields: [UInt8] = [0x34, 0x12, 0xCB, 0xED]
  let input: [UInt8] = [0xFF] + Array(fields.prefix(availableBytes))
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(bitOffset)

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    _ = try reader.parseLenNLen()
  }
}

@Test func storedLengthFollowsBlockHeaderAndLeavesPayloadUnread() throws {
  // Final stored block, nonzero padding, LEN=3, NLEN=0xFFFC, payload="ABC".
  let input: [UInt8] = [0xF9, 0x03, 0x00, 0xFC, 0xFF, 0x41, 0x42, 0x43]
  var reader = BitReader(input.span.bytes)
  let header = try reader.parseheader()

  let result = try reader.parseLenNLen()

  #expect(header.bType == .stored)
  #expect(header.isLastByte == true)
  #expect(result.len == 3)
  #expect(result.nlen == 0xFFFC)
  #expect(reader.byteOffset == 5)
  #expect(reader.bitOffset == 0)
  #expect(try reader.readBits(24) == 0x434241)
}
