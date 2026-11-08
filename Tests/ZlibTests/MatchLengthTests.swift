import Testing

@testable import Zlib

@Test(arguments: [
  (UInt32(257), UInt32(3)),
  (UInt32(258), UInt32(4)),
  (UInt32(259), UInt32(5)),
  (UInt32(264), UInt32(10)),
  (UInt32(285), UInt32(258)),
])
func matchLengthWithoutExtraBitsDoesNotReadInput(testCase: (symbol: UInt32, length: UInt32)) throws {
  let input: [UInt8] = []
  var reader = BitReader(input.span.bytes)

  #expect(try reader.readMatchLength(symbol: testCase.symbol) == testCase.length)
  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == 0)
}

@Test(arguments: [
  (UInt32(265), UInt8(1), 1, UInt32(12)),
  (UInt32(266), UInt8(0), 1, UInt32(13)),
  (UInt32(268), UInt8(1), 1, UInt32(18)),
  (UInt32(269), UInt8(2), 2, UInt32(21)),
  (UInt32(272), UInt8(3), 2, UInt32(34)),
  (UInt32(273), UInt8(5), 3, UInt32(40)),
  (UInt32(276), UInt8(7), 3, UInt32(66)),
  (UInt32(277), UInt8(10), 4, UInt32(77)),
  (UInt32(280), UInt8(15), 4, UInt32(130)),
  (UInt32(281), UInt8(18), 5, UInt32(149)),
  (UInt32(284), UInt8(30), 5, UInt32(257)),
])
func matchLengthReadsOnlyItsNumericExtraBits(
  testCase: (symbol: UInt32, extra: UInt8, bitCount: Int, length: UInt32)
) throws {
  let packed = UInt16(testCase.extra) | (UInt16(0b10101) << testCase.bitCount)
  let input: [UInt8] = [UInt8(truncatingIfNeeded: packed), UInt8(truncatingIfNeeded: packed >> 8)]
  var reader = BitReader(input.span.bytes)

  #expect(try reader.readMatchLength(symbol: testCase.symbol) == testCase.length)
  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == testCase.bitCount)
  #expect(try reader.readBits(5) == 0b10101)
}

@Test(arguments: [
  (UInt32(265), 1),
  (UInt32(269), 2),
  (UInt32(273), 3),
  (UInt32(277), 4),
  (UInt32(281), 5),
])
func matchLengthRejectsTruncatedExtraBits(testCase: (symbol: UInt32, bitCount: Int)) throws {
  let input: [UInt8] = [0xFF]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(9 - testCase.bitCount)
  let originalByteOffset = reader.byteOffset
  let originalBitOffset = reader.bitOffset

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    _ = try reader.readMatchLength(symbol: testCase.symbol)
  }
  #expect(reader.byteOffset == originalByteOffset)
  #expect(reader.bitOffset == originalBitOffset)
}

@Test(arguments: [UInt32(0), 65, 256, 286, 287, .max])
func matchLengthRejectsSymbolsOutsideTheLengthAlphabet(symbol: UInt32) {
  let input: [UInt8] = [0x69]
  var reader = BitReader(input.span.bytes)

  #expect(throws: BitReaderError.invalid) {
    _ = try reader.readMatchLength(symbol: symbol)
  }
  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == 0)
}
