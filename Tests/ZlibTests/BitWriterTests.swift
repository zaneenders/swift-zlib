import Testing

@testable import Zlib

private func expectBitWriterBytes(
  _ output: borrowing UniqueArray<UInt8>,
  _ expected: [UInt8]
) throws {
  let bytes = output.span
  try #require(bytes.count == expected.count)
  for index in expected.indices {
    #expect(bytes[index] == expected[index], "Byte at index \(index)")
  }
}

@Test(arguments: [0, 1, 8])
func bitWriterFinishesEmptyWithoutProducingBytes(minimumCapacity: Int) throws {
  let writer = BitWriter(minimumCapacity: minimumCapacity)

  let output = writer.finish()

  try expectBitWriterBytes(output, [])
}

@Test func bitWriterPacksBitsLowFirst() throws {
  var writer = BitWriter(minimumCapacity: 0)
  let bits: [UInt8] = [0, 1, 1, 0, 1, 1, 0, 1]
  for bit in bits {
    try writer.writeBit(bit)
  }

  let output = writer.finish()

  try expectBitWriterBytes(output, [0xB6])
}

@Test(arguments: 1...8, [UInt8(0), 0xA5, 0xFF])
func bitWriterWritesOnlyTheRequestedLowBits(count: Int, value: UInt8) throws {
  var writer = BitWriter(minimumCapacity: 0)

  writer.writeBits(value, count: count)
  let output = writer.finish()

  let mask = UInt8((UInt16(1) << count) - 1)
  try expectBitWriterBytes(output, [value & mask])
}

@Test func bitWriterPacksSuccessiveFieldsWithoutPadding() throws {
  var writer = BitWriter(minimumCapacity: 0)

  writer.writeBits(0b110, count: 3)
  writer.writeBits(0b10110, count: 5)
  writer.writeBits(0b1001, count: 4)
  writer.writeBits(0b0110, count: 4)
  let output = writer.finish()

  try expectBitWriterBytes(output, [0xB6, 0x69])
}

@Test(arguments: 0...7)
func bitWriterWritesAByteAtEveryBitOffset(bitOffset: Int) throws {
  var writer = BitWriter(minimumCapacity: 0)
  for _ in 0..<bitOffset {
    try writer.writeBit(1)
  }

  writer.writeBits(0x69, count: 8)
  let output = writer.finish()

  let packed = ((UInt16(1) << bitOffset) - 1) | (UInt16(0x69) << bitOffset)
  var expected = [UInt8(packed & 0xFF)]
  if bitOffset > 0 {
    expected.append(UInt8(packed >> 8))
  }
  try expectBitWriterBytes(output, expected)
}

@Test func bitWriterCanMixSingleBitAndFieldWrites() throws {
  var writer = BitWriter(minimumCapacity: 0)

  writer.writeBits(0b10, count: 2)
  try writer.writeBit(1)
  writer.writeBits(0b10110, count: 5)
  let output = writer.finish()

  try expectBitWriterBytes(output, [0xB6])
}

@Test(arguments: [0, 3, 8], [UInt8(0), 0xFF])
func bitWriterZeroBitWritesPreservePosition(prefixLength: Int, value: UInt8) throws {
  var writer = BitWriter(minimumCapacity: 0)
  let bits: [UInt8] = [0, 1, 1, 0, 1, 1, 0, 1]
  for bit in bits.prefix(prefixLength) {
    try writer.writeBit(bit)
  }

  writer.writeBits(value, count: 0)

  for bit in bits.dropFirst(prefixLength) {
    try writer.writeBit(bit)
  }
  let output = writer.finish()
  try expectBitWriterBytes(output, [0xB6])
}

@Test(arguments: 0...255)
func bitWriterCanEncodeEveryByte(value: Int) throws {
  var writer = BitWriter(minimumCapacity: 1)
  let byte = UInt8(value)
  for bitIndex in 0..<8 {
    try writer.writeBit((byte >> bitIndex) & 1)
  }

  let output = writer.finish()

  try expectBitWriterBytes(output, [byte])
}

@Test func bitWriterContinuesAcrossByteBoundaries() throws {
  var writer = BitWriter(minimumCapacity: 1)
  let bits: [UInt8] = [
    0, 1, 1, 0, 1, 1, 0, 1,  // 0xB6
    1, 0, 0, 1, 0, 1, 1, 0,  // 0x69
    1, 0, 1  // A partial byte: 0x05 after zero padding.
  ]
  for bit in bits {
    try writer.writeBit(bit)
  }

  let output = writer.finish()

  try expectBitWriterBytes(output, [0xB6, 0x69, 0x05])
}

@Test(arguments: 1...7, [UInt8(0), 1])
func bitWriterFinishPadsEveryPartialByteWithZeros(bitCount: Int, bit: UInt8) throws {
  var writer = BitWriter(minimumCapacity: 0)
  for _ in 0..<bitCount {
    try writer.writeBit(bit)
  }

  let output = writer.finish()

  let expected: UInt8 = bit == 0 ? 0 : UInt8((1 << bitCount) - 1)
  try expectBitWriterBytes(output, [expected])
}

@Test(arguments: 1...7, [0, 1])
func bitWriterAlignmentStartsTheNextByte(bitCount: Int, completedBytes: Int) throws {
  var writer = BitWriter(minimumCapacity: 0)
  if completedBytes == 1 {
    for bit: UInt8 in [1, 0, 1, 0, 0, 1, 0, 1] {
      try writer.writeBit(bit)
    }
  }
  for _ in 0..<bitCount {
    try writer.writeBit(1)
  }

  writer.alignToByte()
  for bit: UInt8 in [1, 0, 0, 1, 0, 1, 1, 0] {
    try writer.writeBit(bit)
  }
  let output = writer.finish()

  let partialByte = UInt8((1 << bitCount) - 1)
  let expected: [UInt8] =
    completedBytes == 0
    ? [partialByte, 0x69]
    : [0xA5, partialByte, 0x69]
  try expectBitWriterBytes(output, expected)
}

@Test(arguments: [0, 1])
func bitWriterAlignmentPreservesAnAlignedPosition(completedBytes: Int) throws {
  var writer = BitWriter(minimumCapacity: 0)
  if completedBytes == 1 {
    for bit: UInt8 in [0, 1, 1, 0, 1, 1, 0, 1] {
      try writer.writeBit(bit)
    }
  }

  writer.alignToByte()
  writer.alignToByte()
  let output = writer.finish()

  try expectBitWriterBytes(output, completedBytes == 0 ? [] : [0xB6])
}

@Test func bitWriterCanWriteAfterAligningEmptyOutput() throws {
  var writer = BitWriter(minimumCapacity: 0)
  writer.alignToByte()

  for bit: UInt8 in [0, 1, 1, 0, 1, 1, 0, 1] {
    try writer.writeBit(bit)
  }
  let output = writer.finish()

  try expectBitWriterBytes(output, [0xB6])
}

@Test func bitWriterAlignmentIsIdempotentAndClearsThePendingByte() throws {
  var writer = BitWriter(minimumCapacity: 0)
  for bit: UInt8 in [1, 0, 1] {
    try writer.writeBit(bit)
  }

  writer.alignToByte()
  writer.alignToByte()
  for bit: UInt8 in [1, 1, 0] {
    try writer.writeBit(bit)
  }
  let output = writer.finish()

  try expectBitWriterBytes(output, [0x05, 0x03])
}

@Test(arguments: [UInt8(2), 3, 0x80, 0xFF], 0...8)
func bitWriterRejectsInvalidBitsWithoutChangingOutput(invalidBit: UInt8, prefixLength: Int) throws {
  var writer = BitWriter(minimumCapacity: 0)
  let bits: [UInt8] = [0, 1, 1, 0, 1, 1, 0, 1]
  for bit in bits.prefix(prefixLength) {
    try writer.writeBit(bit)
  }

  #expect(throws: BitWriterError.invalidBit) {
    try writer.writeBit(invalidBit)
  }

  for bit in bits.dropFirst(prefixLength) {
    try writer.writeBit(bit)
  }
  let output = writer.finish()
  try expectBitWriterBytes(output, [0xB6])
}

@Test func bitWriterGrowsOutputWithoutLosingEarlierBytes() throws {
  var writer = BitWriter(minimumCapacity: 1)
  let expected: [UInt8] = [0xB6, 0x69, 0x00, 0xFF, 0x12, 0x34, 0x56, 0x78]
  for byte in expected {
    for bitIndex in 0..<8 {
      try writer.writeBit((byte >> bitIndex) & 1)
    }
  }

  let output = writer.finish()

  try expectBitWriterBytes(output, expected)
}

@Test func bitWriterReturnsAnArrayTheCallerCanMutateAndGrow() throws {
  var output: UniqueArray<UInt8>
  do {
    var writer = BitWriter(minimumCapacity: 0)
    for bit: UInt8 in [1, 0, 1] {
      try writer.writeBit(bit)
    }
    output = writer.finish()
  }
  try expectBitWriterBytes(output, [0x05])

  output[0] = 0x42
  output.append(0x43)

  try expectBitWriterBytes(output, [0x42, 0x43])
}

@Test func bitWriterOutputCanBeReadByBitReader() throws {
  var writer = BitWriter(minimumCapacity: 0)
  let bits: [UInt8] = [
    0, 1, 1,  // 3-bit field: 6
    0, 1, 1, 0, 1,  // 5-bit field: 22
    1, 0, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0  // 12-bit field: 0x569
  ]
  for bit in bits {
    try writer.writeBit(bit)
  }
  let output = writer.finish()
  try expectBitWriterBytes(output, [0xB6, 0x69, 0x05])
  var reader = BitReader(output.span.bytes)

  #expect(try reader.readBits(3) == 6)
  #expect(try reader.readBits(5) == 22)
  #expect(try reader.readBits(12) == 0x569)
  #expect(try reader.readBits(4) == 0)
}

@Test(arguments: [
  (UInt16(0x0000), [UInt8(0x00), 0x00]),
  (UInt16(0x0001), [UInt8(0x01), 0x00]),
  (UInt16(0x00FF), [UInt8(0xFF), 0x00]),
  (UInt16(0x0100), [UInt8(0x00), 0x01]),
  (UInt16(0x1234), [UInt8(0x34), 0x12]),
  (UInt16(0x8000), [UInt8(0x00), 0x80]),
  (UInt16(0xFF00), [UInt8(0x00), 0xFF]),
  (UInt16(0xFFFF), [UInt8(0xFF), 0xFF])
])
func bitWriterWritesUInt16LittleEndian(testCase: (value: UInt16, expected: [UInt8])) throws {
  var writer = BitWriter(minimumCapacity: 0)

  writer.writeUInt16LittleEndian(testCase.value)
  let output = writer.finish()

  try expectBitWriterBytes(output, testCase.expected)
}

@Test func bitWriterWritesConsecutiveUInt16ValuesBetweenByteFields() throws {
  var writer = BitWriter(minimumCapacity: 1)

  writer.writeBits(0xA5, count: 8)
  writer.writeUInt16LittleEndian(0x1234)
  writer.writeUInt16LittleEndian(0xABCD)
  writer.writeBits(0x69, count: 8)
  let output = writer.finish()

  try expectBitWriterBytes(output, [0xA5, 0x34, 0x12, 0xCD, 0xAB, 0x69])
}

@Test(
  arguments: [
    (0, [UInt8(0x34), 0x12]),
    (1, [UInt8(0x69), 0x24, 0x00]),
    (2, [UInt8(0xD3), 0x48, 0x00]),
    (3, [UInt8(0xA7), 0x91, 0x00]),
    (4, [UInt8(0x4F), 0x23, 0x01]),
    (5, [UInt8(0x9F), 0x46, 0x02]),
    (6, [UInt8(0x3F), 0x8D, 0x04]),
    (7, [UInt8(0x7F), 0x1A, 0x09])
  ] as [(bitOffset: Int, expected: [UInt8])])
func bitWriterUInt16WritesContinueAtTheCurrentBitPosition(
  testCase: (bitOffset: Int, expected: [UInt8])
) throws {
  var writer = BitWriter(minimumCapacity: 0)
  for _ in 0..<testCase.bitOffset {
    try writer.writeBit(1)
  }

  writer.writeUInt16LittleEndian(0x1234)
  let output = writer.finish()

  try expectBitWriterBytes(output, testCase.expected)
}

@Test func bitWriterUInt16PreservesThePositionForFollowingBits() throws {
  var writer = BitWriter(minimumCapacity: 0)

  writer.writeBits(0b101, count: 3)
  writer.writeUInt16LittleEndian(0x1234)
  writer.writeBits(0b110, count: 3)
  let output = writer.finish()

  try expectBitWriterBytes(output, [0xA5, 0x91, 0x30])
}

@Test func bitWriterUInt16FollowsExplicitByteAlignment() throws {
  var writer = BitWriter(minimumCapacity: 0)

  writer.writeBits(0b001, count: 3)
  writer.alignToByte()
  writer.writeUInt16LittleEndian(0x1234)
  let output = writer.finish()

  try expectBitWriterBytes(output, [0x01, 0x34, 0x12])
}

@Test(arguments: [
  (UInt16(0x0000), [UInt8(0x00), 0x00, 0xFF, 0xFF]),
  (UInt16(0x0001), [UInt8(0x01), 0x00, 0xFE, 0xFF]),
  (UInt16(0x0100), [UInt8(0x00), 0x01, 0xFF, 0xFE]),
  (UInt16(0x1234), [UInt8(0x34), 0x12, 0xCB, 0xED]),
  (UInt16(0x8000), [UInt8(0x00), 0x80, 0xFF, 0x7F]),
  (UInt16(0xFFFF), [UInt8(0xFF), 0xFF, 0x00, 0x00])
])
func bitWriterWritesStoredLengthAndComplement(
  testCase: (length: UInt16, expected: [UInt8])
) throws {
  var writer = BitWriter(minimumCapacity: 0)

  writer.writeUInt16LittleEndian(testCase.length)
  writer.writeUInt16LittleEndian(~testCase.length)
  let output = writer.finish()

  try expectBitWriterBytes(output, testCase.expected)
}

@Test(arguments: [
  (0, 0, []),
  (0, 1, [0x00]),
  (1, 1, [0x01]),
  (0b10, 2, [0x01]),
  (0b11, 2, [0x03]),
  (0b001, 3, [0x04]),
  (0b00101, 5, [0x14]),
  (0b01110001, 8, [0x8E]),
  (0b110010001, 9, [0x13, 0x01]),
  (0b100000000000011, 15, [0x01, 0x60]),
  (0x1234, 16, [0x48, 0x2C])
] as [(code: UInt16, bitCount: Int, expected: [UInt8])])
func bitWriterWritesExactHuffmanCodeBytes(
  testCase: (code: UInt16, bitCount: Int, expected: [UInt8])
) throws {
  var writer = BitWriter(minimumCapacity: 0)

  writer.writeHuffmanCode(testCase.code, bitCount: testCase.bitCount)
  let output = writer.finish()

  try expectBitWriterBytes(output, testCase.expected)
}

@Test(
  arguments: 0...7,
  [
    (UInt16(0b00101), UInt32(0x14), 5),
    (UInt16(0b110010001), UInt32(0x113), 9),
    (UInt16(0x4003), UInt32(0x6001), 15),
    (UInt16(0x1234), UInt32(0x2C48), 16)
  ]
)
func bitWriterHuffmanCodesPreserveAdjacentFieldsAtEveryBitOffset(
  bitOffset: Int,
  testCase: (code: UInt16, packedCode: UInt32, bitCount: Int)
) throws {
  var writer = BitWriter(minimumCapacity: 0)

  writer.writeBits(0xFF, count: bitOffset)
  writer.writeHuffmanCode(testCase.code, bitCount: testCase.bitCount)
  writer.writeBits(0b101, count: 3)
  let output = writer.finish()

  let prefix = (UInt32(1) << bitOffset) - 1
  let packed = prefix | (testCase.packedCode << bitOffset)
    | (UInt32(0b101) << (bitOffset + testCase.bitCount))
  let byteCount = (bitOffset + testCase.bitCount + 3 + 7) / 8
  let expected = (0..<byteCount).map { UInt8(truncatingIfNeeded: packed >> ($0 * 8)) }
  try expectBitWriterBytes(output, expected)
}

@Test(arguments: [0, 3, 8])
func bitWriterZeroLengthHuffmanCodePreservesPosition(prefixLength: Int) throws {
  var writer = BitWriter(minimumCapacity: 0)

  writer.writeBits(0xB6, count: prefixLength)
  writer.writeHuffmanCode(.max, bitCount: 0)
  writer.writeBits(UInt8(0xB6) >> prefixLength, count: 8 - prefixLength)
  let output = writer.finish()

  try expectBitWriterBytes(output, [0xB6])
}

@Test func bitWriterWritesCanonicalHuffmanCodesForAABAndTheEndMarker() throws {
  var frequencies = [Int](repeating: 0, count: 286)
  frequencies[65] = 2
  frequencies[66] = 1
  frequencies[256] = 1
  let lengths = huffmanCodeLengths(frequencies: frequencies)
  let codes = canonicalHuffmanCodes(lengths: lengths)
  var writer = BitWriter(minimumCapacity: 0)

  for symbol in [65, 65, 66, 256] {
    let code = try #require(codes[symbol])
    writer.writeHuffmanCode(code, bitCount: lengths[symbol])
  }
  let output = writer.finish()

  // Codes 0, 0, 10, 11 produce bits 0, 0, 1, 0, 1, 1, then zero padding.
  try expectBitWriterBytes(output, [0x34])
}

// Fixed codes from RFC 1951, section 3.2.6; each expected output is zero-padded.
@Test(arguments: [
  (UInt32(0), [UInt8(0x0C)]),
  (UInt32(1), [UInt8(0x8C)]),
  (UInt32(65), [UInt8(0x8E)]),
  (UInt32(143), [UInt8(0xFD)]),
  (UInt32(144), [UInt8(0x13), 0x00]),
  (UInt32(145), [UInt8(0x13), 0x01]),
  (UInt32(255), [UInt8(0xFF), 0x01]),
  (UInt32(256), [UInt8(0x00)]),
  (UInt32(257), [UInt8(0x40)]),
  (UInt32(279), [UInt8(0x74)]),
  (UInt32(280), [UInt8(0x03)]),
  (UInt32(281), [UInt8(0x83)]),
  (UInt32(285), [UInt8(0xA3)])
] as [(symbol: UInt32, expected: [UInt8])])
func bitWriterWritesExactFixedHuffmanSymbolBytes(
  testCase: (symbol: UInt32, expected: [UInt8])
) throws {
  var writer = BitWriter(minimumCapacity: 0)

  try writer.writeFixedLiteralLengthSymbol(testCase.symbol)
  let output = writer.finish()

  try expectBitWriterBytes(output, testCase.expected)
}

@Test(
  arguments: 0...7,
  [
    (UInt32(65), UInt32(0x8E), 8),
    (UInt32(145), UInt32(0x113), 9),
    (UInt32(257), UInt32(0x40), 7),
    (UInt32(285), UInt32(0xA3), 8)
  ]
)
func bitWriterFixedHuffmanSymbolsPreserveAdjacentFieldsAtEveryBitOffset(
  bitOffset: Int,
  testCase: (symbol: UInt32, packedCode: UInt32, bitCount: Int)
) throws {
  var writer = BitWriter(minimumCapacity: 0)

  writer.writeBits(0xFF, count: bitOffset)
  try writer.writeFixedLiteralLengthSymbol(testCase.symbol)
  writer.writeBits(0b101, count: 3)
  let output = writer.finish()

  let prefix = (UInt32(1) << bitOffset) - 1
  let packed = prefix | (testCase.packedCode << bitOffset)
    | (UInt32(0b101) << (bitOffset + testCase.bitCount))
  let byteCount = (bitOffset + testCase.bitCount + 3 + 7) / 8
  let expected = (0..<byteCount).map { UInt8(truncatingIfNeeded: packed >> ($0 * 8)) }
  try expectBitWriterBytes(output, expected)
}

@Test func bitWriterWritesEveryFixedHuffmanSymbolWithoutPaddingBetweenSymbols() throws {
  var writer = BitWriter(minimumCapacity: 1)
  for symbol: UInt32 in 0...285 {
    try writer.writeFixedLiteralLengthSymbol(symbol)
  }
  let output = writer.finish()

  // All 286 valid symbols occupy exactly 2,376 bits, or 297 bytes.
  #expect(output.count == 297)
  var reader = BitReader(output.span.bytes)
  for symbol: UInt32 in 0...285 {
    #expect(try reader.readFixedLiteralLengthSymbol() == symbol, "Symbol \(symbol)")
  }
  #expect(reader.byteOffset == 297)
  #expect(reader.bitOffset == 0)
}

@Test(arguments: [UInt32(286), 287, 288, 511, 0xFFFF, .max], [0, 3, 8])
func bitWriterRejectsInvalidFixedHuffmanSymbolsWithoutChangingOutput(
  symbol: UInt32, prefixLength: Int
) throws {
  var writer = BitWriter(minimumCapacity: 0)
  let bits: [UInt8] = [0, 1, 1, 0, 1, 1, 0, 1]
  for bit in bits.prefix(prefixLength) {
    try writer.writeBit(bit)
  }

  #expect(throws: BitWriterError.reserved) {
    try writer.writeFixedLiteralLengthSymbol(symbol)
  }

  for bit in bits.dropFirst(prefixLength) {
    try writer.writeBit(bit)
  }
  try writer.writeFixedLiteralLengthSymbol(65)
  let output = writer.finish()

  try expectBitWriterBytes(output, [0xB6, 0x8E])
}

// These complete block fixtures were independently checked with C zlib;
// they also appear in inflateDecodesFixedHuffmanLiterals.
@Test(arguments: [
  ([UInt8](), [UInt8(0x03), 0x00]),
  ([UInt8(0x41)], [UInt8(0x73), 0x04, 0x00]),
  ([UInt8(0x00), 0x8F, 0x90, 0xFF], [UInt8(0x63), 0xE8, 0x9F, 0xF0, 0x1F, 0x00])
])
func bitWriterBuildsKnownFixedHuffmanBlockFixtures(
  testCase: (literals: [UInt8], expected: [UInt8])
) throws {
  var writer = BitWriter(minimumCapacity: 0)

  writer.writeBits(0b011, count: 3)  // Final block, fixed Huffman coding.
  for literal in testCase.literals {
    try writer.writeFixedLiteralLengthSymbol(UInt32(literal))
  }
  try writer.writeFixedLiteralLengthSymbol(256)
  let output = writer.finish()

  try expectBitWriterBytes(output, testCase.expected)
}
