import Testing
import Zlib

@Test func inflateReturnsAnArrayTheCallerCanMutateAndGrow() throws {
  let input: [UInt8] = [0x01, 0x01, 0x00, 0xFE, 0xFF, 0x41]
  var output: UniqueArray<UInt8> = try ZLib.inflate(input: input.span)

  output[0] = 0x42
  output.append(0x43)

  #expect(output.count == 2)
  #expect(output[0] == 0x42)
  #expect(output[1] == 0x43)
}

@Test func inflateStoredBlockReturnsBytesThatOutliveInput() throws {
  let output: UniqueArray<UInt8>
  do {
    let input: [UInt8] = [0xF9, 0x03, 0x00, 0xFC, 0xFF, 0x41, 0x42, 0x43]
    output = try ZLib.inflate(input: input.span)
  }

  let bytes = output.span
  try #require(bytes.count == 3)
  #expect(bytes[0] == 0x41)
  #expect(bytes[1] == 0x42)
  #expect(bytes[2] == 0x43)
}

@Test func inflateReadsMultipleStoredBlocks() throws {
  let input: [UInt8] = [
    0x00, 0x02, 0x00, 0xFD, 0xFF, 0x41, 0x42,
    0x01, 0x01, 0x00, 0xFE, 0xFF, 0x43
  ]

  let output = try ZLib.inflate(input: input.span)

  let bytes = output.span
  try #require(bytes.count == 3)
  #expect(bytes[0] == 0x41)
  #expect(bytes[1] == 0x42)
  #expect(bytes[2] == 0x43)
}

@Test func inflateAcceptsAnEmptyStoredBlock() throws {
  let input: [UInt8] = [0x01, 0x00, 0x00, 0xFF, 0xFF]

  let output = try ZLib.inflate(input: input.span)

  #expect(output.span.count == 0)
}

@Test(arguments: [UInt8(0x04), 0x05])
func inflateRejectsUnsupportedDynamicHuffmanBlocks(header: UInt8) {
  let input: [UInt8] = [header]

  #expect(throws: BitReaderError.unsupportedBlockType) {
    _ = try ZLib.inflate(input: input.span)
  }
}

@Test(arguments: [
  [UInt8(0x07)],
  [UInt8(0x01), 0x01, 0x00, 0xFF, 0xFF, 0x41]
])
func inflateRejectsMalformedInput(input: [UInt8]) {
  #expect(throws: BitReaderError.invalid) {
    _ = try ZLib.inflate(input: input.span)
  }
}

@Test(arguments: [
  [UInt8](),
  [UInt8(0x01)],
  [UInt8(0x01), 0x03, 0x00, 0xFC],
  [UInt8(0x01), 0x03, 0x00, 0xFC, 0xFF, 0x41, 0x42],
  [UInt8(0x00), 0x00, 0x00, 0xFF, 0xFF]
])
func inflateRejectsTruncatedStreams(input: [UInt8]) {
  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    _ = try ZLib.inflate(input: input.span)
  }
}

@Test(arguments: [
  [UInt8(0x01), 0x01, 0x00, 0xFE, 0xFF, 0x41, 0x07],
  [UInt8(0x73), 0x04, 0x00, 0x07]
])
func inflateStopsAtTheFinalBlock(input: [UInt8]) throws {
  let output = try ZLib.inflate(input: input.span)

  let bytes = output.span
  try #require(bytes.count == 1)
  #expect(bytes[0] == 0x41)
}

@Test(arguments: [
  (255, [UInt8(0xFF), 0x00, 0x00, 0xFF]),
  (256, [UInt8(0x00), 0x01, 0xFF, 0xFE]),
  (257, [UInt8(0x01), 0x01, 0xFE, 0xFE]),
  (32_768, [UInt8(0x00), 0x80, 0xFF, 0x7F]),
  (32_769, [UInt8(0x01), 0x80, 0xFE, 0x7F]),
  (65_535, [UInt8(0xFF), 0xFF, 0x00, 0x00])
])
func inflateHandlesStoredLengthBoundaries(testCase: (length: Int, fields: [UInt8])) throws {
  let payload = (0..<testCase.length).map { UInt8(truncatingIfNeeded: $0) }
  let input: [UInt8] = [0x01] + testCase.fields + payload

  let output = try ZLib.inflate(input: input.span)

  let bytes = output.span
  try #require(bytes.count == payload.count)
  let allBytesMatch = payload.indices.allSatisfy { bytes[$0] == payload[$0] }
  #expect(allBytesMatch)
}

@Test func inflateConcatenatesMaximumSizeStoredBlocks() throws {
  let firstPayload = (0..<65_535).map { UInt8(truncatingIfNeeded: $0) }
  let secondPayload = (0..<65_535).map { UInt8(truncatingIfNeeded: $0 + 127) }
  let firstBlock: [UInt8] = [0x00, 0xFF, 0xFF, 0x00, 0x00] + firstPayload
  let secondBlock: [UInt8] = [0x01, 0xFF, 0xFF, 0x00, 0x00] + secondPayload
  let input = firstBlock + secondBlock
  let expected = firstPayload + secondPayload

  let output = try ZLib.inflate(input: input.span)

  let bytes = output.span
  try #require(bytes.count == 131_070)
  let allBytesMatch = expected.indices.allSatisfy { bytes[$0] == expected[$0] }
  #expect(allBytesMatch)
}

@Test func inflateHandlesEmptyBlocksBeforeBetweenAndAfterPayloads() throws {
  let input: [UInt8] = [
    0x00, 0x00, 0x00, 0xFF, 0xFF,  // Empty, non-final.
    0x00, 0x02, 0x00, 0xFD, 0xFF, 0x41, 0x42,  // "AB", non-final.
    0x00, 0x00, 0x00, 0xFF, 0xFF,  // Empty, non-final.
    0x00, 0x01, 0x00, 0xFE, 0xFF, 0x43,  // "C", non-final.
    0x01, 0x00, 0x00, 0xFF, 0xFF  // Empty, final.
  ]

  let output = try ZLib.inflate(input: input.span)

  let bytes = output.span
  try #require(bytes.count == 3)
  #expect(bytes[0] == 0x41)
  #expect(bytes[1] == 0x42)
  #expect(bytes[2] == 0x43)
}

@Test(arguments: 0...31)
func inflateIgnoresEveryStoredBlockPaddingPattern(padding: Int) throws {
  let header = (UInt8(padding) << 3) | 1
  let input: [UInt8] = [header, 0x03, 0x00, 0xFC, 0xFF, 0x00, 0x80, 0xFF]

  let output = try ZLib.inflate(input: input.span)

  let bytes = output.span
  try #require(bytes.count == 3)
  #expect(bytes[0] == 0x00)
  #expect(bytes[1] == 0x80)
  #expect(bytes[2] == 0xFF)
}

@Test(arguments: 0..<15)
func inflateRejectsEveryIncompletePrefixOfMultipleBlocks(prefixLength: Int) {
  let complete: [UInt8] = [
    0x00, 0x02, 0x00, 0xFD, 0xFF, 0x41, 0x42,
    0x01, 0x03, 0x00, 0xFC, 0xFF, 0x43, 0x44, 0x45
  ]
  let input = Array(complete.prefix(prefixLength))

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    _ = try ZLib.inflate(input: input.span)
  }
}

@Test(arguments: [
  ([UInt8(0x02)], BitReaderError.unexpectedEndOfInput),
  ([UInt8(0x03)], BitReaderError.unexpectedEndOfInput),
  ([UInt8(0x04)], BitReaderError.unsupportedBlockType),
  ([UInt8(0x05)], BitReaderError.unsupportedBlockType),
  ([UInt8(0x06)], BitReaderError.invalid),
  ([UInt8(0x07)], BitReaderError.invalid),
  ([UInt8(0x01), 0x01, 0x00, 0xFF, 0xFF, 0x42], BitReaderError.invalid)
])
func inflateReportsErrorsInLaterBlocks(testCase: (suffix: [UInt8], error: BitReaderError)) {
  let firstBlock: [UInt8] = [0x00, 0x01, 0x00, 0xFE, 0xFF, 0x41]
  let input = firstBlock + testCase.suffix

  #expect(throws: testCase.error) {
    _ = try ZLib.inflate(input: input.span)
  }
}

@Test func inflateReadsOnlyTheSuppliedSpanWithinAnAllocation() throws {
  let allocation: [UInt8] = [
    0xDE, 0xAD,
    0x01, 0x03, 0x00, 0xFC, 0xFF, 0x41, 0x42, 0x43,
    0xBE, 0xEF
  ]
  let input = allocation.span.extracting(2..<10)

  let output = try ZLib.inflate(input: input)

  let bytes = output.span
  try #require(bytes.count == 3)
  #expect(bytes[0] == 0x41)
  #expect(bytes[1] == 0x42)
  #expect(bytes[2] == 0x43)
}

@Test func inflateRejectsATruncatedSpanDespiteMoreBytesInTheAllocation() {
  let allocation: [UInt8] = [0x01, 0x03, 0x00, 0xFC, 0xFF, 0x41, 0x42, 0x43]
  let input = allocation.span.extracting(0..<7)

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    _ = try ZLib.inflate(input: input)
  }
}

// Fixed Huffman fixtures below were checked independently with C zlib.
@Test(arguments: [
  ([UInt8(0x03), 0x00], [UInt8]()),
  ([UInt8(0x73), 0x04, 0x00], Array("A".utf8)),
  ([UInt8(0x63), 0xE8, 0x9F, 0xF0, 0x1F, 0x00], [UInt8(0x00), 0x8F, 0x90, 0xFF])
])
func inflateDecodesFixedHuffmanLiterals(testCase: (input: [UInt8], expected: [UInt8])) throws {
  let output = try ZLib.inflate(input: testCase.input.span)

  let bytes = output.span
  try #require(bytes.count == testCase.expected.count)
  let allBytesMatch = testCase.expected.indices.allSatisfy { bytes[$0] == testCase.expected[$0] }
  #expect(allBytesMatch)
}

@Test(arguments: [
  // "ABC", followed by length 3 and distance 3.
  ([UInt8(0x73), 0x74, 0x72, 0x06, 0x22, 0x00], Array("ABCABC".utf8)),
  // Length symbol 269 + extra value 2 = 21; distance code 5 + extra value 1 = 8.
  (
    [UInt8(0x73), 0x74, 0x72, 0x76, 0x71, 0x75, 0x73, 0xF7, 0xC0, 0x4A, 0x03, 0x00],
    Array("ABCDEFGHABCDEFGHABCDEFGHABCDE".utf8)
  ),
  // One "Z", followed by an overlapping length-258, distance-1 match.
  ([UInt8(0x8B), 0x1A, 0x05, 0x00], Array(repeating: UInt8(0x5A), count: 259))
])
func inflateExpandsFixedHuffmanMatches(testCase: (input: [UInt8], expected: [UInt8])) throws {
  let output = try ZLib.inflate(input: testCase.input.span)

  let bytes = output.span
  try #require(bytes.count == testCase.expected.count)
  let allBytesMatch = testCase.expected.indices.allSatisfy { bytes[$0] == testCase.expected[$0] }
  #expect(allBytesMatch)
}

@Test func inflateKeepsHistoryAcrossStoredAndFixedBlocks() throws {
  let input: [UInt8] = [
    0x00, 0x03, 0x00, 0xFC, 0xFF, 0x41, 0x42, 0x43,  // Stored "ABC".
    0x03, 0x22, 0x00  // Fixed block: length 3, distance 3, end-of-block.
  ]

  let output = try ZLib.inflate(input: input.span)

  let expected = Array("ABCABC".utf8)
  let bytes = output.span
  try #require(bytes.count == expected.count)
  let allBytesMatch = expected.indices.allSatisfy { bytes[$0] == expected[$0] }
  #expect(allBytesMatch)
}

@Test(arguments: [
  // Fixed "A", followed by a stored "B" block whose header starts at bit offset 2.
  [UInt8(0x72), 0x04, 0x04, 0x01, 0x00, 0xFE, 0xFF, 0x42],
  // Fixed "A", followed by a fixed "B" block whose header starts at bit offset 2.
  [UInt8(0x72), 0x04, 0xCC, 0x09, 0x00]
])
func inflateReadsBlockHeadersAfterUnalignedFixedBlocks(input: [UInt8]) throws {
  let output = try ZLib.inflate(input: input.span)

  let bytes = output.span
  try #require(bytes.count == 2)
  #expect(bytes[0] == 0x41)
  #expect(bytes[1] == 0x42)
}

@Test(arguments: [
  [UInt8(0x1B), 0x03],  // Literal/length symbol 286.
  [UInt8(0x1B), 0x07],  // Literal/length symbol 287.
  [UInt8(0x73), 0x04, 0x3E],  // Distance code 30 after literal "A" and length 3.
  [UInt8(0x73), 0x04, 0x7E]  // Distance code 31 after literal "A" and length 3.
])
func inflateRejectsForbiddenFixedHuffmanSymbols(input: [UInt8]) {
  #expect(throws: BitReaderError.forbiddenSymbol) {
    _ = try ZLib.inflate(input: input.span)
  }
}

@Test(arguments: [
  [UInt8(0x03), 0x02, 0x00],  // Match distance 1 with empty history.
  [UInt8(0x73), 0x74, 0x72, 0x06, 0x62, 0x00]  // Match distance 4 after only "ABC".
])
func inflateRejectsFixedMatchesBeyondAvailableHistory(input: [UInt8]) {
  #expect(throws: BitReaderError.invalid) {
    _ = try ZLib.inflate(input: input.span)
  }
}

@Test(arguments: 0..<12)
func inflateRejectsEveryTruncatedFixedMatchPrefix(prefixLength: Int) {
  let complete: [UInt8] = [0x73, 0x74, 0x72, 0x76, 0x71, 0x75, 0x73, 0xF7, 0xC0, 0x4A, 0x03, 0x00]
  let input = Array(complete.prefix(prefixLength))

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    _ = try ZLib.inflate(input: input.span)
  }
}
